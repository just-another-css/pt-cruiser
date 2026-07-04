#include <math.h>

#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>

#include "materials.h"

char* default_material_names[] = {
    "light_source",
    "light_diffuse",
    "dark_diffuse",
    "metal",
    "glass",
};

char* default_texture_paths[] =    { "textures/light_source_texture.png", "textures/diffuse_texture.png", "textures/diffuse_texture2.png", "textures/metal_texture.png", "textures/diffuse_texture.png" };
float default_transparencies[] =   { LIGHT_SOURCE_TRANSPARENCY, DIFFUSE_TRANSPARENCY, DIFFUSE_TRANSPARENCY, METAL_TRANSPARENCY, GLASS_TRANSPARENCY }, // 0 for opaque, 1 for transparent
    default_crit_angles[] =        { LIGHT_SOURCE_CRIT_ANGLE, DIFFUSE_CRIT_ANGLE, DIFFUSE_CRIT_ANGLE, METAL_CRIT_ANGLE, GLASS_CRIT_ANGLE }, // critical angle in radians
    default_refractive_indices[] = { LIGHT_SOURCE_REFRACTIVE_INDEX, DIFFUSE_REFRACTIVE_INDEX, DIFFUSE_REFRACTIVE_INDEX, METAL_REFRACTIVE_INDEX, GLASS_REFRACTIVE_INDEX },
    default_smoothnesses[] =       { LIGHT_SOURCE_SMOOTHNESS, DIFFUSE_SMOOTHNESS, DIFFUSE_SMOOTHNESS, METAL_SMOOTHNESS, GLASS_SMOOTHNESS }, // 0 for Lambertian, 1 for perfectly reflective
    default_roughnesses[] =        { LIGHT_SOURCE_ROUGHNESS, DIFFUSE_ROUGHNESS, DIFFUSE_ROUGHNESS, METAL_ROUGHNESS, GLASS_ROUGHNESS }; // 0 for specular reflections, 1 for diffuse reflections

static MaterialData materials_data_cpy; // global to allow editing in `initialise_material_texture` without copying from device
static cudaTextureObject_t* material_textures;
 
__constant__ MaterialData materials_data;

void load_default_material(int material, char** texture_path, float* transparency, float* crit_angle, float* refr_index, float* smoothness, float* roughness) {
    *texture_path = default_texture_paths[material];
    *transparency = default_transparencies[material];
    *crit_angle = default_crit_angles[material];
    *refr_index = default_refractive_indices[material];
    *smoothness = default_smoothnesses[material];
    *roughness = default_roughnesses[material];
}

void initialise_materials_data(char** texture_paths, float* transparencies, float* crit_angles, float* refr_indices, float* smoothnesses, float* roughnesses, int num_materials) {
    float* cos_crit_angles = (float*) malloc(num_materials * sizeof(float));
    // Precompute cos_crit_angles
    for (int i = 0; i < num_materials; i++) cos_crit_angles[i] = cosf(crit_angles[i]);
    // Allocate memory and copy data to device
    material_textures = (cudaTextureObject_t*) malloc(num_materials * sizeof(cudaTextureObject_t));
    cudaMalloc(&materials_data_cpy.transparencies, num_materials * sizeof(float));
    cudaMalloc(&materials_data_cpy.cos_crit_angles, num_materials * sizeof(float));
    cudaMalloc(&materials_data_cpy.refractive_indices, num_materials * sizeof(float));
    cudaMalloc(&materials_data_cpy.smoothnesses, num_materials * sizeof(float));
    cudaMalloc(&materials_data_cpy.roughnesses, num_materials * sizeof(float));
    cudaMalloc(&materials_data_cpy.textures, num_materials * sizeof(cudaTextureObject_t));
    cudaMemcpy(materials_data_cpy.transparencies, transparencies, num_materials * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(materials_data_cpy.cos_crit_angles, cos_crit_angles, num_materials * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(materials_data_cpy.refractive_indices, refr_indices, num_materials * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(materials_data_cpy.smoothnesses, smoothnesses, num_materials * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(materials_data_cpy.roughnesses, roughnesses, num_materials * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(materials_data_cpy.textures, material_textures, num_materials * sizeof(cudaTextureObject_t), cudaMemcpyHostToDevice);
    // Copy pointers to constant device memory
    cudaMemcpyToSymbol(materials_data, &materials_data_cpy, sizeof(MaterialData));
    // Load textures
    for (int i = 0; i < num_materials; i++) initialise_material_texture(i, texture_paths[i]);
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
    CUDA_CHECK(cudaMemcpy(materials_data_cpy.textures + material_i, material_textures + material_i, sizeof(cudaTextureObject_t), cudaMemcpyHostToDevice));
    stbi_image_free(texture_data);
}