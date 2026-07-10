#ifndef SCENE_PROCESSING_H
#define SCENE_PROCESSING_H

#include "mesh.h"
#include "camera_path_types.h"

#define CAM_POS make_float3(0,0,0)
#define CAM_DIR make_float3(0,0,1)
#define CAM_UP  make_float3(0,1,0)
#define CAM_SPEED 1
#define CAM_ROTATION_SPEED 0.1

#define X_RES 3848
#define Y_RES 2160
#define X_FOV 1.75
#define PIXEL_RAY_GRID_DIM 10
#define RAY_BOUNCE_LIMIT 16
#define TILE_PIXELS 262144 // 2^18

#define NO_FRAME_LIMIT -1
#define NVJPEG_IMAGE_QUALITY 90

typedef struct {
    float3 cam_pos, cam_dir, cam_up;
    float cam_speed, cam_rotation_speed;
    int x_res, y_res;
    float x_fov, y_fov;
    int pixel_ray_grid_dim, ray_bounce_limit, pixels_per_tile;
    int num_frames, image_quality;
    bool use_opengl, nvjpeg_first, nvjpeg_last, nvjpeg_every, show_frametime, use_denoising, use_bloom;
    char* nvjpeg_output;
} RenderParameters;

extern void init_params(RenderParameters* params);
extern void parse_file(FILE* input, int* num_objects, PointsMesh** meshes, RenderParameters* params, CameraPath** camera_path);

#endif
