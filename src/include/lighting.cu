#include <cuda_runtime.h>
#include <math_constants.h>
#include "materials.h"
#include "lighting.h"
#include "math_utils.h"

__device__ __forceinline__ float schlick_fresnel(float3 incident_ray, float3 surface_normal, float base_reflection) {
    float cos_angle = fabsf(vec_dot_prod(incident_ray, surface_normal));
    float cos_term = 1.0f - cos_angle;
    float cos_sq = cos_term * cos_term;
    float cos_fifth_pow = cos_sq * cos_sq * cos_term;
    return fmaf((1.0f - base_reflection), cos_fifth_pow, base_reflection);
}

/* Fraction of ray reflected from glass
* PRE: Rays provided are normalised
*/
__device__ __forceinline__ float calc_reflected_glass_intensity(float3 incident_ray, float3 surface_normal) {
    return schlick_fresnel(incident_ray, surface_normal, GLASS_NORMAL_REFLECTION);
}

/* Calculate the throughput multiplier of an outgoing ray
* @param incoming_ray direction of incoming ray
* @param surface_normal float4 
*/
__device__ float calc_next_throughput(float3 incoming_ray, float4 surface_normal, float3 new_ray_dir, Material material) {
    float3 normal = f4_to_f3(surface_normal);
    // Calculate BRDF
    float3 perfect_reflection = sub_vec(incoming_ray, scale_vec(2 * vec_dot_prod(incoming_ray, normal), normal));
    float cos_alpha = fmax(0.0f, vec_dot_prod(new_ray_dir, perfect_reflection));

    // Set smoothness max to 0.999 to avoid divide by 0
    float smoothness = fmin(0.999f, materials_data.smoothnesses[material]);
    float n = (smoothness) / (1.0f - smoothness);
    float cos_power = powf(cos_alpha, n);
    // BRDF = albedo * (n + 2) * cos_power * 1/2π, albedo ignored
    float brdf = fmaf(n, cos_power, 2 * cos_power) * TWO_PI_RECIPROCAL;

    // Get diffuse 
    float pdf_diffuse = fmax(0.0f, vec_dot_prod(normal, new_ray_dir)) / CUDART_PI_F;

    // Get specular & overall PDF
    float pdf_specular = (n + 1) / (2 * CUDART_PI_F) * powf(cos_alpha, n);
    float pdf = fmaf(smoothness, pdf_specular, fmaf(-smoothness, pdf_diffuse, pdf_diffuse));
    float new_ray_normal_angle = vec_dot_prod(normal, new_ray_dir);
    float lambert_cosine = fmax(0.0f, new_ray_normal_angle);

    // Add tiny epsilon in case pdf is 0
    float epsilon = 0.001f;

    if (material == GLASS) {
        // if (vec_dot_prod(incoming_ray, normal) > 0) scale_vec_ip(-1.0f, &normal); // always face toward incoming ray
        float reflected_intensity = calc_reflected_glass_intensity(new_ray_dir, normal);
        // Check reflection or refraction
        if (new_ray_normal_angle <= 0) { // reflection
            return reflected_intensity;
        }
        return 1.0f - reflected_intensity;
    }

    // Return overall throughput
    return brdf * lambert_cosine * __frcp_rn(fmaxf(pdf, epsilon));

}

__device__ float calc_next_throughput_nee(float3 incoming_ray, float4 surface_normal, float3 new_ray_dir, Material material) {
    float3 normal = f4_to_f3(surface_normal);
    if (vec_dot_prod(incoming_ray, normal) > 0) scale_vec_ip(-1.0f, &normal);
    // Calculate BRDF
    float3 perfect_reflection = sub_vec(incoming_ray, scale_vec(2 * vec_dot_prod(incoming_ray, normal), normal));
    float cos_alpha = fmax(0.0f, vec_dot_prod(new_ray_dir, perfect_reflection));

    // Set smoothness max to 0.999 to avoid divide by 0
    float smoothness = fmin(0.999f, materials_data.smoothnesses[material]);
    float n = (smoothness) / (1.0f - smoothness);
    float cos_power = powf(cos_alpha, n);
    // BRDF = albedo * (n + 2) * cos_power * 1/2π, albedo ignored
    float brdf = fmaf(n, cos_power, 2 * cos_power) * TWO_PI_RECIPROCAL;
    float new_ray_normal_angle = vec_dot_prod(normal, new_ray_dir);
    float lambert_cosine = fmax(0.0f, new_ray_normal_angle);

    return brdf * lambert_cosine;
}

// /* Fraction of ray reflected from metal
// * PRE: Rays provided are normalised
// */
// __device__ float get_reflected_metal_intensity(float3 incident_ray, float3 surface_normal) {
//     return schlick_fresnel(incident_ray, surface_normal, METAL_NORMAL_REFLECTION);
// }


