#ifndef PATHTRACING_H
#define PATHTRACING_H

#include <curand_kernel.h>

#define EPSILON 1e-3

typedef struct ray_collision ray_collision;

typedef struct {
    int x_res, y_res, pixel_ray_grid_dim, pixels_per_tile; // construction parameters
    int total_pixels, rays_per_pixel, rays_per_tile; // precalculated values
    curandStatePhilox4_32_10_t* rand_states; // CURAND PRNG states
    float3 *top_left_corners, *left_rights, *top_bottoms, *ray_dirs; // ray direction buffers
    float3 *specular_rays, *ray_origins, *ray_throughputs, *ray_values; // per-ray buffers
    ray_collision* last_ray_collisions;
    float *ray_refr_inds, *ray_brdf_pdfs; // per-ray data
    bool* ray_light_ints; // per-ray light intersections
    bool *next_step; // flag for next step required
} PathtraceBuffers;

extern PathtraceBuffers* init_pathtrace(int x_res, int y_res, int pixel_ray_grid_dim, int pixels_per_tile);
extern void pathtrace(float3 cam_pos, float3 cam_up, float3 cam_dir, float3* pixels, float* light_ints, PathtraceBuffers* buffers, int ray_bounce_limit, float x_fov);
extern void free_pathtrace(PathtraceBuffers* buffers);

#endif
