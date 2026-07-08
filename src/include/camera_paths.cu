#include "camera_paths.h"
#include "math_utils.h"

void move_cam(RenderParameters* params, float3 translation, float3 rotation) {
    if (translation.x) { // A/D, left/right
        add_vec_ip(&params->cam_pos, scale_vec(translation.x, vec_cross_prod(params->cam_up, params->cam_dir)));
    }
    if (translation.y) { // R/F, up/down
        add_vec_ip(&params->cam_pos, scale_vec(translation.y, params->cam_up));
    }
    if (translation.z) { // W/S, forwards/backwards
        add_vec_ip(&params->cam_pos, scale_vec(translation.z, params->cam_dir));
    }
    if (rotation.x) { // up/down, pitch
        float3 cam_right = vec_cross_prod(params->cam_dir, params->cam_up);
        params->cam_dir = norm_vec(vec_rotate(params->cam_dir, cam_right, rotation.x));
        params->cam_up = norm_vec(vec_rotate(params->cam_up, cam_right, rotation.x));
    }
    if (rotation.y) { // left/right, yaw
        params->cam_dir = norm_vec(vec_rotate(params->cam_dir, params->cam_up, rotation.y));
    }
    if (rotation.z) { // Q/E, roll
        params->cam_up = norm_vec(vec_rotate(params->cam_up, params->cam_dir, rotation.z));
    }
}

void init_path(CameraPath* path, RenderParameters* params, float3 translation, float3 rotation) {
    path->pos_path = (PositionPathNode) {
        .pos = params->cam_pos,
        .translation = translation,
    };
    path->pos_path_end = &path->pos_path;
    path->pitch_path = (PitchPathNode) {
        .dir = params->cam_dir,
        .up = params->cam_up,
        .pitch = rotation.x,
    };
    path->pitch_path_end = &path->pitch_path;
    path->yaw_path = (RotationPathNode) {
        .vec = params->cam_dir,
        .rotation = rotation.y,
    };
    path->yaw_path_end = &path->yaw_path;
    path->roll_path = (RotationPathNode) {
        .vec = params->cam_up,
        .rotation = rotation.y,
    };
    path->roll_path_end = &path->roll_path;
}

void build_path(CameraPath* path, RenderParameters* params, int frame, float3 translation, float3 rotation) {
    if (!equal_vecs(translation, path->pos_path_end->translation)) {
        PositionPathNode* node = (PositionPathNode*) malloc(sizeof(PositionPathNode));
        node->pos = params->cam_pos;
        node->translation = translation;
        node->frame = frame;
        node->next = NULL;
        path->pos_path_end->next = node;
        path->pos_path_end = node;
    }
    if (rotation.x != path->pitch_path_end->pitch) { // add node to pitch_path
        PitchPathNode* node = (PitchPathNode*) malloc(sizeof(PitchPathNode));
        node->dir = params->cam_dir;
        node->up = params->cam_up;
        node->pitch = rotation.x;
        node->frame = frame;
        node->next = NULL;
        path->pitch_path_end->next = node;
        path->pitch_path_end = node;
    }
    if (rotation.y != path->yaw_path_end->rotation) { // add node to yaw_path
        RotationPathNode* node = (RotationPathNode*) malloc(sizeof(RotationPathNode));
        node->vec = params->cam_dir;
        node->rotation = rotation.y;
        node->frame = frame;
        node->next = NULL;
        path->yaw_path_end->next = node;
        path->yaw_path_end = node;
    }
    if (rotation.z != path->roll_path_end->rotation) {
        RotationPathNode* node = (RotationPathNode*) malloc(sizeof(RotationPathNode));
        node->vec = params->cam_up;
        node->rotation = rotation.z;
        node->frame = frame;
        node->next = NULL;
        path->roll_path_end->next = node;
        path->roll_path_end = node;
    }
}
