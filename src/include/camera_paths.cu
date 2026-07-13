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

void init_path(CameraPath** path, RenderParameters* params, float3 translation, float3 rotation) {
    *path = (CameraPath*) malloc(sizeof(CameraPath));
    PositionPathNode* pos_node = (PositionPathNode*) malloc(sizeof(PositionPathNode));
    *pos_node = (PositionPathNode) {
        .pos = params->cam_pos,
        .translation = translation,
    };
    (*path)->pos_path_start = (*path)->pos_path_end = (*path)->pos_path = pos_node;
    PitchPathNode* pitch_node = (PitchPathNode*) malloc(sizeof(PitchPathNode));
    *pitch_node = (PitchPathNode) {
        .dir = params->cam_dir,
        .up = params->cam_up,
        .pitch = rotation.x,
    };
    (*path)->pitch_path_start = (*path)->pitch_path_end = (*path)->pitch_path = pitch_node;
    RotationPathNode* yaw_node = (RotationPathNode*) malloc(sizeof(RotationPathNode));
    *yaw_node = (RotationPathNode) {
        .vec = params->cam_dir,
        .rotation = rotation.y,
    };
    (*path)->yaw_path_start = (*path)->yaw_path_end = (*path)->yaw_path = yaw_node;
    RotationPathNode* roll_node = (RotationPathNode*) malloc(sizeof(RotationPathNode));
    *roll_node = (RotationPathNode) {
        .vec = params->cam_up,
        .rotation = rotation.z,
    };
    (*path)->roll_path_start = (*path)->roll_path_end = (*path)->roll_path = roll_node;
}

void build_path(CameraPath* path, RenderParameters* params, int frame, float3 translation, float3 rotation) {
    if (!equal_vecs(translation, path->pos_path_end->translation)) {
        path->pos_path_end->next = (PositionPathNode*) malloc(sizeof(PositionPathNode));
        *path->pos_path_end->next = (PositionPathNode) {
            .pos = params->cam_pos,
            .translation = translation,
            .frame = frame,
        };
        path->pos_path_end = path->pos_path_end->next;
    }
    if (rotation.x != path->pitch_path_end->pitch) { // add node to pitch_path
        path->pitch_path_end->next = (PitchPathNode*) malloc(sizeof(PitchPathNode));
        *path->pitch_path_end->next = (PitchPathNode) {
            .dir = params->cam_dir,
            .up = params->cam_up,
            .pitch = rotation.x,
            .frame = frame,
        };
        path->pitch_path_end = path->pitch_path_end->next;
    }
    if (rotation.y != path->yaw_path_end->rotation) { // add node to yaw_path
        path->yaw_path_end->next = (RotationPathNode*) malloc(sizeof(RotationPathNode));
        *path->yaw_path_end->next = (RotationPathNode) {
            .vec = params->cam_dir,
            .rotation = rotation.y,
            .frame = frame,
        };
        path->yaw_path_end = path->yaw_path_end->next;
    }
    if (rotation.z != path->roll_path_end->rotation) {
        path->roll_path_end->next = (RotationPathNode*) malloc(sizeof(RotationPathNode));
        *path->roll_path_end->next = (RotationPathNode) {
            .vec = params->cam_up,
            .rotation = rotation.z,
            .frame = frame,
        };
        path->roll_path_end = path->roll_path_end->next;
    }
}

void finish_path(CameraPath* path, RenderParameters* params, int frame_count) {
    build_path(path, params, frame_count, make_float3(0,0,0), make_float3(0,0,0));
}

