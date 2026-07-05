#include "postprocess.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "optix_stubs.h"
#include "optix_function_table_definition.h"


__constant__ float bloom_weights[5] = {0.2270f, 0.1945f, 0.1216f, 0.0540f, 0.0162f};
static void optix_check(OptixResult res, const char *file, int line) {
    if (res != OPTIX_SUCCESS) {
        fprintf(stderr, "OptiX error %s:%d: %s\n", file, line, optixGetErrorString(res));
        exit(EXIT_FAILURE);
    }
}
#define OPTIX_CHECK(x) optix_check((x), __FILE__, __LINE__)

static void optix_log_cb(unsigned int level, const char *tag, const char *msg, void *cbdata) {
    /* unused */
    if (level <= 3)
        fprintf(stderr, "[OptiX][%s] %s\n", tag, msg);
}

/* horizontal bloom pass: blur light-source pixels along x into bloom_buf */
__global__ void bloom_horizontal(const float3 *src, float3 *dst,
                                  const float *mask, int width, int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= width || y >= height) return;

    const float *w = bloom_weights;
    float3 acc = make_float3(0.0f, 0.0f, 0.0f);
    float total = 0.0f;

    for (int dx = -4; dx <= 4; dx++) {
        int nx = x + dx;
        if (nx < 0 || nx >= width) continue;
        int idx = y * width + nx;
        if (mask[idx] == 0.0f) continue;
        float weight = w[dx < 0 ? -dx : dx];
        acc.x += src[idx].x * weight;
        acc.y += src[idx].y * weight;
        acc.z += src[idx].z * weight;
        total += weight;
    }
    if (total > 0.0f) {
        acc.x /= total; acc.y /= total; acc.z /= total;
    }
    dst[y * width + x] = acc;
}

/* vertical bloom pass: blur along y into bloom_tmp (separate buffer, no race) */
__global__ void bloom_vertical(const float3 *src, float3 *dst,
                                int width, int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= width || y >= height) return;

    const float *w = bloom_weights;
    float3 acc = make_float3(0.0f, 0.0f, 0.0f);
    float total = 0.0f;

    for (int dy = -4; dy <= 4; dy++) {
        int ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        float weight = w[dy < 0 ? -dy : dy];
        float3 p = src[ny * width + x];
        acc.x += p.x * weight;
        acc.y += p.y * weight;
        acc.z += p.z * weight;
        total += weight;
    }
    if (total > 0.0f) {
        acc.x /= total; acc.y /= total; acc.z /= total;
    }
    dst[y * width + x] = acc;
}

/* tone map + gamma, run after denoising and bloom */
__global__ void tonemap_gamma_kernel(const float3 *hdr, const float3 *bloom,
                                      uchar4 *ldr, int width, int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= width || y >= height) return;

    int idx = y * width + x;
    float3 p = hdr[idx];

    /* add bloom contribution */
    p.x += bloom[idx].x;
    p.y += bloom[idx].y;
    p.z += bloom[idx].z;

    /* skip Reinhard, values already in 0-1 range */
    float r = p.x;
    float g = p.y;
    float b = p.z;

    float inv_gamma = 1.0f / 2.2f;
    r = __powf(fmaxf(r, 0.0f), inv_gamma);
    g = __powf(fmaxf(g, 0.0f), inv_gamma);
    b = __powf(fmaxf(b, 0.0f), inv_gamma);

    ldr[idx] = make_uchar4(
        (unsigned char) fminf(r * 255.0f + 0.5f, 255.0f),
        (unsigned char) fminf(g * 255.0f + 0.5f, 255.0f),
        (unsigned char) fminf(b * 255.0f + 0.5f, 255.0f),
        255
    );
}

