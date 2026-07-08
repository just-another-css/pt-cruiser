#ifndef CAMERA_PATHS_H
#define CAMERA_PATHS_H

#include <vector_types.h>
#include "scene_processing.h"

struct PositionPathNode {
    float3 pos;
    float3 translation;
    int frame;
    PositionPathNode* next;
};

typedef struct PositionPathNode PositionPathNode;

struct RotationPathNode {
    float3 vec;
    float rotation;
    int frame;
    RotationPathNode* next;
};

typedef struct RotationPathNode RotationPathNode;

struct PitchPathNode {
    float3 dir, up;
    float pitch;
    int frame;
    PitchPathNode* next;
};

typedef struct PitchPathNode PitchPathNode;

typedef struct {
    PositionPathNode pos_path;
    PitchPathNode pitch_path;
    RotationPathNode yaw_path, roll_path;
    PositionPathNode *pos_path_end;
    PitchPathNode *pitch_path_end;
    RotationPathNode *yaw_path_end, *roll_path_end;
} CameraPath;

extern void move_cam(RenderParameters* params, float3 translation, float3 rotation);
extern void init_path(CameraPath* path, RenderParameters* params, float3 translation, float3 rotation);
extern void build_path(CameraPath* path, RenderParameters* params, int frame, float3 translation, float3 rotation);

#endif
