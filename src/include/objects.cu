#include "objects.h"
#include "constants.h"
#include "math_utils.h"

__constant__ TriangleObjects objects_dev;
TriangleObjects objects;

__global__ void calc_triangle_data(int** a_devs, int** b_devs, int** c_devs, float3** vertices_devs, float2** uv_devs) {
    int obj = blockIdx.y * blockDim.y + threadIdx.y; // object
    if (obj >= objects_dev.num_objects) return;
    int tri = blockIdx.x * blockDim.x + threadIdx.x; // triangle
    TriangleMesh* mesh = objects_dev.meshes + obj; // get pointer to relevant mesh
    if (tri >= mesh->triangle_count) return;
    // // Save points to registers
    float3* vertices_dev = vertices_devs[obj];
    float3 a = vertices_dev[a_devs[obj][tri]];
    float3 b = vertices_dev[b_devs[obj][tri]];
    float3 c = vertices_dev[c_devs[obj][tri]];
    // Set triangle a point
    mesh->a[tri] = a;
    // Calculate edge vectors
    float3 ab = sub_vec(b, a), ac = sub_vec(c, a);
    mesh->ab[tri] = ab;
    mesh->ac[tri] = ac;
    // Calculate normal vector
    float3 normal = norm_vec(vec_cross_prod(ab, ac));
    mesh->normals[tri] = f3_to_f4(normal, vec_dot_prod(normal, a));
    // Calculate UV vectors
    int tri3 = tri * 3;
    float2* uv_dev = uv_devs[obj];
    float2 uv_a = uv_dev[tri3];
    mesh->uv_a[tri] = uv_a;
    mesh->uv_ab[tri] = sub_vec2(uv_dev[tri3 + 1], uv_a);
    mesh->uv_ac[tri] = sub_vec2(uv_dev[tri3 + 2], uv_a);
    // Calculate triangle AABB
    mesh->aabbs.pt_min[tri] = vec_min(a, vec_min(b, c));
    mesh->aabbs.pt_max[tri] = vec_max(a, vec_max(b, c));
}

static void calculate_mesh_vectors(int** a_devs, int** b_devs, int** c_devs, float3** vertices_devs, float2** uv_devs) {
    dim3 block;
    block.x = 32;
    block.y = 1;
    dim3 grid;
    grid.x = (objects.max_tri_count + block.x - 1) / block.x;
    grid.y = (objects.num_objects + block.y - 1) / block.y;
    calc_triangle_data<<<grid, block>>>(a_devs, b_devs, c_devs, vertices_devs, uv_devs);
}

