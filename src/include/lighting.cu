#include <cuda_runtime.h>
#include <math_constants.h>
#include "materials.h"
#include "lighting.h"
#include "objects.h"
#include "light_sources.h"
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

#define MAX_N 1000

/* Calculate the throughput multiplier of an outgoing ray
* @param incoming_ray direction of incoming ray
* @param surface_normal float4 
*/
__device__ float calc_next_throughput(float3 incoming_ray, float4 surface_normal, float3 new_ray_dir, int material) {
    if (materials_data.transparencies[material]) { return materials_data.transparencies[material]; }
    // return 1;
    float3 normal = f4_to_f3(surface_normal);
    // if (vec_dot_prod(incoming_ray, normal) < 0) scale_vec_ip(-1.0f, &normal);
    // Calculate BRDF
    float3 perfect_reflection = sub_vec(incoming_ray, scale_vec(2 * vec_dot_prod(incoming_ray, normal), normal));
    float cos_alpha = fabsf(vec_dot_prod(new_ray_dir, perfect_reflection));
    float cos_theta = fabsf(vec_dot_prod(new_ray_dir, normal));

    // Set smoothness max to 0.999 to avoid divide by 0
    float smoothness = fmin(0.999f, materials_data.smoothnesses[material]);
    float roughness = fmin(0.999f, materials_data.roughnesses[material]);
    // float n = (roughness) / (1 - roughness);
    float n = roughness != 0 ? (1 - roughness) / (roughness) : MAX_N;
    float cos_power = powf(cos_alpha, n);
    // BRDF = albedo * (n + 2) * cos_power * 1/2π, albedo ignored
    // float brdf = fmaf(n, cos_power, 2 * cos_power) * TWO_PI_RECIPROCAL;
    float brdf_diffuse = M_1_PIf;
    float brdf_specular = fmaf(n, cos_power, 2 * cos_power) * M_2_PIf;
    float brdf = smoothness * brdf_specular + (1 - smoothness) * brdf_diffuse;

    // Get diffuse 
    float pdf_diffuse = cos_theta * M_1_PIf;

    // Get specular & overall PDF
    float pdf_specular = (n + 1) * cos_power * M_2_PIf;
    float pdf = fmaf(smoothness, pdf_specular, fmaf(-smoothness, pdf_diffuse, pdf_diffuse));
    // float lambert_cosine = fabsf(vec_dot_prod(normal, new_ray_dir));
    // float lambert_cosine = fmaxf(0, vec_dot_prod(normal, new_ray_dir));
    float lambert_cosine = fabsf(vec_dot_prod(normal, new_ray_dir));

    // Add tiny epsilon in case pdf is 0
    float epsilon = 0.001f;

    // if (materials_data.transparencies[material]) {
    //     // if (vec_dot_prod(incoming_ray, normal) > 0) scale_vec_ip(-1.0f, &normal); // always face toward incoming ray
    //     float reflected_intensity = calc_reflected_glass_intensity(new_ray_dir, normal);
    //     // Check reflection or refraction
    //     if (new_ray_normal_angle <= 0) { // reflection
    //         return reflected_intensity;
    //     }
    //     return 1.0f - reflected_intensity;
    // }

    // Return overall throughput
    return brdf * lambert_cosine * __frcp_rn(fmaxf(pdf, epsilon));

}

__device__ float calc_next_throughput_nee(float3 incoming_ray, float4 surface_normal, float3 new_ray_dir, int material) {
    if (materials_data.transparencies[material]) { return 1 - materials_data.transparencies[material]; }
    float3 normal = f4_to_f3(surface_normal);
    if (vec_dot_prod(incoming_ray, normal) > 0) scale_vec_ip(-1.0f, &normal);
    // Calculate BRDF
    float3 perfect_reflection = sub_vec(incoming_ray, scale_vec(2 * vec_dot_prod(incoming_ray, normal), normal));
    float cos_alpha = fmax(0.0f, vec_dot_prod(new_ray_dir, perfect_reflection));

    float smoothness = materials_data.smoothnesses[material];
    float roughness = fmin(0.999f, materials_data.roughnesses[material]); // avoid division by zero
    float n = roughness != 0 ? ((1 - roughness) / roughness) : MAX_N;
    float cos_power = powf(cos_alpha, n);
    float brdf_diffuse = M_1_PIf;
    float brdf_specular = fmaf(n, cos_power, 2 * cos_power) * M_2_PIf;
    float brdf = smoothness * brdf_specular + (1 - smoothness) * brdf_diffuse;

    float lambert_cosine = fabsf(vec_dot_prod(normal, new_ray_dir));

    return brdf * lambert_cosine;
}

// /* Fraction of ray reflected from metal
// * PRE: Rays provided are normalised
// */
// __device__ float get_reflected_metal_intensity(float3 incident_ray, float3 surface_normal) {
//     return schlick_fresnel(incident_ray, surface_normal, METAL_NORMAL_REFLECTION);
// }

#define MAX_ALPHA 1000

__device__ float calc_brdf_pdf_value(int obj_i, int face_i, float3 brdf_ray, float3 specular_ray) {
    int material = objects_dev.meshes[obj_i].materials[face_i];
    if (materials_data.transparencies[material] > 0) return 0; // TODO: compare to TIR and refraction rays
    if (zero_vec(specular_ray)) return 0; // first bounce; no PDF to evaluate
    float smoothness = materials_data.smoothnesses[material];
    float alpha = smoothness == 0 ? 0 : (smoothness != 1 ? fdividef(smoothness, 1 - smoothness) : MAX_ALPHA);
    return smoothness * fdividef(alpha + 1, 2 * CUDART_PI_F) * powf(fabsf(vec_dot_prod(brdf_ray, specular_ray)), alpha) + // reflection ray
           (1 - smoothness) * fabsf(vec_dot_prod(brdf_ray, f4_to_f3(objects_dev.meshes[obj_i].normals[face_i]))) / CUDART_PI_F; // diffuse ray
}

__device__ float calc_nee_pdf_value(int obj_i, int face_i) {
    int light_source_i = light_sources_dev.light_is[obj_i];
    return light_sources_dev.norm_obj_powers[light_source_i] * light_sources_dev.norm_face_powers[light_source_i][light_sources_dev.light_face_is[light_source_i][face_i]];
}

// Return MIS weight using power heuristic with beta = 2
__device__ float calc_dual_importance_sampling_weight(float pdf_value, float alt_pdf_value) {
    pdf_value *= pdf_value;
    return fdividef(pdf_value, pdf_value + alt_pdf_value * alt_pdf_value);
}