void postprocess_init(FrameBuffers *fb, DenoiserState *ds, int width, int height) {
    memset(ds, 0, sizeof(DenoiserState));
    fb->width  = width;
    fb->height = height;

    size_t npix = (size_t) width * height;
    CUDA_CHECK(cudaMalloc(&fb->ldr_buf, npix * sizeof(uchar4)));
    CUDA_CHECK(cudaMalloc(&fb->hdr_buf,      npix * sizeof(float3)));
    CUDA_CHECK(cudaMalloc(&fb->hdr_denoised, npix * sizeof(float3)));
    CUDA_CHECK(cudaMalloc(&fb->bloom_buf,    npix * sizeof(float3)));
    CUDA_CHECK(cudaMalloc(&fb->bloom_tmp,    npix * sizeof(float3)));
    CUDA_CHECK(cudaMalloc(&fb->light_mask, npix * sizeof(float)));

    CUDA_CHECK(cudaFree(0));
    OPTIX_CHECK(optixInit());

    OptixDeviceContextOptions ctx_opts;
    memset(&ctx_opts, 0, sizeof(ctx_opts));
    ctx_opts.logCallbackFunction = optix_log_cb;
    ctx_opts.logCallbackLevel    = 4;
    OPTIX_CHECK(optixDeviceContextCreate(0, &ctx_opts, &ds->context));

    OptixDenoiserOptions denoiser_opts;
    memset(&denoiser_opts, 0, sizeof(denoiser_opts));
    denoiser_opts.guideAlbedo = 0;
    denoiser_opts.guideNormal = 0;
    OPTIX_CHECK(optixDenoiserCreate(ds->context,
                                    OPTIX_DENOISER_MODEL_KIND_HDR,
                                    &denoiser_opts, &ds->denoiser));

    OPTIX_CHECK(optixDenoiserComputeMemoryResources(ds->denoiser,
                                                    (unsigned) width,
                                                    (unsigned) height,
                                                    &ds->sizes));

    CUDA_CHECK(cudaMalloc((void **) &ds->state_buf,   ds->sizes.stateSizeInBytes));
    CUDA_CHECK(cudaMalloc((void **) &ds->scratch_buf, ds->sizes.withoutOverlapScratchSizeInBytes));
    CUDA_CHECK(cudaMalloc((void **) &ds->intensity,   sizeof(float)));

    OPTIX_CHECK(optixDenoiserSetup(ds->denoiser, 0,
                                   (unsigned) width, (unsigned) height,
                                   ds->state_buf,    ds->sizes.stateSizeInBytes,
                                   ds->scratch_buf,  ds->sizes.withoutOverlapScratchSizeInBytes));
    ds->ready = 1;
}

void postprocess_cleanup(FrameBuffers *fb, DenoiserState *ds) {
    if (fb->hdr_buf)      { cudaFree(fb->hdr_buf);      fb->hdr_buf      = NULL; }
    if (fb->hdr_denoised) { cudaFree(fb->hdr_denoised); fb->hdr_denoised = NULL; }
    if (fb->bloom_buf)    { cudaFree(fb->bloom_buf);    fb->bloom_buf    = NULL; }
    if (fb->bloom_tmp)    { cudaFree(fb->bloom_tmp);    fb->bloom_tmp    = NULL; }
    if (fb->light_mask)   { cudaFree(fb->light_mask);   fb->light_mask   = NULL; }
    if (fb->ldr_buf) {
        cudaFree(fb->ldr_buf);
    }

    if (ds->ready) {
        cudaFree((void *) ds->intensity);
        cudaFree((void *) ds->scratch_buf);
        cudaFree((void *) ds->state_buf);
        optixDenoiserDestroy(ds->denoiser);
        optixDeviceContextDestroy(ds->context);
        ds->ready = 0;
    }
}

