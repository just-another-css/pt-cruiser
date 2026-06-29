#include "light_sources.h"
#include "math_utils.h"
#include "mesh.h"
#include "objects.h"

__constant__ LightSources light_sources_dev;

// x: max triangle count; y: number of light sources
__global__ static void calculate_triangle_powers(int* cur_lit_face_is) {
    int i = blockIdx.y * blockDim.y + threadIdx.y;
    if (i >= light_sources_dev.num_light_sources) return;
    int light_source_i = light_sources_dev.obj_is[i];
    int face_i = blockIdx.x * blockDim.x + threadIdx.x;
    TriangleMesh* light_source_mesh = objects_dev.meshes + light_source_i;
    if (face_i >= light_source_mesh->triangle_count) return;
    if (zero_vec(light_source_mesh->lightings[face_i])) return;
    int lit_face_i = atomicAdd(cur_lit_face_is + i, 1);
    light_sources_dev.face_is[i][lit_face_i] = face_i;
    // calculate size of each triangle and scale by triangle lighting intensity to get power
    light_sources_dev.norm_face_powers[i][lit_face_i] = vec_mag(light_source_mesh->lightings[face_i]) * 0.5f * vec_mag(vec_cross_prod(light_source_mesh->ab[face_i], light_source_mesh->ac[face_i]));
}

// x: number of light sources
__global__ static void calculate_total_triangle_powers() {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= light_sources_dev.num_light_sources) return;
    float* triangle_powers = light_sources_dev.norm_face_powers[i];
    float total_obj_power = 0;
    int j_limit = light_sources_dev.num_lit_faces[i];
    // TODO: switch to float4 loads
    for (int j = 0; j < j_limit; j++) total_obj_power += triangle_powers[j]; // calculate total power of triangles in each object
    light_sources_dev.norm_obj_powers[i] = total_obj_power;
}

// x: max triangle count; y: number of light sources
__global__ static void calculate_norm_triangle_powers() {
    int i = blockIdx.y * blockDim.y + threadIdx.y;
    if (i >= light_sources_dev.num_light_sources) return;
    int face_i = blockIdx.x * blockDim.x + threadIdx.x;
    if (face_i >= light_sources_dev.num_lit_faces[i]) return;
    light_sources_dev.norm_face_powers[i][face_i] = fdividef(light_sources_dev.norm_face_powers[i][face_i], light_sources_dev.norm_obj_powers[i]); // normalise area of triangles within each object
}

// x: number of light sources
__global__ static void calculate_cum_norm_triangle_powers() {
    int i = blockIdx.y * blockDim.y + threadIdx.y;
    if (i >= light_sources_dev.num_light_sources) return;
    int j_limit = light_sources_dev.num_lit_faces[i];
    float* triangle_powers = light_sources_dev.norm_face_powers[i];
    float* cum_triangle_powers = light_sources_dev.cum_norm_face_powers[i];
    cum_triangle_powers[0] = triangle_powers[0];
    for (int j = 1; j < j_limit; j++) cum_triangle_powers[j] = cum_triangle_powers[j - 1] + triangle_powers[j]; // find cumulative normalised power for each triangle in each object
}

// x: 1
__global__ static void calculate_total_obj_powers(float* total_obj_power) {
    float acc = 0;
    int j_limit = light_sources_dev.num_light_sources;
    for (int j = 0; j < j_limit; j++) acc += light_sources_dev.norm_obj_powers[j]; // calculate total power of all light sources
    *total_obj_power = acc;
}

// x: number of light sources
__global__ static void calculate_norm_obj_powers(float* total_obj_power) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= light_sources_dev.num_light_sources) return;
    light_sources_dev.norm_obj_powers[i] = fdividef(light_sources_dev.norm_obj_powers[i], *total_obj_power); // normalise power of each object relative to all light sources in scene
}

// x: 1
__global__ static void calculate_cum_norm_obj_powers() {
    int j_limit = light_sources_dev.num_light_sources;
    float* obj_powers = light_sources_dev.norm_obj_powers;
    float* cum_obj_powers = light_sources_dev.cum_norm_obj_powers;
    cum_obj_powers[0] = obj_powers[0];
    for (int j = 1; j < j_limit; j++) cum_obj_powers[j] = cum_obj_powers[j - 1] + obj_powers[j]; // find cumulative normalised power for each light source in scene
}