void write_path(CameraPath* path, int path_fps, FILE* output) {
    fputs("camera_path: { cam = [", output);
    // Write position path
    PositionPathNode* pos_path = path->pos_path;
    fprintf(output, "{ frame = %d, pos = (%f,%f,%f), tran = (%f,%f,%f) }", pos_path->frame, pos_path->pos.x, pos_path->pos.y, pos_path->pos.z, pos_path->translation.x, pos_path->translation.y, pos_path->translation.z);
    while ((pos_path = pos_path->next)) {
        fprintf(output, ", { frame = %d, pos = (%f,%f,%f), tran = (%f,%f,%f) }", pos_path->frame, pos_path->pos.x, pos_path->pos.y, pos_path->pos.z, pos_path->translation.x, pos_path->translation.y, pos_path->translation.z);
    }
    // Write pitch path
    fputs("], pitch = [", output);
    PitchPathNode* pitch_path = path->pitch_path;
    fprintf(output, "{ frame = %d, dir = (%f,%f,%f), up = (%f,%f,%f), rot = %f }", pitch_path->frame, pitch_path->dir.x, pitch_path->dir.y, pitch_path->dir.z, pitch_path->up.x, pitch_path->up.y, pitch_path->up.z, pitch_path->pitch);
    while ((pitch_path = pitch_path->next)) {
        fprintf(output, ", { frame = %d, dir = (%f,%f,%f), up = (%f,%f,%f), rot = %f }", pitch_path->frame, pitch_path->dir.x, pitch_path->dir.y, pitch_path->dir.z, pitch_path->up.x, pitch_path->up.y, pitch_path->up.z, pitch_path->pitch);
    }
    // Write yaw path
    fputs("], yaw = [", output);
    RotationPathNode* yaw_path = path->yaw_path;
    fprintf(output, "{ frame = %d, dir = (%f,%f,%f), rot = %f }", yaw_path->frame, yaw_path->vec.x, yaw_path->vec.y, yaw_path->vec.z, yaw_path->rotation);
    while ((yaw_path = yaw_path->next)) {
        fprintf(output, ", { frame = %d, dir = (%f,%f,%f), rot = %f }", yaw_path->frame, yaw_path->vec.x, yaw_path->vec.y, yaw_path->vec.z, yaw_path->rotation);
    }
    // Write roll path
    fputs("], roll = [", output);
    RotationPathNode* roll_path = path->roll_path;
    fprintf(output, "{ frame = %d, up = (%f,%f,%f), rot = %f }", roll_path->frame, roll_path->vec.x, roll_path->vec.y, roll_path->vec.z, roll_path->rotation);
    while ((roll_path = roll_path->next)) {
        fprintf(output, ", { frame = %d, up = (%f,%f,%f), rot = %f }", roll_path->frame, roll_path->vec.x, roll_path->vec.y, roll_path->vec.z, roll_path->rotation);
    }
    if (path_fps) fprintf(output, "], fps = %d }", path_fps);
    else fputs("] }", output);
}

void start_trace_path(CameraPath* path, RenderParameters* params) {
    params->cam_pos = path->pos_path->pos;
    params->cam_dir = path->pitch_path->dir; // pitch path and yaw/roll paths should match on first node due to init_path behaviour
    params->cam_up = path->pitch_path->up;
}

bool trace_path(CameraPath* path, int frame, float fps_scale, RenderParameters* params, float3* translation, float3* rotation, bool* continue_path) {
    if (path->pos_path != path->pos_path_end && frame >= path->pos_path->next->frame) {
        PositionPathNode* next = path->pos_path->next;
        path->pos_path = next;
        params->cam_pos = path->pos_path->pos;
    }
    if (path->pitch_path != path->pitch_path_end && frame >= path->pitch_path->next->frame) {
        PitchPathNode* next = path->pitch_path->next;
        path->pitch_path = next;
        params->cam_dir = path->pitch_path->dir;
        params->cam_up = path->pitch_path->up;
    }
    if (path->yaw_path != path->yaw_path_end && frame >= path->yaw_path->next->frame) {
        RotationPathNode* next = path->yaw_path->next;
        path->yaw_path = next;
        params->cam_dir = path->yaw_path->vec;
    }
    if (path->roll_path != path->roll_path_end && frame >= path->roll_path->next->frame) {
        RotationPathNode* next = path->roll_path->next;
        path->roll_path = next;
        params->cam_up = path->roll_path->vec;
    }
    *translation = scale_vec(fps_scale, path->pos_path->translation);
    *rotation = scale_vec(fps_scale, make_float3(
        path->pitch_path->pitch,
        path->yaw_path->rotation,
        path->roll_path->rotation
    ));
    if (path->pos_path == path->pos_path_end &&
        path->pitch_path == path->pitch_path_end &&
        path->yaw_path == path->yaw_path_end &&
        path->roll_path == path->roll_path_end) *continue_path = false;
    return *continue_path;
}

void free_path(CameraPath* path) {
    PositionPathNode* pos_node = path->pos_path_start, *next_pos_node;
    while (pos_node) {
        next_pos_node = pos_node->next;
        free(pos_node);
        pos_node = next_pos_node;
    }
    PitchPathNode* pitch_node = path->pitch_path_start, *next_pitch_node;
    while (pitch_node) {
        next_pitch_node = pitch_node->next;
        free(pitch_node);
        pitch_node = next_pitch_node;
    }
    RotationPathNode* yaw_node = path->yaw_path_start, *next_yaw_node;
    while (yaw_node) {
        next_yaw_node = yaw_node->next;
        free(yaw_node);
        yaw_node = next_yaw_node;
    }
    RotationPathNode* roll_node = path->roll_path_start, *next_roll_node;
    while (roll_node) {
        next_roll_node = roll_node->next;
        free(roll_node);
        roll_node = next_roll_node;
    }
    free(path);
}
