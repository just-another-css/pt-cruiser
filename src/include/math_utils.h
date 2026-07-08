#ifndef MATHUTILS_H
#define MATHUTILS_H

#include <math.h>
#include <float.h>
#include "constants.h"

__host__ __device__ static __forceinline__ float3 vec_min(float3 a, float3 b) {
    return make_float3(fminf(a.x, b.x),
                       fminf(a.y, b.y),
                       fminf(a.z, b.z));
}

__host__ __device__ static __forceinline__ float3 vec_max(float3 a, float3 b) {
    return make_float3(fmaxf(a.x, b.x),
                       fmaxf(a.y, b.y),
                       fmaxf(a.z, b.z));
}

__host__ __device__ static __forceinline__ float3 vec_cross_prod(float3 vec1, float3 vec2) {
    return make_float3(fmaf(vec1.y, vec2.z, -(vec1.z * vec2.y)),
                       fmaf(vec1.z, vec2.x, -(vec1.x * vec2.z)),
                       fmaf(vec1.x, vec2.y, -(vec1.y * vec2.x)));
}

__host__ __device__ static __forceinline__ float3 scale_vec(float scalar, float3 vec) {
    return make_float3(scalar * vec.x,
                       scalar * vec.y,
                       scalar * vec.z);
}

__device__ static __forceinline__ float2 scale_vec2(float scalar, float2 vec) {
    return make_float2(scalar * vec.x,
                       scalar * vec.y);
}

__host__ __device__ static __forceinline__ void scale_vec_ip(float scalar, float3* vec) {
    vec->x *= scalar;
    vec->y *= scalar;
    vec->z *= scalar;
}

__host__ __device__ static __forceinline__ float3 add_vec(float3 vec1, float3 vec2) {
    return make_float3(vec1.x + vec2.x,
                       vec1.y + vec2.y,
                       vec1.z + vec2.z);
}

__host__ __device__ static __forceinline__ float3 sub_vec(float3 vec1, float3 vec2) {
    return make_float3(vec1.x - vec2.x,
                       vec1.y - vec2.y,
                       vec1.z - vec2.z);
}

__device__ static __forceinline__ float2 sub_vec2(float2 vec1, float2 vec2) {
    return make_float2(vec1.x - vec2.x,
                       vec1.y - vec2.y);
}

__host__ __device__ static __forceinline__ void add_vec_ip(float3* vec1, float3 vec2) {
    vec1->x = vec1->x + vec2.x;
    vec1->y = vec1->y + vec2.y;
    vec1->z = vec1->z + vec2.z;
}

__host__ __device__ static __forceinline__ float3 add3_vec(float3 vec1, float3 vec2, float3 vec3) {
    return make_float3(vec1.x + vec2.x + vec3.x,
                       vec1.y + vec2.y + vec3.y,
                       vec1.z + vec2.z + vec3.z);
}

__device__ static __forceinline__ float2 add3_vec2(float2 vec1, float2 vec2, float2 vec3) {
    return make_float2(vec1.x + vec2.x + vec3.x,
                       vec1.y + vec2.y + vec3.y);
}

__host__ __device__ static __forceinline__ float vec_mag(float3 vec) {
    return sqrtf(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z);
}

__host__ __device__ static __forceinline__ float vec_dot_sqr(float3 vec) {
    return fmaf(vec.x, vec.x, fmaf(vec.y, vec.y, vec.z * vec.z));
}

__host__ __device__ static __forceinline__ float3 norm_vec(float3 vec) {
    return scale_vec(rsqrtf(vec_dot_sqr(vec)), vec);
}

__device__ static __forceinline__ float3 norm_vec_safe(float3 vec) {
    float mag_sqr = vec_dot_sqr(vec); // square of magnitude
    return mag_sqr < FLT_EPSILON ? make_float3(1,0,0) : scale_vec(rsqrtf(mag_sqr), vec); // ensure that magnitude is nonzero before attempting to normalise
}

__host__ __device__ static __forceinline__ void norm_vec_ip(float3* vec) {
    scale_vec_ip(rsqrtf(vec_dot_sqr(*vec)), vec);
}

__host__ __device__ static __forceinline__ float vec_dot_prod(float3 vec1, float3 vec2) {
    return vec1.x * vec2.x +
           vec1.y * vec2.y +
           vec1.z * vec2.z;
}

__device__ static __forceinline__ float3 multiply_vec(float3 vec1, float3 vec2) {
    return make_float3(vec1.x * vec2.x,
                       vec1.y * vec2.y,
                       vec1.z * vec2.z);
}

__device__ static __forceinline__ float3 multiply3_vec(float3 vec1, float3 vec2, float3 vec3) {
    // return make_float3(vec1.x * vec2.x * vec3.x,
    //                    vec1.y * vec2.y * vec3.y,
    //                    vec1.z * vec2.z * vec3.z);
    return multiply_vec(multiply_vec(vec1, vec2), vec3);
}

__device__ static __forceinline__ float3 multiply6_vec(float3 vec1, float3 vec2, float3 vec3, float3 vec4, float3 vec5, float3 vec6) {
    return multiply_vec(multiply3_vec(vec1, vec2, vec3), multiply3_vec(vec4, vec5, vec6));
}

__device__ static __forceinline__ float4 f3_to_f4(float3 f3, float w) {
    return make_float4(f3.x, f3.y, f3.z, w);
}

__device__ static __forceinline__ float3 f4_to_f3(float4 f4) {
    return make_float3(f4.x, f4.y, f4.z);
}

__device__ static __forceinline__ bool zero_vec(float3 vec) {
    return vec.x == 0 && vec.y == 0 && vec.z == 0;
}

__host__ __device__ static __forceinline__ bool nonzero_vec(float3 vec) {
    return vec.x || vec.y || vec.z;
}

__host__ static __forceinline__ float3 vec_rotate(float3 vec, float3 axis, float angle) {
    if (!angle) return vec;
    float cos_angle = cosf(angle);
    return add3_vec(
        scale_vec(cos_angle, vec),
        scale_vec(sinf(angle), vec_cross_prod(axis, vec)),
        scale_vec((1 - cos_angle) * vec_dot_prod(axis, vec), axis)
    );
}

__device__ static __forceinline__ uint64_t lshift_each_bit_3(uint64_t num) {
    num &= 0x1fffffULL;
    num = (num | (num << 32)) & 0x1f00000000ffffULL;
    num = (num | (num << 16)) & 0x1f0000ff0000ffULL;
    num = (num | (num <<  8)) & 0x100f00f00f00f00fULL;
    num = (num | (num <<  4)) & 0x10c30c30c30c30c3ULL;
    num = (num | (num <<  2)) & 0x1249249249249249ULL;
    return num;
}

#endif
