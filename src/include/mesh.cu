#include "mesh.h"

// TriangleMesh* create_triangle_mesh(int* indices, int num_indices, float3* positions, int num_pos, float4* normals, float2* uv, int* materials) {
//     /* CPU allocation gibberish */
//     TriangleMesh* mesh = (TriangleMesh*) malloc(sizeof(TriangleMesh));
//     MALLOC_CHECK(mesh);
//     mesh->triangle_count = num_indices / 3;
//     mesh->vertex_count = num_pos;
//     create_boundboxes(mesh->aabbs, mesh->triangle_count);
//     int array_size = mesh->triangle_count * sizeof(int);
//     mesh->a = (int*) malloc(array_size);
//     mesh->b = (int*) malloc(array_size);
//     mesh->c = (int*) malloc(array_size);
//     MALLOC_CHECK(mesh->a);
//     MALLOC_CHECK(mesh->b);
//     MALLOC_CHECK(mesh->c);
//     memcpy(mesh->a, indices, array_size);
//     memcpy(mesh->b, indices + mesh->triangle_count, array_size);
//     memcpy(mesh->c, indices + 2 * mesh->triangle_count, array_size);

//     mesh->vertices = (float3*) malloc(num_pos * sizeof(float3));
//     MALLOC_CHECK(mesh->vertices);
//     memcpy(mesh->vertices, positions, num_pos * sizeof(float3));

//     mesh->uv = NULL;
//     if (uv) {
//         mesh->uv = (float2*) malloc(num_pos * sizeof(float2));
//         MALLOC_CHECK(mesh->uv);
//         memcpy(mesh->uv, uv, num_pos * sizeof(float2));
//     }

//     mesh->materials = (int*) malloc(mesh->triangle_count * sizeof(int));
//     MALLOC_CHECK(mesh->materials);
//     memcpy(mesh->materials, materials, mesh->triangle_count * sizeof(int));
    
//     return mesh;
    
//     /* GPU allocation gibberish */

//     // TriangleMesh *mesh;
//     // CUDA_CHECK(cudaMallocManaged((void**) &mesh, sizeof(TriangleMesh), cudaMemAttachGlobal));
//     // mesh->triangle_count = num_indices / 3;
//     // mesh->vertex_count = num_pos;

//     // CUDA_CHECK(cudaMallocManaged((void**) &mesh->vertex_indices, num_indices * sizeof(int), cudaMemAttachGlobal));
//     // CUDA_CHECK(cudaMemcpy(mesh->vertex_indices, indices, num_indices * sizeof(int), cudaMemcpyDefault));

//     // CUDA_CHECK(cudaMallocManaged((void**) &mesh->vertices, num_pos * sizeof(float3), cudaMemAttachGlobal));
//     // CUDA_CHECK(cudaMemcpy(mesh->vertices, positions, num_pos * sizeof(float3), cudaMemcpyDefault));

//     // CUDA_CHECK(cudaMallocManaged((void**) &mesh->normals, num_pos * sizeof(float4), cudaMemAttachGlobal));
//     // CUDA_CHECK(cudaMemcpy(mesh->normals, normals, num_pos * sizeof(float4), cudaMemcpyDefault));

//     // mesh->uv = NULL;
//     // if (uv) {
//     //     CUDA_CHECK(cudaMallocManaged((void**) &mesh->uv, num_pos * sizeof(float2), cudaMemAttachGlobal));
//     //     CUDA_CHECK(cudaMemcpy(mesh->uv, uv, num_pos * sizeof(float2), cudaMemcpyDefault));
//     // }

//     // // Compute vectors AB and AC
//     // CUDA_CHECK(cudaMallocManaged((void**) &mesh->edge_vectors, mesh->triangle_count * 2 * sizeof(float3), cudaMemAttachGlobal));
//     // for (int i = 0; i < mesh->triangle_count; i++) {
//     //     mesh->edge_vectors[i * 2] = sub_vec(mesh->vertices[mesh->vertex_indices[i * 3 + 2]], mesh->vertices[mesh->vertex_indices[i * 3]]);
//     //     mesh->edge_vectors[i * 2 + 1] = sub_vec(mesh->vertices[mesh->vertex_indices[i * 3 + 1]], mesh->vertices[mesh->vertex_indices[i * 3]]);
//     // }
//     // return mesh;
// }

void free_triangle_mesh(TriangleMesh &mesh) {
    cudaFree(mesh.a);
    cudaFree(mesh.ab);
    cudaFree(mesh.ac);
    cudaFree(mesh.normals);
    cudaFree(mesh.uv_a);
    cudaFree(mesh.uv_ab);
    cudaFree(mesh.uv_ac);
    free_boundbox(mesh.aabbs);
}
