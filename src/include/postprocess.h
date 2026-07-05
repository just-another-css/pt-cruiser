#ifndef POSTPROCESS_H
#define POSTPROCESS_H

#include <cuda_runtime.h>
#include <optix.h>
#include <nvjpeg.h>
#include "constants.h"

/* light_mask is a per-pixel int array */
typedef struct {
    float3 *hdr_buf; /* HDR input from renderer */
    float3 *hdr_denoised; /* denoiser output (separate buffer, required by OptiX) */
    float3 *bloom_buf;
    float3 *bloom_tmp;    /* vertical bloom pass output, fed into tonemap */
    float *light_mask;   /* 1 if pixel is a direct light source, else 0 */
    uchar4 *ldr_buf;      /* mapped PBO, set each frame */
    unsigned char *jpeg_rgb_buf; /* planar RGB device buffer for nvJPEG */
    int width;
    int height;
} FrameBuffers;

typedef struct {
    OptixDeviceContext context;
    OptixDenoiser denoiser;
    OptixDenoiserSizes sizes;
    CUdeviceptr state_buf;
    CUdeviceptr scratch_buf;
    CUdeviceptr intensity;
    int ready;
} DenoiserState;

extern void postprocess_init(FrameBuffers *fb, DenoiserState *ds, int width, int height);
extern void postprocess_cleanup(FrameBuffers *fb, DenoiserState *ds);
extern void postprocess_denoise(FrameBuffers *fb, DenoiserState *ds);
extern void postprocess_bloom(FrameBuffers *fb);
extern void postprocess_tonemap_gamma(FrameBuffers *fb);
extern void postprocess_run(FrameBuffers *fb, DenoiserState *ds, bool use_denoising, bool use_bloom);

typedef struct {
    nvjpegHandle_t        handle;
    nvjpegEncoderState_t  enc_state;
    nvjpegEncoderParams_t enc_params;
    int                   quality;
    int                   ready;
} JpegState;

extern void postprocess_jpeg_init(FrameBuffers *fb, JpegState *js, int quality);
extern void postprocess_jpeg_cleanup(FrameBuffers *fb, JpegState *js);
extern void postprocess_save_jpeg(FrameBuffers *fb, JpegState *js, const char *path);

#endif /* POSTPROCESS_H */
