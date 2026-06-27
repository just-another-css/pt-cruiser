#ifndef PATHTRACING_H
#define PATHTRACING_H

#define PIXEL_RAY_GRID_DIM 10
#define RAYS_PER_PIXEL (PIXEL_RAY_GRID_DIM * PIXEL_RAY_GRID_DIM)

#define RAY_BOUNCE_LIMIT 16
#define EPSILON 1e-3

#define TILE_PIXELS 262144 // 2^18
#define TILE_RAYS (TILE_PIXELS * RAYS_PER_PIXEL)

extern void pathtrace(float3 cam_pos, float3 cam_up, float3 cam_dir, float3* pixels, float* light_ints);

#endif