void initialise_light_sources(int num_objects, PointsMesh* meshes, int* all_num_lit_faces) {
    int num_light_sources = 0;
    for (int i = 0; i < num_objects; i++) if (all_num_lit_faces[i]) num_light_sources++;
    assert(num_light_sources > 0);
    // TODO: special case for no light sources
    int* light_source_is = (int*) malloc(num_light_sources * sizeof(int));
    int* light_source_num_lit_faces = (int*) malloc(num_light_sources * sizeof(int));
    int total_lit_faces = 0, max_lit_faces = 0;
    int** face_is_devs = (int**) malloc(num_light_sources * sizeof(int*));
    float** cum_norm_face_power_devs = (float**) malloc(num_light_sources * sizeof(float*));
    float** norm_face_power_devs = (float**) malloc(num_light_sources * sizeof(float*));
    for (int i = 0, j = 0; j < num_light_sources; i++) {
        if (all_num_lit_faces[i]) { 
            light_source_is[j] = i;
            light_source_num_lit_faces[j] = all_num_lit_faces[i];
            total_lit_faces += all_num_lit_faces[i];
            CUDA_CHECK(cudaMalloc(&face_is_devs[j], all_num_lit_faces[i] * sizeof(int)));
            CUDA_CHECK(cudaMalloc(&cum_norm_face_power_devs[j], all_num_lit_faces[i] * sizeof(float)));
            CUDA_CHECK(cudaMalloc(&norm_face_power_devs[j], all_num_lit_faces[i] * sizeof(float)));
            if (all_num_lit_faces[i] > max_lit_faces) max_lit_faces = all_num_lit_faces[i];
            j++;
        }
    }
    LightSources light_sources_dev_cpy;
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.obj_is, num_light_sources * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.cum_norm_obj_powers, num_light_sources * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.norm_obj_powers, num_light_sources * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.num_lit_faces, num_light_sources * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.face_is, num_light_sources * sizeof(int*)));
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.cum_norm_face_powers, num_light_sources * sizeof(float*)));
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.norm_face_powers, num_light_sources * sizeof(float*)));
    CUDA_CHECK(cudaMemcpy(light_sources_dev_cpy.obj_is, light_source_is, num_light_sources * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(light_sources_dev_cpy.num_lit_faces, light_source_num_lit_faces, num_light_sources * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(light_sources_dev_cpy.face_is, face_is_devs, num_light_sources * sizeof(int*), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(light_sources_dev_cpy.cum_norm_face_powers, cum_norm_face_power_devs, num_light_sources * sizeof(float*), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(light_sources_dev_cpy.norm_face_powers, norm_face_power_devs, num_light_sources * sizeof(float*), cudaMemcpyHostToDevice));
    free(face_is_devs);
    free(cum_norm_face_power_devs);
    free(norm_face_power_devs);
    light_sources_dev_cpy.num_light_sources = num_light_sources;
    // Copy pointers to device
    cudaMemcpyToSymbol(light_sources_dev, &light_sources_dev_cpy, sizeof(LightSources));
    // Calculate triangle data
    {
        int* cur_lit_face_is;
        CUDA_CHECK(cudaMalloc(&cur_lit_face_is, num_light_sources * sizeof(int)));
        CUDA_CHECK(cudaMemset(cur_lit_face_is, 0, num_light_sources * sizeof(int)));
        dim3 block_dim;
        block_dim.x = 32;
        block_dim.y = 16;
        dim3 grid_dim;
        grid_dim.x = (max_lit_faces + block_dim.x - 1) / block_dim.x;
        grid_dim.y = (num_light_sources + block_dim.y - 1) / block_dim.y;
        calculate_triangle_powers<<<grid_dim, block_dim>>>(cur_lit_face_is);
        cudaFree(cur_lit_face_is);
    }
    {
        dim3 block_dim;
        block_dim.x = 64;
        dim3 grid_dim;
        grid_dim.x = (num_light_sources + block_dim.x - 1) / block_dim.x;
        calculate_total_triangle_powers<<<grid_dim, block_dim>>>();
    }
    {
        dim3 block_dim;
        block_dim.x = 32;
        block_dim.y = 16;
        dim3 grid_dim;
        grid_dim.x = (max_lit_faces + block_dim.x - 1) / block_dim.x;
        grid_dim.y = (num_light_sources + block_dim.y - 1) / block_dim.y;
        calculate_norm_triangle_powers<<<grid_dim, block_dim>>>();
    }
    {
        dim3 block_dim;
        block_dim.x = 64;
        dim3 grid_dim;
        grid_dim.x = (num_light_sources + block_dim.x - 1) / block_dim.x;
        calculate_cum_norm_triangle_powers<<<grid_dim, block_dim>>>();
    }
    float* total_obj_power_dev;
    CUDA_CHECK(cudaMalloc(&total_obj_power_dev, sizeof(float)));
    {
        dim3 block_dim;
        block_dim.x = 1;
        dim3 grid_dim;
        grid_dim.x = 1;
        calculate_total_obj_powers<<<grid_dim, block_dim>>>(total_obj_power_dev);
    }
    {
        dim3 block_dim;
        block_dim.x = 64;
        dim3 grid_dim;
        grid_dim.x = (num_light_sources + block_dim.x - 1) / block_dim.x;
        calculate_norm_obj_powers<<<grid_dim, block_dim>>>(total_obj_power_dev);
    }
    cudaFree(total_obj_power_dev);
    {
        dim3 block_dim;
        block_dim.x = 1;
        dim3 grid_dim;
        grid_dim.x = 1;
        calculate_cum_norm_obj_powers<<<grid_dim, block_dim>>>();
    }
}