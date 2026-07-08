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
