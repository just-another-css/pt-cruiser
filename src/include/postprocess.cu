#include "postprocess.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "optix_stubs.h"
#include "optix_function_table_definition.h"
#include "math_utils.h"

#define OPTIX_CHECK(code) { \
    OptixResult result = code; \
    if (result != OPTIX_SUCCESS) { \
        fprintf(stderr, "OptiX error %s:%d: %s\n", __FILE__, __LINE__, optixGetErrorString(result)); \
        exit(EXIT_FAILURE); \
    } \
}

#define NVJPEG_CHECK(code) { \
    nvjpegStatus_t result = code; \
    if (result != NVJPEG_STATUS_SUCCESS) { \
        fprintf(stderr, "nvJPEG error %s:%d : %d\n", __FILE__, __LINE__, (int)result); \
        exit(EXIT_FAILURE); \
    } \
}

#define BLOOM_SIZE 4
__constant__ float bloom_weights[9] = { 0.0162f, 0.0540f, 0.1216, 0.1945f, 0.2270f, 0.1945f, 0.1216f, 0.0540f, 0.0162f };

#define OPTIMISED_HUFFMAN 1

struct FrameBuffers {
    float3* hdr_buf; // HDR input from renderer
    float3* hdr_denoised; // denoiser output (separate buffer, required by OptiX)
    float3* bloom_tmp;
    float3* bloom_buf; // vertical bloom pass output, fed into tonemap
    float* light_mask; // 1 if pixel is a direct light source, else 0
    uchar4* ldr_buf; // mapped PBO, set each frame
};

struct DenoiserState {
    OptixDeviceContext context;
    OptixDenoiser denoiser;
    OptixDenoiserLayer* layer;
    OptixDenoiserGuideLayer* guide;
    OptixDenoiserParams params;
    OptixDenoiserSizes sizes;
    CUdeviceptr state_buf;
    CUdeviceptr scratch_buf;
    CUdeviceptr intensity;
};

struct nvJpegState {
    unsigned char* rgb_frame; // planar RGB device buffer for nvJPEG
    unsigned char *r, *g, *b; // pointers to R/G/B planes within rgb_frame
    unsigned char* jpeg_buffer;
    size_t jpeg_buffer_size;
    nvjpegHandle_t handle;
    nvjpegEncoderState_t enc_state;
    nvjpegEncoderParams_t enc_params;
    nvjpegImage_t image_desc;
    int quality;
};

PostprocessingState init_postprocessing(int width, int height) {
    PostprocessingState ps = {
        .fb = (FrameBuffers*) malloc(sizeof(FrameBuffers)),
        .width = width,
        .height = height,
        .num_pixels = (size_t) width * height,
    };
    memset(ps.fb, 0, sizeof(FrameBuffers));
    CUDA_CHECK(cudaMalloc(&ps.fb->hdr_denoised, ps.num_pixels * sizeof(float3)));
    CUDA_CHECK(cudaMalloc(&ps.fb->bloom_buf, ps.num_pixels * sizeof(float3)));
    CUDA_CHECK(cudaMemset(ps.fb->bloom_buf, 0, ps.num_pixels * sizeof(float3))); // zero buffer in case bloom is not used
    CUDA_CHECK(cudaMalloc(&ps.fb->light_mask, ps.num_pixels * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&ps.fb->ldr_buf, ps.num_pixels * sizeof(uchar4)));
    ps.frame_input = ps.fb->hdr_denoised;
    ps.light_ints = ps.fb->light_mask;
    ps.frame_output = ps.fb->ldr_buf;
    return ps;
}

static void optix_log_cb(unsigned int level, const char* tag, const char* msg, void* cbdata) {
    if (level <= 3) fprintf(stderr, "[OptiX] %s: %s\n", tag, msg);
}

