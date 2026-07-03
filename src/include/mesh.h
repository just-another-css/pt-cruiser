#ifndef SHAPE_H
#define SHAPE_H

#include "bound_box.h"
#include "constants.h"
#include "materials.h"

typedef struct {
    int triangle_count, vertex_count;
    int *a, *b, *c;
    float3 *vertices;
    float2 *uv;
    int *materials;
    float3 *lightings;
} PointsMesh;

typedef struct {
    int triangle_count, vertex_count;
    float3 *a;
    float3 *ab, *ac;
    float4 *normals;
    float2 *uv_a, *uv_ab, *uv_ac;
    BoundBoxes aabbs;
    int *materials;
    float3 *lightings;
} TriangleMesh;

// Initialising TriangleMesh
// Pre-assumption: length of positions = length of uv = length of normals
// If no vector is available for uv, pass in NULL. Other vectors are mandatory
extern TriangleMesh* create_triangle_mesh(int *indices, int num_indices, float3 *positions, int num_pos, float3 *normals, int* face_indices, float2* uv);
// free allocated TriangleMesh
extern void free_triangle_mesh(TriangleMesh &mesh);

#endif
