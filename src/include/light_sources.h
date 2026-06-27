#ifndef LIGHT_SOURCES_H
#define LIGHT_SOURCES_H

#include "mesh.h"

typedef struct {
    int *obj_is;
    float *norm_intensities;
    float *cum_norm_intensities;
    float *total_triangle_areas;
    float **norm_triangle_areas;
    float **cum_norm_triangle_areas;
    int num_light_sources;
} LightSources;

extern __constant__ LightSources light_sources_dev;

// @note O(n) over number of objects
extern void initialise_light_sources(int num_objects, float3 *lightings, PointsMesh* meshes);

#endif