void init_denoising(PostprocessingState* ps) {
    // allocate separate pre-denoising buffer to write frame to during pathtracing
    CUDA_CHECK(cudaMalloc(&ps->fb->hdr_buf, ps->num_pixels * sizeof(float3)));
    ps->frame_input = ps->fb->hdr_buf;
    ps->ds = (DenoiserState*) malloc(sizeof(DenoiserState));
    DenoiserState* ds = ps->ds;
    memset(ds, 0, sizeof(DenoiserState));

    OPTIX_CHECK(optixInit());
    OptixDeviceContextOptions ctx_opts = (OptixDeviceContextOptions) {
        .logCallbackFunction = optix_log_cb,
        .logCallbackLevel = 3,
    };
    OPTIX_CHECK(optixDeviceContextCreate(0, &ctx_opts, &ds->context));

    OptixDenoiserOptions denoiser_opts = (OptixDenoiserOptions) {
        .guideAlbedo = 0,
        .guideNormal = 0,
    };
    OPTIX_CHECK(optixDenoiserCreate(ds->context, OPTIX_DENOISER_MODEL_KIND_HDR, &denoiser_opts, &ds->denoiser));

    OPTIX_CHECK(optixDenoiserComputeMemoryResources(ds->denoiser, ps->width, ps->height, &ds->sizes));
    CUDA_CHECK(cudaMalloc((void**) &ds->state_buf, ds->sizes.stateSizeInBytes));
    CUDA_CHECK(cudaMalloc((void**) &ds->scratch_buf, ds->sizes.withoutOverlapScratchSizeInBytes));
    CUDA_CHECK(cudaMalloc((void**) &ds->intensity, sizeof(float)));
    OPTIX_CHECK(optixDenoiserSetup(ds->denoiser, 0, ps->width, ps->height, ds->state_buf, ds->sizes.stateSizeInBytes, ds->scratch_buf, ds->sizes.withoutOverlapScratchSizeInBytes));

    ds->layer = (OptixDenoiserLayer*) malloc(sizeof(OptixDenoiserLayer));
    OptixDenoiserLayer* layer = ds->layer;
    memset(layer, 0, sizeof(OptixDenoiserLayer));
    layer->input.data = (CUdeviceptr) ps->fb->hdr_buf;
    layer->input.width = (unsigned) ps->width;
    layer->input.height = (unsigned) ps->height;
    layer->input.rowStrideInBytes = (unsigned) (ps->width * sizeof(float3));
    layer->input.pixelStrideInBytes = sizeof(float3);
    layer->input.format = OPTIX_PIXEL_FORMAT_FLOAT3;
    layer->output = layer->input;
    layer->output.data = (CUdeviceptr) ps->fb->hdr_denoised;

    ds->guide = (OptixDenoiserGuideLayer*) malloc(sizeof(OptixDenoiserGuideLayer));
    memset(ds->guide, 0, sizeof(OptixDenoiserGuideLayer));

    memset(&ds->params, 0, sizeof(OptixDenoiserParams));
    ds->params.blendFactor = 0;
}

void init_bloom(PostprocessingState* ps) {
    ps->use_bloom = true;
    CUDA_CHECK(cudaMalloc(&ps->fb->bloom_tmp, ps->num_pixels * sizeof(float3)));
}

void init_nvjpeg(PostprocessingState* ps, int quality) {
    ps->js = (nvJpegState*) malloc(sizeof(nvJpegState));
    nvJpegState* js = ps->js;
    memset(js, 0, sizeof(nvJpegState));
    js->quality = quality;
    CUDA_CHECK(cudaMalloc(&js->rgb_frame, ps->num_pixels * 3));
    js->r = js->rgb_frame;
    js->g = js->rgb_frame + ps->num_pixels;
    js->b = js->rgb_frame + ps->num_pixels * 2;

    NVJPEG_CHECK(nvjpegCreateSimple(&js->handle));
    NVJPEG_CHECK(nvjpegEncoderStateCreate(js->handle, &js->enc_state, 0));
    NVJPEG_CHECK(nvjpegEncoderParamsCreate(js->handle, &js->enc_params, 0));
    NVJPEG_CHECK(nvjpegEncoderParamsSetQuality(js->enc_params, js->quality, 0));
    NVJPEG_CHECK(nvjpegEncoderParamsSetOptimizedHuffman(js->enc_params, OPTIMISED_HUFFMAN, 0));
    NVJPEG_CHECK(nvjpegEncoderParamsSetSamplingFactors(js->enc_params, NVJPEG_CSS_444, 0));
    memset(&js->image_desc, 0, sizeof(nvjpegImage_t));
    js->image_desc.channel[0] = js->r;
    js->image_desc.channel[1] = js->g;
    js->image_desc.channel[2] = js->b;
    js->image_desc.pitch[0] = ps->width;
    js->image_desc.pitch[1] = ps->width;
    js->image_desc.pitch[2] = ps->width;

    NVJPEG_CHECK(nvjpegEncodeGetBufferSize(js->handle, js->enc_params, ps->width, ps->height, &js->jpeg_buffer_size));
    js->jpeg_buffer = (unsigned char*) malloc(js->jpeg_buffer_size);
}

