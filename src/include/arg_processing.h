#ifndef ARG_PROCESSING_H
#define ARG_PROCESSING_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include "constants.h"

extern void process_args(int argc, char** argv, bool* use_opengl, char** nvjpeg_output, bool* nvjpeg_first, bool* nvjpeg_last, bool* show_frametime, bool* use_denoising, bool* use_bloom, float3* cam_pos, float3* cam_dir, float3* cam_up, float* cam_speed, int* num_frames, int* image_quality);

#endif