#ifndef MATERIALS_H
#define MATERIALS_H

#include "constants.h"

typedef enum {
    LIGHT_SOURCE,
    GLASS,
    METAL,
    DIFFUSE,
    LIGHT_DIFFUSE,
    RED_DIFFUSE,
    GREEN_DIFFUSE,
} Material;

#define NUM_MATERIALS 7

// Constants for light sources
#define LIGHT_SOURCE_TRANSPARENCY 0
#define LIGHT_SOURCE_CRIT_ANGLE 0
#define LIGHT_SOURCE_REFRACTIVE_INDEX 0
#define LIGHT_SOURCE_SMOOTHNESS 0
#define LIGHT_SOURCE_ROUGHNESS 0

// Constants for glass
#define GLASS_TRANSPARENCY 0.9
#define GLASS_CRIT_ANGLE 1.5707
#define GLASS_REFRACTIVE_INDEX 1.5
#define GLASS_SMOOTHNESS 1
#define GLASS_ROUGHNESS 0.01
#define GLASS_NORMAL_REFLECTION 0.04

// Constants for metal
#define METAL_TRANSPARENCY 0
#define METAL_CRIT_ANGLE 0
#define METAL_REFRACTIVE_INDEX 0
#define METAL_SMOOTHNESS 0.65
#define METAL_ROUGHNESS 0.5
#define METAL_NORMAL_REFLECTION 0.9

// Constants for diffuse
#define DIFFUSE_TRANSPARENCY 0
#define DIFFUSE_CRIT_ANGLE 0
#define DIFFUSE_REFRACTIVE_INDEX 0
#define DIFFUSE_SMOOTHNESS 0
#define DIFFUSE_ROUGHNESS 0

#ifdef __CUDACC__

typedef struct {
    float *transparencies, *cos_crit_angles, *refractive_indices, *smoothnesses, *roughnesses;
    cudaTextureObject_t *textures;
} MaterialData;

extern __constant__ MaterialData materials_data;

extern void initialise_materials_data(void);
extern void initialise_material_texture(Material material, char* texture_path);

#endif

#endif