static void run_denoising(PostprocessingState ps) {
    OptixDenoiserLayer* layer = ps.ds->layer;
    OPTIX_CHECK(optixDenoiserComputeIntensity(ps.ds->denoiser, 0, &layer->input, ps.ds->intensity, ps.ds->scratch_buf, ps.ds->sizes.withoutOverlapScratchSizeInBytes));
    ps.ds->params.hdrIntensity = ps.ds->intensity;
    OPTIX_CHECK(optixDenoiserInvoke(ps.ds->denoiser, 0, &ps.ds->params, ps.ds->state_buf, ps.ds->sizes.stateSizeInBytes, ps.ds->guide, layer, 1, 0, 0, ps.ds->scratch_buf, ps.ds->sizes.withoutOverlapScratchSizeInBytes));
}

/* horizontal bloom pass: blur light-source pixels along x into bloom_tmp */
__global__ void apply_bloom_horizontal(const float3* src, float3* dst, const float* mask, int width, int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= width || y >= height) return;
    float3 acc = make_float3(0,0,0);
    float total = 0;
    int i = y * width + x;
    int j_start_offset = min(BLOOM_SIZE, x);
    int j_limit = i + min(BLOOM_SIZE + 1, width - x);
    for (int j = i - j_start_offset, b = BLOOM_SIZE - j_start_offset; j < j_limit; j++, b++) {
        if (mask[j]) {
            float weight = bloom_weights[b];
            add_vec_ip(&acc, scale_vec(weight, src[j]));
            total += weight;
        }
    }
    if (total > 0) scale_vec_ip(__frcp_rn(total), &acc);
    dst[i] = acc;
}

/* vertical bloom pass: blur along y into bloom_buf (separate buffer, no race) */
__global__ void apply_bloom_vertical(const float3* src, float3* dst, int width, int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= width || y >= height) return;
    float3 acc = make_float3(0,0,0);
    float total = 0;
    const float3* src_x = src + x;
    int j_start_offset = min(BLOOM_SIZE, y);
    int j_limit = (y + min(BLOOM_SIZE + 1, height - y)) * width;
    for (int j = (y - j_start_offset) * width, b = BLOOM_SIZE - j_start_offset; j < j_limit; j += width, b++) {
        float weight = bloom_weights[b];
        add_vec_ip(&acc, scale_vec(weight, src_x[j]));
        total += weight;
    }
    if (total > 0) scale_vec_ip(__frcp_rn(total), &acc);
    dst[y * width + x] = acc;
}

static void run_bloom(PostprocessingState ps) {
    dim3 block = { 16, 16 };
    dim3 grid = {
        (ps.width + block.x - 1) / block.x,
        (ps.height + block.y - 1) / block.y
    };
    apply_bloom_horizontal<<<grid, block>>>(ps.fb->hdr_denoised, ps.fb->bloom_tmp, ps.fb->light_mask, ps.width, ps.height);
    apply_bloom_vertical<<<grid, block>>>(ps.fb->bloom_tmp, ps.fb->bloom_buf, ps.width, ps.height);
    CUDA_CHECK(cudaGetLastError());
}

// gamma correction without bloom
__global__ void apply_gamma(const float3* hdr, uchar4* ldr, size_t num_pixels) {
    size_t x = blockIdx.x * blockDim.x + threadIdx.x;
    if (x >= num_pixels) return;
    float3 p = pow_vec(hdr[x], 1/2.2f);
    ldr[x] = make_uchar4(
        (unsigned char) min(fmaf(p.x, 255, 0.5f), 255.0f),
        (unsigned char) min(fmaf(p.y, 255, 0.5f), 255.0f),
        (unsigned char) min(fmaf(p.z, 255, 0.5f), 255.0f),
        255
    );
}

// gamma correction, applied after combining pixel buffer with bloom buffer
__global__ void apply_gamma_wbloom(const float3* hdr, const float3* bloom, uchar4* ldr, size_t num_pixels) {
    size_t x = blockIdx.x * blockDim.x + threadIdx.x;
    if (x >= num_pixels) return;
    float3 p = pow_vec(add_vec(hdr[x], bloom[x]), 1/2.2f);
    ldr[x] = make_uchar4(
        (unsigned char) min(fmaf(p.x, 255, 0.5f), 255.0f),
        (unsigned char) min(fmaf(p.y, 255, 0.5f), 255.0f),
        (unsigned char) min(fmaf(p.z, 255, 0.5f), 255.0f),
        255
    );
}

