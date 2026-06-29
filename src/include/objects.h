#ifndef OBJECTS_H
#define OBJECTS_H

#include "mesh.h"

typedef struct {
    int num_objects, max_tri_count;
    TriangleMesh *meshes;
} TriangleObjects;

// Global Objects
extern __constant__ TriangleObjects objects_dev;
extern TriangleObjects objects;

// Call this on start, to initialise global triangle objects
extern void initialise_objects(int num_objects, PointsMesh* meshes, int** light_source_objs);
extern void free_objects(void);

#endif
