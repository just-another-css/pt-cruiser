#pragma once
#include <thrust/device_vector.h>
#include <thrust/execution_policy.h>
#include <thrust/sort.h>
#include <thrust/transform.h>

typedef struct {
    uint64_t morton_code;
    int mesh_index, tri_index;
} MortonShape;

extern "C" void sort_morton_shapes_thrust(MortonShape *morton_shapes, uint32_t num_triangles);
