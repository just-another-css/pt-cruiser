#include "light_sources.h"
#include "math_utils.h"
#include "mesh.h"
#include "objects.h"

__constant__ LightSources light_sources_dev;

__global__ static void calculate_triangle_areas() {
    int i = blockIdx.y * blockDim.y + threadIdx.y;
    if (i >= light_sources_dev.num_light_sources) return;
    int light_source_i = light_sources_dev.obj_is[i];
    int face_i = blockIdx.x * blockDim.x + threadIdx.x;
    TriangleMesh* light_source_mesh = objects_dev.meshes + light_source_i;
    if (face_i >= light_source_mesh->triangle_count) return;
    float* triangle_areas = light_sources_dev.norm_triangle_areas[i];
    triangle_areas[face_i] = 0.5f * vec_mag(vec_cross_prod(light_source_mesh->ab[face_i], light_source_mesh->ac[face_i])); // calculate size of each triangle
}

__global__ static void calculate_total_triangle_areas() {
    int i = blockIdx.y * blockDim.y + threadIdx.y;
    if (i >= light_sources_dev.num_light_sources) return;
    TriangleMesh* light_source_mesh = objects_dev.meshes + light_sources_dev.obj_is[i];
    float* triangle_areas = light_sources_dev.norm_triangle_areas[i];
    float total_triangle_area = 0;
    int j_limit = light_source_mesh->triangle_count;
    for (int j = 0; j < j_limit; j++) total_triangle_area += triangle_areas[j]; // calculate total area of triangles in each object
    light_sources_dev.total_triangle_areas[i] = total_triangle_area;
}

__global__ static void calculate_norm_triangle_areas() {
    int i = blockIdx.y * blockDim.y + threadIdx.y;
    if (i >= light_sources_dev.num_light_sources) return;
    int face_i = blockIdx.x * blockDim.x + threadIdx.x;
    if (face_i >= objects_dev.meshes[light_sources_dev.obj_is[i]].triangle_count) return;
    light_sources_dev.norm_triangle_areas[i][face_i] = fdividef(light_sources_dev.norm_triangle_areas[i][face_i], light_sources_dev.total_triangle_areas[i]); // normalise area of triangles within each object
}

__global__ static void calculate_cum_norm_triangle_areas() {
    int i = blockIdx.y * blockDim.y + threadIdx.y;
    if (i >= light_sources_dev.num_light_sources) return;
    int j_limit = objects_dev.meshes[light_sources_dev.obj_is[i]].triangle_count;
    float* triangle_areas = light_sources_dev.norm_triangle_areas[i];
    float* cum_triangle_areas = light_sources_dev.cum_norm_triangle_areas[i];
    cum_triangle_areas[0] = triangle_areas[0];
    for (int j = 1; j < j_limit; j++) cum_triangle_areas[j] = cum_triangle_areas[j - 1] + triangle_areas[j]; // find cumulative normalised area for each triangle in each object
}