void initialise_objects(int num_objects, float3* lightings, PointsMesh* meshes) {
    // Copy lightings to device
    float3* lightings_dev;
    CUDA_CHECK(cudaMalloc(&lightings_dev, num_objects * sizeof(float3)));
    CUDA_CHECK(cudaMemcpy(lightings_dev, lightings, num_objects * sizeof(float3), cudaMemcpyHostToDevice));
    // Initialise host objects list
    objects.num_objects = num_objects;
    objects.max_tri_count = 0;
    objects.lightings = lightings_dev;
    objects.meshes = (TriangleMesh*) malloc(num_objects * sizeof(TriangleMesh));
    if (objects.meshes == nullptr) {
        printf("null pointer of object meshes");
    }
    // Allocate and copy object mesh data to device and store pointers in meshes array in host objects struct
    int** a_devs = (int**) malloc(num_objects * sizeof(int*));
    int** b_devs = (int**) malloc(num_objects * sizeof(int*));
    int** c_devs = (int**) malloc(num_objects * sizeof(int*));
    float3** vertices_devs = (float3**) malloc(num_objects * sizeof(float3*));
    float2** uv_devs = (float2**) malloc(num_objects * sizeof(float2*));
    for (int obj = 0; obj < num_objects; obj++) {
        // Set size values
        objects.meshes[obj].triangle_count = meshes[obj].triangle_count;
        objects.meshes[obj].vertex_count = meshes[obj].vertex_count;
        // Allocate TriangleMesh arrays
        CUDA_CHECK(cudaMalloc(&objects.meshes[obj].a, meshes[obj].triangle_count * sizeof(float3)));
        CUDA_CHECK(cudaMalloc(&objects.meshes[obj].ab, meshes[obj].triangle_count * sizeof(float3)));
        CUDA_CHECK(cudaMalloc(&objects.meshes[obj].ac, meshes[obj].triangle_count * sizeof(float3)));
        CUDA_CHECK(cudaMalloc(&objects.meshes[obj].normals, meshes[obj].triangle_count * sizeof(float4)));
        CUDA_CHECK(cudaMalloc(&objects.meshes[obj].uv_a, meshes[obj].triangle_count * sizeof(float2)));
        CUDA_CHECK(cudaMalloc(&objects.meshes[obj].uv_ab, meshes[obj].triangle_count * sizeof(float2)));
        CUDA_CHECK(cudaMalloc(&objects.meshes[obj].uv_ac, meshes[obj].triangle_count * sizeof(float2)));
        CUDA_CHECK(cudaMalloc(&objects.meshes[obj].aabbs.pt_min, meshes[obj].triangle_count * sizeof(float3)));
        CUDA_CHECK(cudaMalloc(&objects.meshes[obj].aabbs.pt_max, meshes[obj].triangle_count * sizeof(float3)));
        CUDA_CHECK(cudaMalloc(&objects.meshes[obj].materials, meshes[obj].triangle_count * sizeof(Material)));
        // Copy data to TriangleMesh
        CUDA_CHECK(cudaMemcpy(objects.meshes[obj].materials, meshes[obj].materials, meshes[obj].triangle_count * sizeof(Material), cudaMemcpyHostToDevice));
        // Allocate space for data on device for processing
        CUDA_CHECK(cudaMalloc(&a_devs[obj], meshes[obj].triangle_count * sizeof(int)));
        CUDA_CHECK(cudaMalloc(&b_devs[obj], meshes[obj].triangle_count * sizeof(int)));
        CUDA_CHECK(cudaMalloc(&c_devs[obj], meshes[obj].triangle_count * sizeof(int)));
        CUDA_CHECK(cudaMalloc(&vertices_devs[obj], meshes[obj].vertex_count * sizeof(float3)));
        CUDA_CHECK(cudaMalloc(&uv_devs[obj], meshes[obj].triangle_count * 3 * sizeof(float2)));
        // Copy data to device for processing
        CUDA_CHECK(cudaMemcpy(a_devs[obj], meshes[obj].a, meshes[obj].triangle_count * sizeof(int), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(b_devs[obj], meshes[obj].b, meshes[obj].triangle_count * sizeof(int), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(c_devs[obj], meshes[obj].c, meshes[obj].triangle_count * sizeof(int), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(vertices_devs[obj], meshes[obj].vertices, meshes[obj].vertex_count * sizeof(float3), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(uv_devs[obj], meshes[obj].uv, meshes[obj].triangle_count * 3 * sizeof(float2), cudaMemcpyHostToDevice));
        
        if (meshes[obj].triangle_count > objects.max_tri_count) objects.max_tri_count = meshes[obj].triangle_count;
    }
    // Copy host objects list to device
    TriangleObjects objects_dev_cpy = objects;
    CUDA_CHECK(cudaMalloc(&objects_dev_cpy.meshes, num_objects * sizeof(TriangleMesh))); // copy object meshes from host to device
    CUDA_CHECK(cudaMemcpy(objects_dev_cpy.meshes, objects.meshes, num_objects * sizeof(TriangleMesh), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpyToSymbol(objects_dev, &objects_dev_cpy, sizeof(TriangleObjects)));
    // Copy buffer pointer arrays to device
    int **a_devs_dev, **b_devs_dev, **c_devs_dev;
    float3** vertices_devs_dev;
    float2** uv_devs_dev;
    CUDA_CHECK(cudaMalloc(&a_devs_dev, num_objects * sizeof(int*)));
    CUDA_CHECK(cudaMalloc(&b_devs_dev, num_objects * sizeof(int*)));
    CUDA_CHECK(cudaMalloc(&c_devs_dev, num_objects * sizeof(int*)));
    CUDA_CHECK(cudaMalloc(&vertices_devs_dev, num_objects * sizeof(float3*)));
    CUDA_CHECK(cudaMalloc(&uv_devs_dev, num_objects * sizeof(float2*)));
    CUDA_CHECK(cudaMemcpy(a_devs_dev, a_devs, num_objects * sizeof(int*), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(b_devs_dev, b_devs, num_objects * sizeof(int*), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(c_devs_dev, c_devs, num_objects * sizeof(int*), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(vertices_devs_dev, vertices_devs, num_objects * sizeof(float3*), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(uv_devs_dev, uv_devs, num_objects * sizeof(float2*), cudaMemcpyHostToDevice));
    // Calculate mesh edge vectors and normals
    calculate_mesh_vectors(a_devs_dev, b_devs_dev, c_devs_dev, vertices_devs_dev, uv_devs_dev);
    // Free mesh data transfer buffers
    for (int obj = 0; obj < num_objects; obj++) {
        CUDA_CHECK(cudaFree(a_devs[obj]));
        CUDA_CHECK(cudaFree(b_devs[obj]));
        CUDA_CHECK(cudaFree(c_devs[obj]));
        CUDA_CHECK(cudaFree(vertices_devs[obj]));
        CUDA_CHECK(cudaFree(uv_devs[obj]));
    }
    CUDA_CHECK(cudaFree(a_devs_dev));
    CUDA_CHECK(cudaFree(b_devs_dev));
    CUDA_CHECK(cudaFree(c_devs_dev));
    CUDA_CHECK(cudaFree(vertices_devs_dev));
    CUDA_CHECK(cudaFree(uv_devs_dev));
    free(a_devs);
    free(b_devs);
    free(c_devs);
    free(vertices_devs);
    free(uv_devs);
}

void free_objects(void) {
    cudaFree(objects.lightings);
    TriangleObjects objects_dev_cpy;
    CUDA_CHECK(cudaMemcpyFromSymbol(&objects_dev_cpy, objects_dev, sizeof(TriangleObjects)));
    // cudaFree(objects_dev_cpy.lightings); this is double free, as it's freed by objects.lightings already
    for (int obj = 0; obj < objects.num_objects; obj++) {
        free_triangle_mesh(objects.meshes[obj]);
        // free_triangle_mesh(objects_dev_cpy.meshes[obj]); double free as memcpy meshes pointers previously
    }
    free(objects.meshes);
    cudaFree(objects_dev_cpy.meshes);
}
