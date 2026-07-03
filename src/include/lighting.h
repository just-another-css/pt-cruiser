#ifndef LIGHTING_H
#define LIGHTING_H

#include "math_utils.h"
#include "materials.h"

#define TWO_PI_RECIPROCAL 0.159154943092

extern __device__ float calc_next_throughput(float3 incoming_ray, float4 surface_normal, float3 new_ray_dir, int material);

extern __device__ float calc_next_throughput_nee(float3 incoming_ray, float4 surface_normal, float3 new_ray_dir, int material);

#endif