static void run_gamma_correction(PostprocessingState ps) {
    dim3 block = { 256 };
    dim3 grid = { (ps.num_pixels + block.x - 1) / block.x };
    if (ps.use_bloom) apply_gamma_wbloom<<<grid, block>>>(ps.fb->hdr_denoised, ps.fb->bloom_buf, ps.frame_output, ps.num_pixels);
    else apply_gamma<<<grid, block>>>(ps.fb->hdr_denoised, ps.frame_output, ps.num_pixels);
    CUDA_CHECK(cudaGetLastError());
}

void run_postprocessing(PostprocessingState ps) {
    if (ps.ds) run_denoising(ps);
    if (ps.use_bloom) run_bloom(ps);
    run_gamma_correction(ps);
}

__global__ void uchar4_to_rgb_planar(const uchar4* src, unsigned char* r_plane, unsigned char* g_plane, unsigned char* b_plane, size_t num_pixels) {
    size_t x = blockIdx.x * blockDim.x + threadIdx.x;
    if (x >= num_pixels) return;
    uchar4 p = src[x];
    r_plane[x] = p.x;
    g_plane[x] = p.y;
    b_plane[x] = p.z;
}

void write_image_nvjpeg(PostprocessingState ps, const char* path) {
    dim3 block = { 256 };
    dim3 grid = { (ps.num_pixels + block.x - 1) / block.x };
    uchar4_to_rgb_planar<<<grid, block>>>(ps.frame_output, ps.js->r, ps.js->g, ps.js->b, ps.num_pixels);
    CUDA_CHECK(cudaDeviceSynchronize());
    NVJPEG_CHECK(nvjpegEncodeImage(ps.js->handle, ps.js->enc_state, ps.js->enc_params, &ps.js->image_desc, NVJPEG_INPUT_RGB, ps.width, ps.height, 0));
    size_t jpeg_buffer_size = ps.js->jpeg_buffer_size;
    NVJPEG_CHECK(nvjpegEncodeRetrieveBitstream(ps.js->handle, ps.js->enc_state, ps.js->jpeg_buffer, &jpeg_buffer_size, 0));
    CUDA_CHECK(cudaDeviceSynchronize());
    FILE* jpeg_file = fopen(path, "wb");
    if (!jpeg_file) { fprintf(stderr, "[!] Error: Cannot open '%s' to write JPEG\n", path); return; }
    fwrite(ps.js->jpeg_buffer, 1, jpeg_buffer_size, jpeg_file);
    fclose(jpeg_file);
}

void clean_postprocessing(PostprocessingState* ps) {
    if (ps->ds) clean_denoising(ps);
    if (ps->js) clean_nvjpeg(ps);
    if (ps->fb) clean_buffers(ps); // clear buffers after all associated denoiser/nvJPEG resources destroyed
    ps->frame_input = NULL;
    ps->light_ints = NULL;
    ps->frame_output = NULL;
}

void clean_buffers(PostprocessingState* ps) {
    FrameBuffers* fb = ps->fb;
    CUDA_CHECK(cudaFree(fb->hdr_buf));
    CUDA_CHECK(cudaFree(fb->hdr_denoised));
    CUDA_CHECK(cudaFree(fb->bloom_tmp));
    CUDA_CHECK(cudaFree(fb->bloom_buf));
    CUDA_CHECK(cudaFree(fb->light_mask));
    CUDA_CHECK(cudaFree(fb->ldr_buf));
    free(fb);
    ps->fb = NULL;
}

void clean_denoising(PostprocessingState* ps) {
    DenoiserState* ds = ps->ds;
    CUDA_CHECK(cudaFree((void*) ds->intensity));
    CUDA_CHECK(cudaFree((void*) ds->scratch_buf));
    CUDA_CHECK(cudaFree((void*) ds->state_buf));
    OPTIX_CHECK(optixDenoiserDestroy(ds->denoiser));
    OPTIX_CHECK(optixDeviceContextDestroy(ds->context));
    free(ds->layer);
    free(ds->guide);
    free(ds);
    ps->ds = NULL;
}

void clean_nvjpeg(PostprocessingState* ps) {
    nvJpegState* js = ps->js;
    CUDA_CHECK(cudaFree(js->rgb_frame));
    NVJPEG_CHECK(nvjpegEncoderParamsDestroy(js->enc_params));
    NVJPEG_CHECK(nvjpegEncoderStateDestroy(js->enc_state));
    NVJPEG_CHECK(nvjpegDestroy(js->handle));
    free(js->jpeg_buffer);
    free(js);
    ps->js = NULL;
}
