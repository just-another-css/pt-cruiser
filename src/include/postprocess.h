#ifndef POSTPROCESS_H
#define POSTPROCESS_H

#include <cuda_runtime.h>
#include <optix.h>
#include <nvjpeg.h>
#include "constants.h"

typedef struct FrameBuffers FrameBuffers;
typedef struct DenoiserState DenoiserState;
typedef struct nvJpegState nvJpegState;

typedef struct {
    FrameBuffers* fb;
    DenoiserState* ds;
    nvJpegState* js;
    float3* frame_input;
    float* light_ints;
    uchar4* frame_output;
    int width;
    int height;
    size_t num_pixels;
    bool use_bloom;
} PostprocessingState;

extern PostprocessingState init_postprocessing(int width, int height);
extern void init_denoising(PostprocessingState* ps);
extern void init_bloom(PostprocessingState* ps);
extern void init_nvjpeg(PostprocessingState* ps, int quality);

extern void run_postprocessing(PostprocessingState ps);
extern void write_image_nvjpeg(PostprocessingState ps, const char* path);

extern void clean_postprocessing(PostprocessingState* ps);
extern void clean_buffers(PostprocessingState* ps);
extern void clean_denoising(PostprocessingState* ps);
extern void clean_nvjpeg(PostprocessingState* ps);

#endif