void postprocess_denoise(FrameBuffers *fb, DenoiserState *ds) {
    if (!ds->ready) return;

    OptixDenoiserLayer layer;
    memset(&layer, 0, sizeof(layer));
    layer.input.data               = (CUdeviceptr) fb->hdr_buf;
    layer.input.width              = (unsigned) fb->width;
    layer.input.height             = (unsigned) fb->height;
    layer.input.rowStrideInBytes   = (unsigned) (fb->width * sizeof(float3));
    layer.input.pixelStrideInBytes = sizeof(float3);
    layer.input.format             = OPTIX_PIXEL_FORMAT_FLOAT3;
    layer.output = layer.input;
    layer.output.data = (CUdeviceptr) fb->hdr_denoised;

    OPTIX_CHECK(optixDenoiserComputeIntensity(ds->denoiser, 0, &layer.input,
                                              ds->intensity, ds->scratch_buf,
                                              ds->sizes.withoutOverlapScratchSizeInBytes));

    OptixDenoiserParams params;
    memset(&params, 0, sizeof(params));
    params.hdrIntensity = ds->intensity;
    params.blendFactor  = 0.0f;
    OptixDenoiserGuideLayer guide;
    memset(&guide, 0, sizeof(guide));

    OPTIX_CHECK(optixDenoiserInvoke(ds->denoiser, 0, &params,
                                    ds->state_buf, ds->sizes.stateSizeInBytes,
                                    &guide, &layer, 1, 0, 0,
                                    ds->scratch_buf,
                                    ds->sizes.withoutOverlapScratchSizeInBytes));
    CUDA_CHECK(cudaDeviceSynchronize());
}

void postprocess_bloom(FrameBuffers *fb) {
    size_t npix = (size_t) fb->width * fb->height;
    CUDA_CHECK(cudaMemset(fb->bloom_tmp, 0, npix * sizeof(float3)));

    dim3 block = {16, 16, 1};
    dim3 grid = {
        ((unsigned) fb->width  + block.x - 1) / block.x,
        ((unsigned) fb->height + block.y - 1) / block.y,
        1
    };
    bloom_horizontal<<<grid, block>>>(fb->hdr_denoised, fb->bloom_buf,
                                      fb->light_mask, fb->width, fb->height);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    bloom_vertical<<<grid, block>>>(fb->bloom_buf, fb->bloom_tmp,
                                    fb->width, fb->height);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());
}

void postprocess_tonemap_gamma(FrameBuffers *fb) {
    dim3 block = {16, 16, 1};
    dim3 grid = {
        ((unsigned) fb->width  + block.x - 1) / block.x,
        ((unsigned) fb->height + block.y - 1) / block.y,
        1
    };
    tonemap_gamma_kernel<<<grid, block>>>(fb->hdr_denoised, fb->bloom_tmp,
                                          fb->ldr_buf, fb->width, fb->height);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());
}

void postprocess_run(FrameBuffers *fb, DenoiserState *ds, bool use_denoising, bool use_bloom) {
    if (use_denoising) postprocess_denoise(fb, ds);
    else CUDA_CHECK(cudaMemcpy(fb->hdr_denoised, fb->hdr_buf, fb->width * fb->height * sizeof(float3), cudaMemcpyDeviceToDevice));
    if (use_bloom) postprocess_bloom(fb);
    else CUDA_CHECK(cudaMemset(fb->bloom_tmp, 0, fb->width * fb->height * sizeof(float3))); // zero input array before tonemapping
    postprocess_tonemap_gamma(fb);
}

#define NVJPEG_CHECK(x) do { \
    nvjpegStatus_t _s = (x); \
    if (_s != NVJPEG_STATUS_SUCCESS) { \
        fprintf(stderr, "nvJPEG error %s:%d : %d\n", __FILE__, __LINE__, (int)_s); \
        exit(EXIT_FAILURE); \
    } \
} while (0)

__global__ void uchar4_to_rgb_planar(const uchar4 *src,
                                      unsigned char *r_plane,
                                      unsigned char *g_plane,
                                      unsigned char *b_plane,
                                      int width, int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= width || y >= height) return;
    int idx = y * width + x;
    uchar4 p = src[idx];
    r_plane[idx] = p.x;
    g_plane[idx] = p.y;
    b_plane[idx] = p.z;
}

