#include "mesh.h"

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
