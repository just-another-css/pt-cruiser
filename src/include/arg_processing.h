#ifndef ARG_PROCESSING_H
#define ARG_PROCESSING_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include "constants.h"
#include "scene_processing.h"

extern void process_args(int argc, char** argv, RenderParameters* params);

#endif