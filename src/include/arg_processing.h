#ifndef ARG_PROCESSING_H
#define ARG_PROCESSING_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include "scene_processing.h"

extern void process_help_arg(int argc, char** argv);
extern void process_args(int argc, char** argv, RenderParameters* params, int* num_objects, PointsMesh** meshes, CameraPath** cam_path);

#endif
