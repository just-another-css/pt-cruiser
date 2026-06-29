#ifndef LIGHT_SOURCES_H
#define LIGHT_SOURCES_H

#include "mesh.h"

typedef struct {
    int num_light_sources; // used to prevent invalid accesses to 
    int *obj_is; // identify objects
    float *cum_norm_obj_powers; // used to sample objects
    float *norm_obj_powers; // used for probability of sampling each object
    int *num_lit_faces; // used to prevent invalid accesses to face arrays
    int **face_is; // identify faces
    float **cum_norm_face_powers; // used to sample faces
    float **norm_face_powers; // used for probability of sampling each face
} LightSources;

extern __constant__ LightSources light_sources_dev;

// @note O(n) over number of objects
extern void initialise_light_sources(int num_objects, PointsMesh* meshes, int* all_num_lit_faces);

#endif
