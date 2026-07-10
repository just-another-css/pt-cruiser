#ifndef CAMERA_PATH_TYPES_H
#define CAMERA_PATH_TYPES_H

#include <vector_types.h>

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
    PositionPathNode *pos_path, *pos_path_end;
    PitchPathNode *pitch_path, *pitch_path_end;
    RotationPathNode *yaw_path, *roll_path, *yaw_path_end, *roll_path_end;
} CameraPath;

#endif