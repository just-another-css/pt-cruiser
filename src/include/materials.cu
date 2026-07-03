#include <math.h>

#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>

#include "materials.h"

static MaterialData materials_data_cpy; // global to allow editing in `initialise_material_texture` without copying from device
static cudaTextureObject_t* materials_textures;
 
__constant__ MaterialData materials_data;

void initialise_materials_data(void) {
    float transparencies[] =   { LIGHT_SOURCE_TRANSPARENCY, GLASS_TRANSPARENCY, METAL_TRANSPARENCY, DIFFUSE_TRANSPARENCY, DIFFUSE_TRANSPARENCY, DIFFUSE_TRANSPARENCY, DIFFUSE_TRANSPARENCY }, // 0 for opaque, 1 for transparent
        crit_angles[] =        { LIGHT_SOURCE_CRIT_ANGLE, GLASS_CRIT_ANGLE, METAL_CRIT_ANGLE, DIFFUSE_CRIT_ANGLE, DIFFUSE_CRIT_ANGLE, DIFFUSE_CRIT_ANGLE, DIFFUSE_CRIT_ANGLE }, // critical angle in radians
        cos_crit_angles[NUM_MATERIALS], // precomputed cos(crit_angles[i])
        refractive_indices[] = { LIGHT_SOURCE_REFRACTIVE_INDEX, GLASS_REFRACTIVE_INDEX, METAL_REFRACTIVE_INDEX, DIFFUSE_REFRACTIVE_INDEX, DIFFUSE_REFRACTIVE_INDEX, DIFFUSE_REFRACTIVE_INDEX, DIFFUSE_REFRACTIVE_INDEX },
        smoothnesses[] =       { LIGHT_SOURCE_SMOOTHNESS, GLASS_SMOOTHNESS, METAL_SMOOTHNESS, DIFFUSE_SMOOTHNESS, DIFFUSE_SMOOTHNESS, DIFFUSE_SMOOTHNESS, DIFFUSE_SMOOTHNESS }, // 0 for Lambertian, 1 for perfectly reflective
        roughnesses[] =        { LIGHT_SOURCE_ROUGHNESS, GLASS_ROUGHNESS, METAL_ROUGHNESS, DIFFUSE_ROUGHNESS, DIFFUSE_ROUGHNESS, DIFFUSE_ROUGHNESS, DIFFUSE_ROUGHNESS }; // 0 for specular reflections, 1 for diffuse reflections
    // precompute cos_crit_angles
    for (int i = 0; i < NUM_MATERIALS; i++) cos_crit_angles[i] = cosf(crit_angles[i]);
    // Allocate memory and copy data to device
    materials_textures = (cudaTextureObject_t*) malloc(NUM_MATERIALS * sizeof(cudaTextureObject_t));
    cudaMalloc(&materials_data_cpy.transparencies, NUM_MATERIALS * sizeof(float));
    cudaMalloc(&materials_data_cpy.cos_crit_angles, NUM_MATERIALS * sizeof(float));
    cudaMalloc(&materials_data_cpy.refractive_indices, NUM_MATERIALS * sizeof(float));
    cudaMalloc(&materials_data_cpy.smoothnesses, NUM_MATERIALS * sizeof(float));
    cudaMalloc(&materials_data_cpy.roughnesses, NUM_MATERIALS * sizeof(float));
    cudaMalloc(&materials_data_cpy.textures, NUM_MATERIALS * sizeof(cudaTextureObject_t));
    cudaMemcpy(materials_data_cpy.transparencies, transparencies, NUM_MATERIALS * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(materials_data_cpy.cos_crit_angles, cos_crit_angles, NUM_MATERIALS * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(materials_data_cpy.refractive_indices, refractive_indices, NUM_MATERIALS * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(materials_data_cpy.smoothnesses, smoothnesses, NUM_MATERIALS * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(materials_data_cpy.roughnesses, roughnesses, NUM_MATERIALS * sizeof(float), cudaMemcpyHostToDevice);
    // Copy pointers to constant device memory
    cudaMemcpyToSymbol(materials_data, &materials_data_cpy, sizeof(MaterialData));
}

void initialise_material_texture(int material_i, char* texture_path) {
    // Load image to host array
    int x, y, n; // receive image data from stb
    float *texture_data = stbi_loadf(texture_path, &x, &y, &n, 4); // force 4 channels for CUDA texture object compatibility
    // Copy image data to CUDA array
    cudaArray_t texture_array;
    struct cudaChannelFormatDesc channel_desc = cudaCreateChannelDesc<float4>();
    CUDA_CHECK(cudaMallocArray(&texture_array, &channel_desc, x, y));
    CUDA_CHECK(cudaMemcpy2DToArray(texture_array, 0, 0, texture_data, x * 4 * sizeof(float), x * sizeof(float4), y, cudaMemcpyHostToDevice));
    // Initialise CUDA texture object
    struct cudaResourceDesc resource_desc = {
        .resType = cudaResourceTypeArray,
    };
    resource_desc.res.array.array = texture_array;
    struct cudaTextureDesc texture_desc = {
        .addressMode = { cudaAddressModeMirror, cudaAddressModeMirror }, // mirror to prevent visible edges
        .filterMode = cudaFilterModeLinear, // interpolate points in texture
        .readMode = cudaReadModeElementType, // already loaded in as floats from stb
        .normalizedCoords = true, // UV coordinates will be normalised
    };
    CUDA_CHECK(cudaCreateTextureObject(material_textures + material_i, &resource_desc, &texture_desc, NULL));
    stbi_image_free(texture_data);
}