void initialise_light_sources(int num_objects, float3 *lightings, PointsMesh* meshes) {
    int num_light_sources = 0;
    for (int i = 0; i < num_objects; i++) if (nonzero_vec(lightings[i])) num_light_sources++;
    assert(num_light_sources > 0);
    // TODO: special case for no light sources
    int *light_source_is = (int*) malloc(num_light_sources * sizeof(int));
    float *norm_intensities = (float*) malloc(num_light_sources * sizeof(float));
    float *cum_intensities = (float*) malloc(num_light_sources * sizeof(float));
    for (int i = 0; i < num_objects; i++) {
        if (nonzero_vec(lightings[i])) {
            light_source_is[0] = i;
            norm_intensities[0] = vec_mag(lightings[i]);
            cum_intensities[0] = vec_mag(lightings[i]);
            break;
        }
    }
    for (int i = light_source_is[0] + 1, j = 0; j < num_light_sources; i++) {
        if (nonzero_vec(lightings[i])) { 
            light_source_is[++j] = i;
            norm_intensities[j] = vec_mag(lightings[i]);
            cum_intensities[j] = cum_intensities[j - 1] + norm_intensities[j];
        }
    }
    for (int j = 0; j < num_light_sources; j++) {
        norm_intensities[j] /= cum_intensities[num_light_sources - 1];
        cum_intensities[j] /= cum_intensities[num_light_sources - 1];
    }
    cum_intensities[num_light_sources - 1] = 1; // ensure that full range up to 1 is covered
    LightSources light_sources_dev_cpy;
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.obj_is, num_light_sources * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.norm_intensities, num_light_sources * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.cum_norm_intensities, num_light_sources * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.total_triangle_areas, num_light_sources * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.norm_triangle_areas, num_light_sources * sizeof(float*)));
    CUDA_CHECK(cudaMalloc(&light_sources_dev_cpy.cum_norm_triangle_areas, num_light_sources * sizeof(float*)));
    CUDA_CHECK(cudaMemcpy(light_sources_dev_cpy.obj_is, light_source_is, num_light_sources * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(light_sources_dev_cpy.norm_intensities, norm_intensities, num_light_sources * sizeof(float), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(light_sources_dev_cpy.cum_norm_intensities, cum_intensities, num_light_sources * sizeof(float), cudaMemcpyHostToDevice));
    // Allocate arrays for triangle data
    float** norm_triangle_areas_devs = (float**) malloc(num_light_sources * sizeof(float*));
    float** cum_norm_triangle_areas_devs = (float**) malloc(num_light_sources * sizeof(float*));
    int max_tri_count = 0;
    for (int i = 0; i < num_light_sources; i++) {
        CUDA_CHECK(cudaMalloc(&norm_triangle_areas_devs[i], meshes[light_source_is[i]].triangle_count * sizeof(float)));
        CUDA_CHECK(cudaMalloc(&cum_norm_triangle_areas_devs[i], meshes[light_source_is[i]].triangle_count * sizeof(float)));
        if (meshes[light_source_is[i]].triangle_count > max_tri_count) max_tri_count = meshes[light_source_is[i]].triangle_count;
    }
    CUDA_CHECK(cudaMemcpy(light_sources_dev_cpy.norm_triangle_areas, norm_triangle_areas_devs, num_light_sources * sizeof(float*), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(light_sources_dev_cpy.cum_norm_triangle_areas, cum_norm_triangle_areas_devs, num_light_sources * sizeof(float*), cudaMemcpyHostToDevice));
    free(norm_triangle_areas_devs);
    free(cum_norm_triangle_areas_devs);
    light_sources_dev_cpy.num_light_sources = num_light_sources;
    // Copy pointers to device
    cudaMemcpyToSymbol(light_sources_dev, &light_sources_dev_cpy, sizeof(LightSources));
    // Calculate triangle data
    
    {
        dim3 block_dim;
        block_dim.x = 32;
        block_dim.y = 16;
        dim3 grid_dim;
        grid_dim.x = (max_tri_count + block_dim.x - 1) / block_dim.x;
        grid_dim.y = (num_light_sources + block_dim.y - 1) / block_dim.y;
        calculate_triangle_areas<<<grid_dim, block_dim>>>();
    }
    {
        dim3 block_dim;
        block_dim.x = 64;
        dim3 grid_dim;
        grid_dim.x = (num_light_sources + block_dim.x - 1) / block_dim.x;
        calculate_total_triangle_areas<<<grid_dim, block_dim>>>();
    }
    {
        dim3 block_dim;
        block_dim.x = 32;
        block_dim.y = 16;
        dim3 grid_dim;
        grid_dim.x = (max_tri_count + block_dim.x - 1) / block_dim.x;
        grid_dim.y = (num_light_sources + block_dim.y - 1) / block_dim.y;
        calculate_norm_triangle_areas<<<grid_dim, block_dim>>>();
    }
    {
        dim3 block_dim;
        block_dim.x = 64;
        dim3 grid_dim;
        grid_dim.x = (num_light_sources + block_dim.x - 1) / block_dim.x;
        calculate_cum_norm_triangle_areas<<<grid_dim, block_dim>>>();
    }
}