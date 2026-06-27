#ifndef BVH_H
#define BVH_H

#include "bound_box.h"
#include "mesh.h"
#include "objects.h"

typedef struct {
    BoundBoxes aabbs;
    // mesh_index will be -1 for interim node
    int *mesh_index, *triangle_index;
    int *left_child_index, *right_child_index;
} BVH;

extern __device__ BVH bvh_dev;

extern void create_bvh(void);
extern void free_bvh(void);

#endif