void postprocess_jpeg_init(FrameBuffers *fb, JpegState *js, int quality) {
    memset(js, 0, sizeof(JpegState));
    js->quality = quality > 0 ? quality : 90;
    size_t npix = (size_t) fb->width * fb->height;
    CUDA_CHECK(cudaMalloc(&fb->jpeg_rgb_buf, npix * 3));
    NVJPEG_CHECK(nvjpegCreateSimple(&js->handle));
    NVJPEG_CHECK(nvjpegEncoderStateCreate(js->handle, &js->enc_state, 0));
    NVJPEG_CHECK(nvjpegEncoderParamsCreate(js->handle, &js->enc_params, 0));
    NVJPEG_CHECK(nvjpegEncoderParamsSetQuality(js->enc_params, js->quality, 0));
    NVJPEG_CHECK(nvjpegEncoderParamsSetOptimizedHuffman(js->enc_params, 1, 0));
    NVJPEG_CHECK(nvjpegEncoderParamsSetSamplingFactors(js->enc_params, NVJPEG_CSS_444, 0));
    js->ready = 1;
}

void postprocess_jpeg_cleanup(FrameBuffers *fb, JpegState *js) {
    if (fb->jpeg_rgb_buf) { cudaFree(fb->jpeg_rgb_buf); fb->jpeg_rgb_buf = NULL; }
    if (js->ready) {
        nvjpegEncoderParamsDestroy(js->enc_params);
        nvjpegEncoderStateDestroy(js->enc_state);
        nvjpegDestroy(js->handle);
        js->ready = 0;
    }
}

void postprocess_save_jpeg(FrameBuffers *fb, JpegState *js, const char *path) {
    if (!js->ready) { fprintf(stderr, "postprocess_save_jpeg: not initialised\n"); return; }
    int width = fb->width, height = fb->height;
    size_t npix = (size_t) width * height;
    dim3 block = {16, 16, 1};
    dim3 grid = {((unsigned)width+15)/16, ((unsigned)height+15)/16, 1};
    unsigned char *r_plane = fb->jpeg_rgb_buf;
    unsigned char *g_plane = fb->jpeg_rgb_buf + npix;
    unsigned char *b_plane = fb->jpeg_rgb_buf + npix * 2;
    uchar4_to_rgb_planar<<<grid, block>>>(fb->ldr_buf, r_plane, g_plane, b_plane, width, height);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());
    nvjpegImage_t img;
    memset(&img, 0, sizeof(img));
    img.channel[0] = r_plane; img.pitch[0] = (unsigned) width;
    img.channel[1] = g_plane; img.pitch[1] = (unsigned) width;
    img.channel[2] = b_plane; img.pitch[2] = (unsigned) width;
    NVJPEG_CHECK(nvjpegEncodeImage(js->handle, js->enc_state, js->enc_params,
                                    &img, NVJPEG_INPUT_RGB, width, height, 0));
    CUDA_CHECK(cudaDeviceSynchronize());
    size_t jpeg_size = 0;
    NVJPEG_CHECK(nvjpegEncodeRetrieveBitstream(js->handle, js->enc_state, NULL, &jpeg_size, 0));
    unsigned char *host_buf = (unsigned char *) malloc(jpeg_size);
    MALLOC_CHECK(host_buf);
    NVJPEG_CHECK(nvjpegEncodeRetrieveBitstream(js->handle, js->enc_state, host_buf, &jpeg_size, 0));
    CUDA_CHECK(cudaDeviceSynchronize());
    FILE *fp = fopen(path, "wb");
    if (!fp) { fprintf(stderr, "cannot open %s\n", path); free(host_buf); return; }
    fwrite(host_buf, 1, jpeg_size, fp);
    fclose(fp);
    free(host_buf);
}
