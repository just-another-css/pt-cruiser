#ifndef LIGHTING_H
#define LIGHTING_H

#include "math_utils.h"
#include "materials.h"

#define TWO_PI_RECIPROCAL 0.159154943092

extern __device__ float calc_next_throughput(float3 incoming_ray, float4 surface_normal, float3 new_ray_dir, int material);
extern __device__ float calc_next_throughput_nee(float3 incoming_ray, float4 surface_normal, float3 new_ray_dir, int material);
extern __device__ float calc_brdf_pdf_value(int obj_i, int face_i, float3 brdf_ray, float3 specular_ray);
extern __device__ float calc_nee_pdf_value(int obj_i, int face_i);
extern __device__ float calc_dual_importance_sampling_weight(float pdf_value, float alt_pdf_value);

#endif
