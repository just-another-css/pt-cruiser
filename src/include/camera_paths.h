#ifndef CAMERA_PATHS_H
#define CAMERA_PATHS_H

#include "camera_path_types.h"
#include "scene_processing.h"

extern void move_cam(RenderParameters* params, float3 translation, float3 rotation);
extern void init_path(CameraPath* path, RenderParameters* params, int frame, float3 translation, float3 rotation);
extern void build_path(CameraPath* path, RenderParameters* params, int frame, float3 translation, float3 rotation);
extern void finish_path(CameraPath* path, RenderParameters* params, int frame_count);
extern void start_trace_path(CameraPath* path, RenderParameters* params);
extern bool trace_path(CameraPath* path, int frame, float fps_scale, RenderParameters* params, float3* translation, float3* rotation, bool* continue_path);
extern void write_path(CameraPath* path, FILE* output);

#endif
