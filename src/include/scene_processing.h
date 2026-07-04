#ifndef SCENE_PROCESSING_H
#define SCENE_PROCESSING_H

#include "mesh.h"

typedef struct {
    int x_res, y_res;
    float x_fov, y_fov;
    int pixel_ray_grid_dim;
    int ray_bounce_limit;
    int pixels_per_tile;
} RenderParameters;

extern void parse_file(FILE* input, int* num_objects, PointsMesh** meshes, RenderParameters* params);

#endif
