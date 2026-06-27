#ifndef COMMON_H
#define COMMON_H

#include <assert.h>

#ifdef __CUDACC__
#include <cuda_runtime.h>
#endif

#include <float.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define X_RES 3848
#define X_RES_HALF (X_RES / 2)
#define Y_RES 2160
#define Y_RES_HALF (Y_RES / 2)
#define TOTAL_PIXELS (X_RES * Y_RES)

#define Y_FOV 0.85

#define CUDA_RAND_SEED 123456

#define MALLOC_CHECK(p) do { \
    if (!p) { \
        fprintf(stderr, "Malloc failed: %s:%i in %s\n", __FILE__, __LINE__, __func__); \
        exit(EXIT_FAILURE); \
    } \
} while (0)

#define CUDA_CHECK(code) do { \
    cudaError_t result = code; \
    if (result != cudaSuccess) { \
        fprintf(stderr, "CUDA Runtime Error: %s:%i:%d = %s\n", __FILE__, __LINE__, result, cudaGetErrorString(result)); \
    } \
} while (0)

#endif
