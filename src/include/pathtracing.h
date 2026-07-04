#ifndef PATHTRACING_H
#define PATHTRACING_H

#define EPSILON 1e-3

extern void pathtrace(float3 cam_pos, float3 cam_up, float3 cam_dir, float3* pixels, float* light_ints, int x_res, int y_res, int pixel_ray_grid_dim, int pixels_per_tile, int ray_bounce_limit, float x_fov);

#endif
