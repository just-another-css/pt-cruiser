#include <stdio.h>
extern "C" {
    #include "../parsing/parser_api.h"
    #include "../parsing/parser.h"
}
#include "scene_processing.h"

#define INVALID_MATERIAL -1
#define UNASSIGNED -1

static int find_material(char* material, char** materials, int num_materials) {
    for (int i = 0; i < num_materials; i++) if (!strcmp(material, materials[i])) return i;
    return INVALID_MATERIAL;
}

extern FILE *yyin;
extern int yyerrors;
extern Scene_t *parsed_scene;

static float3 vec_to_f3(Vec_t vec) {
    return make_float3(vec.x, vec.y, vec.z);
}

static void parse_input(int* num_objects, PointsMesh** mesh, RenderParameters* params, CameraPath** camera_path) {
    // Process material names
    char** material_names = (char**) malloc(parsed_scene->mat_len * sizeof(char*));
    for (int i = 0; i < parsed_scene->mat_len; i++) material_names[i] = parsed_scene->materials[i].name;
    bool* use_default_materials = (bool*) malloc(NUM_DEFAULT_MATERIALS * sizeof(bool));
    memset(use_default_materials, 0, NUM_DEFAULT_MATERIALS * sizeof(bool));
    int* default_material_is = (int*) malloc(NUM_DEFAULT_MATERIALS * sizeof(int));
    int num_total_materials = parsed_scene->mat_len; // counts explicit and default materials; add default materials after all explicitly specified materials
    // Process objects
    *num_objects = parsed_scene->obj_len;
    *mesh = (PointsMesh*) malloc(parsed_scene->obj_len * sizeof(PointsMesh));
    MALLOC_CHECK(*mesh);
    for (int i = 0; i < parsed_scene->obj_len; i++) {
        int num_triangles = parsed_scene->objects[i].faces->len;
        int num_vertices = parsed_scene->objects[i].points->len;
        (*mesh)[i].triangle_count = num_triangles;
        (*mesh)[i].vertex_count = num_vertices;
        (*mesh)[i].a = (int*) malloc(num_triangles * sizeof(int));
        MALLOC_CHECK((*mesh)[i].a);
        (*mesh)[i].b = (int*) malloc(num_triangles * sizeof(int));
        MALLOC_CHECK((*mesh)[i].b);
        (*mesh)[i].c = (int*) malloc(num_triangles * sizeof(int));
        MALLOC_CHECK((*mesh)[i].c);
        (*mesh)[i].vertices = (float3*) malloc(num_vertices * sizeof(float3));
        MALLOC_CHECK((*mesh)[i].vertices);
        (*mesh)[i].materials = (int*) malloc(num_triangles * sizeof(int));
        MALLOC_CHECK((*mesh)[i].materials);
        (*mesh)[i].lightings = (float3*) malloc(num_triangles * sizeof(float3));
        MALLOC_CHECK((*mesh)[i].lightings);
        (*mesh)[i].uv = (float2*) malloc(3 * num_triangles * sizeof(float2));
        MALLOC_CHECK((*mesh)[i].uv);
        bool object_material_set = false, object_lighting_set = false, object_uvs_set = false;
        int object_material;
        float3 object_lighting;
        float2 object_uvs[3];
        float value;
        for (int a = 0; a < parsed_scene->objects[i].desc_args->len; a++) {
            switch (parsed_scene->objects[i].desc_args->args[a].type) {
                case MATERIAL_DESC_ARG:
                    object_material = find_material(parsed_scene->objects[i].desc_args->args[a].material, material_names, parsed_scene->mat_len);
                    if (object_material == INVALID_MATERIAL) {
                        object_material = find_material(parsed_scene->objects[i].desc_args->args[a].material, default_material_names, NUM_DEFAULT_MATERIALS);
                        if (object_material == INVALID_MATERIAL) {
                            fprintf(stderr, "[!] Unidentified material '%s' used in object %d", parsed_scene->objects[i].desc_args->args[a].material, i);
                            exit(EXIT_FAILURE);
                        }
                        if (!use_default_materials[object_material]) {
                            use_default_materials[object_material] = true;
                            default_material_is[object_material] = num_total_materials++;
                        }
                        object_material = default_material_is[object_material];
                    }
                    object_material_set = true;
                    break;
                case LIGHTING_DESC_ARG:
                    value = parsed_scene->objects[i].desc_args->args[a].lighting;
                    object_lighting = make_float3(value, value, value);
                    object_lighting_set = true;
                    break;
                case UV_DESC_ARG:
                    object_uvs[0] = make_float2(parsed_scene->objects[i].desc_args->args[a].uvs->list[0].x,
                                                parsed_scene->objects[i].desc_args->args[a].uvs->list[0].y);
                    object_uvs[1] = make_float2(parsed_scene->objects[i].desc_args->args[a].uvs->list[1].x,
                                                parsed_scene->objects[i].desc_args->args[a].uvs->list[1].y);
                    object_uvs[2] = make_float2(parsed_scene->objects[i].desc_args->args[a].uvs->list[2].x,
                                                parsed_scene->objects[i].desc_args->args[a].uvs->list[2].y);
                    object_uvs_set = true;
                    break;
            }
        }
        for (int tri = 0; tri < num_triangles; tri++) {
            (*mesh)[i].a[tri] = parsed_scene->objects[i].faces->faces[tri].fst;
            (*mesh)[i].b[tri] = parsed_scene->objects[i].faces->faces[tri].snd;
            (*mesh)[i].c[tri] = parsed_scene->objects[i].faces->faces[tri].thr;
            bool material_flag = false, lighting_flag = false, uv_flag = false;
            float intensity;
            for (int a = 0; a < parsed_scene->objects[i].faces->faces[tri].desc_args->len; a++) {
                switch (parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].type) {
                    case MATERIAL_DESC_ARG:
                        (*mesh)[i].materials[tri] = find_material(parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].material, material_names, parsed_scene->mat_len);
                        if ((*mesh)[i].materials[tri] == INVALID_MATERIAL) {
                            (*mesh)[i].materials[tri] = find_material(parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].material, default_material_names, NUM_DEFAULT_MATERIALS);
                            if ((*mesh)[i].materials[tri] == INVALID_MATERIAL) {
                                fprintf(stderr, "[!] Unidentified material '%s' used in face %d in object %d", parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].material, tri, i);
                                exit(EXIT_FAILURE);
                            }
                            if (!use_default_materials[(*mesh)[i].materials[tri]]) {
                                use_default_materials[(*mesh)[i].materials[tri]] = true;
                                default_material_is[(*mesh)[i].materials[tri]] = num_total_materials++;
                            }
                            (*mesh)[i].materials[tri] = default_material_is[(*mesh)[i].materials[tri]];
                        }
                        material_flag = true;
                        break;
                    case LIGHTING_DESC_ARG:
                        intensity = parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].lighting;
                        (*mesh)[i].lightings[tri] = make_float3(intensity, intensity, intensity); // lighting is effectively a scalar applied to the colour of the object's texture
                        lighting_flag = true;
                        break;
                    case UV_DESC_ARG:
                        if (parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].uvs->len != 3) {
                            fprintf(stderr, "[!] A face must have three uvs! Error on object %d face %d\n", i, tri);
                            exit(EXIT_FAILURE);
                        }
                        (*mesh)[i].uv[tri * 3] = make_float2(parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].uvs->list[0].x,
                                                             parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].uvs->list[0].y);
                        (*mesh)[i].uv[tri * 3 + 1] = make_float2(parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].uvs->list[1].x,
                                                                 parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].uvs->list[1].y);
                        (*mesh)[i].uv[tri * 3 + 2] = make_float2(parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].uvs->list[2].x,
                                                                 parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].uvs->list[2].y);
                        uv_flag = true;
                        break;
                    default:
                        break;
                }
            }
            if (!material_flag) {
                if (object_material_set) (*mesh)[i].materials[tri] = object_material;
                else {
                    fprintf(stderr, "[!] No material was provided for face %d of object %d, and no material was provided for the object\n", tri, i);
                    exit(EXIT_FAILURE);
                }
            }
            if (!lighting_flag) {
                (*mesh)[i].lightings[tri] = object_lighting_set ? object_lighting : make_float3(0,0,0); // default to unlit or object lighting
            }
            if (!uv_flag) {
                if (object_uvs_set) {
                    (*mesh)[i].uv[tri * 3] = object_uvs[0];
                    (*mesh)[i].uv[tri * 3 + 1] = object_uvs[1];
                    (*mesh)[i].uv[tri * 3 + 2] = object_uvs[2];
                } else {
                    (*mesh)[i].uv[tri * 3] = make_float2(0, 0);
                    (*mesh)[i].uv[tri * 3 + 1] = make_float2(1, 0);
                    (*mesh)[i].uv[tri * 3 + 2] = make_float2(0, 1);
                }
            }
        }
        for (int v = 0; v < num_vertices; v++) {
            Vec_t now_v = parsed_scene->objects[i].points->list[v];
            (*mesh)[i].vertices[v] = make_float3(now_v.x, now_v.y, now_v.z);
        }
    }

    // Process materials
    char** texture_paths = (char**) malloc(num_total_materials * sizeof(char*));
    float* transparencies = (float*) malloc(num_total_materials * sizeof(float)),
        *crit_angles = (float*) malloc(num_total_materials * sizeof(float)),
        *refr_indices = (float*) malloc(num_total_materials * sizeof(float)),
        *smoothnesses = (float*) malloc(num_total_materials * sizeof(float)),
        *roughnesses = (float*) malloc(num_total_materials * sizeof(float));
    for (int i = parsed_scene->mat_len; i < num_total_materials; i++) { // Load parameters for any default materials used by objects
        bool material_loaded = false;
        for (int j = 0; j < NUM_DEFAULT_MATERIALS; j++) {
            if (default_material_is[j] == i) {
                load_default_material(j, texture_paths + i, transparencies + i, crit_angles + i, refr_indices + i, smoothnesses + i, roughnesses + i);
                material_loaded = true;
                break;
            }
        }
        if (!material_loaded) {
            fprintf(stderr, "[!] Default material %d (%s) could not be loaded\n", i, default_material_names[i]);
            exit(EXIT_FAILURE);
        }
    }
    for (int i = 0; i < parsed_scene->mat_len; i++) { // Set parameters for explicitly defined materials
        if (parsed_scene->materials[i].base) { // use base material for any unassigned parameters
            int base_i = find_material(parsed_scene->materials[i].base, material_names, i);
            bool material_loaded = false;
            if (base_i == INVALID_MATERIAL) { // base material is not a custom material defined before the current material
                int default_mat_i = find_material(parsed_scene->materials[i].base, default_material_names, NUM_DEFAULT_MATERIALS);
                if (default_mat_i != INVALID_MATERIAL) { // base material was a default material
                    if (!use_default_materials[default_mat_i]) { // default material has not been loaded in first pass
                        load_default_material(default_mat_i, texture_paths + i, transparencies + i, crit_angles + i, refr_indices + i, smoothnesses + i, roughnesses + i); // load default material directly and skip loading later
                        material_loaded = true;
                    }
                }
            }
            if (!material_loaded) { // base material has not been loaded directly; copy from existing material
                if (base_i == INVALID_MATERIAL) { // base material was never found and was not loaded directly
                    fprintf(stderr, "[!] Material #%d '%s' uses nonexistent base material '%s'", i, parsed_scene->materials[i].name, parsed_scene->materials[i].base);
                    exit(EXIT_FAILURE);
                }
                texture_paths[i] = texture_paths[base_i];
                transparencies[i] = transparencies[base_i];
                crit_angles[i] = crit_angles[base_i];
                refr_indices[i] = refr_indices[base_i];
                smoothnesses[i] = smoothnesses[base_i];
                roughnesses[i] = roughnesses[base_i];
            }
            if (parsed_scene->materials[i].args) { // at least some parameters have been changed from base material
                if (parsed_scene->materials[i].args->texture_path != NULL) texture_paths[i] = parsed_scene->materials[i].args->texture_path;
                if (parsed_scene->materials[i].args->transparency != UNASSIGNED) transparencies[i] = parsed_scene->materials[i].args->transparency;
                if (parsed_scene->materials[i].args->crit_angle != UNASSIGNED) crit_angles[i] = parsed_scene->materials[i].args->crit_angle;
                if (parsed_scene->materials[i].args->refr_index != UNASSIGNED) refr_indices[i] = parsed_scene->materials[i].args->refr_index;
                if (parsed_scene->materials[i].args->smoothness != UNASSIGNED) smoothnesses[i] = parsed_scene->materials[i].args->smoothness;
                if (parsed_scene->materials[i].args->roughness != UNASSIGNED) roughnesses[i] = parsed_scene->materials[i].args->roughness;
            }
        } else { // no base material, default to zero
            if (!parsed_scene->materials[i].args) {
                fprintf(stderr, "[!] Material #%d '%s' has no provided arguments and no base material", i, parsed_scene->materials[i].name);
                exit(EXIT_FAILURE);
            }
            if (parsed_scene->materials[i].args->texture_path != NULL) texture_paths[i] = parsed_scene->materials[i].args->texture_path;
            else {
                fprintf(stderr, "[!] Material #%d '%s' has no provided texture and no base material", i, parsed_scene->materials[i].name);
                exit(EXIT_FAILURE);
            }
            transparencies[i] = parsed_scene->materials[i].args->transparency != UNASSIGNED ? parsed_scene->materials[i].args->transparency : 0;
            crit_angles[i] = parsed_scene->materials[i].args->crit_angle != UNASSIGNED ? parsed_scene->materials[i].args->crit_angle : 0;
            refr_indices[i] = parsed_scene->materials[i].args->refr_index != UNASSIGNED ? parsed_scene->materials[i].args->refr_index : 0;
            smoothnesses[i] = parsed_scene->materials[i].args->smoothness != UNASSIGNED ? parsed_scene->materials[i].args->smoothness : 0;
            roughnesses[i] = parsed_scene->materials[i].args->roughness != UNASSIGNED ? parsed_scene->materials[i].args->roughness : 0;
        }
    }
    initialise_materials_data(texture_paths, transparencies, crit_angles, refr_indices, smoothnesses, roughnesses, num_total_materials); // Copy material data to device and load textures
    
    // Process rendering parameters
    bool valid, use_x_fov = true;
    for (int i = 0; i < parsed_scene->param_len; i++) {
        valid = true;
        switch (*parsed_scene->params[i].name) {
            case 'x':
                if (!strcmp(parsed_scene->params[i].name + 1, "_res")) params->x_res = parsed_scene->params[i].value;
                else if (!strcmp(parsed_scene->params[i].name + 1, "_fov")) {
                    params->x_fov = parsed_scene->params[i].value;
                    use_x_fov = true;
                } else valid = false;
                break;
            case 'y':
                if (!strcmp(parsed_scene->params[i].name + 1, "_res")) params->y_res = parsed_scene->params[i].value;
                else if (!strcmp(parsed_scene->params[i].name + 1, "_fov")) {
                    params->y_fov = parsed_scene->params[i].value;
                    use_x_fov = false;
                } else valid = false;
                break;
            case 'p':
                if (!strcmp(parsed_scene->params[i].name + 1, "ixel_ray_grid_dim")) params->pixel_ray_grid_dim = parsed_scene->params[i].value;
                else if (!strcmp(parsed_scene->params[i].name + 1, "ixels_per_tile")) params->pixels_per_tile = parsed_scene->params[i].value;
                else valid = false;
                break;
            case 'r':
                if (!strcmp(parsed_scene->params[i].name + 1, "ay_bounce_limit")) params->ray_bounce_limit = parsed_scene->params[i].value;
                else valid = false;
                break;
            default:
                valid = false;
                break;
        }
        if (!valid) {
            fprintf(stderr, "[!] Parameter #%d '%s' with value %f/(%f,%f,%f) was not recognised\n", i, parsed_scene->params[i].name, parsed_scene->params[i].num_value, parsed_scene->params[i].vec_value.x, parsed_scene->params[i].vec_value.y, parsed_scene->params[i].vec_value.z);
            exit(EXIT_FAILURE);
        }
    }
    if (use_x_fov) params->y_fov = params->x_fov * params->y_res / params->x_res;
    else params->x_fov = params->y_fov * params->x_res / params->y_res;

    // Process camera path
    if (parsed_scene->path_set) {
        *camera_path = (CameraPath*) malloc(sizeof(CameraPath));
        CameraPathNode* pos_node = parsed_scene->path[POS_LIST];
        if (pos_node) {
            (*camera_path)->pos_path_end = (*camera_path)->pos_path = (PositionPathNode*) malloc(sizeof(PositionPathNode));
            (*camera_path)->pos_path_end->next = NULL;
            do {
                bool pos_set = false, translation_set = false, frame_set = false;
                for (int i = 0; i < pos_node->values.len; i++) {
                    switch (pos_node->values.values[i].type) {
                        case FRAME:
                            (*camera_path)->pos_path_end->frame = pos_node->values.values[i].frame;
                            frame_set = true;
                            break;
                        case POS:
                            (*camera_path)->pos_path_end->pos = vec_to_f3(pos_node->values.values[i].vec);
                            pos_set = true;
                            break;
                        case TRANSLATION:
                            (*camera_path)->pos_path_end->translation = vec_to_f3(pos_node->values.values[i].vec);
                            translation_set = true;
                            break;
                        default:
                            fputs("[!] Invalid value provided for camera position path node", stderr);
                            exit(EXIT_FAILURE);
                    }
                }
                if (!pos_set || !translation_set || !frame_set) {
                    fputs("[!] Insufficient values provided for camera position path node", stderr);
                    exit(EXIT_FAILURE);
                }
                pos_node = pos_node->next;
                if (pos_node) {
                    (*camera_path)->pos_path_end->next = (PositionPathNode*) malloc(sizeof(PositionPathNode));
                    (*camera_path)->pos_path_end = (*camera_path)->pos_path_end->next;
                    (*camera_path)->pos_path_end->next = NULL;
                }
            } while (pos_node);
        } else {
            (*camera_path)->pos_path_end = (*camera_path)->pos_path = NULL;
        }
        CameraPathNode* pitch_node = parsed_scene->path[PITCH_LIST];
        if (pitch_node) {
            (*camera_path)->pitch_path_end = (*camera_path)->pitch_path = (PitchPathNode*) malloc(sizeof(PitchPathNode));
            (*camera_path)->pitch_path_end->next = NULL;
            do {
                bool dir_set = false, up_set = false, pitch_set = false, frame_set = false;
                for (int i = 0; i < pitch_node->values.len; i++) {
                    switch (pitch_node->values.values[i].type) {
                        case FRAME:
                            (*camera_path)->pitch_path_end->frame = pitch_node->values.values[i].frame;
                            frame_set = true;
                            break;
                        case DIR:
                            (*camera_path)->pitch_path_end->dir = vec_to_f3(pitch_node->values.values[i].vec);
                            dir_set = true;
                            break;
                        case UP:
                            (*camera_path)->pitch_path_end->up = vec_to_f3(pitch_node->values.values[i].vec);
                            up_set = true;
                            break;
                        case ROTATION:
                            (*camera_path)->pitch_path_end->pitch = pitch_node->values.values[i].rotation;
                            pitch_set = true;
                            break;
                        default:
                            fputs("[!] Invalid value provided for camera pitch path node", stderr);
                            exit(EXIT_FAILURE);
                    }
                }
                if (!dir_set || !up_set || !pitch_set || !frame_set) {
                    fputs("[!] Insufficient values provided for camera pitch path node", stderr);
                    exit(EXIT_FAILURE);
                }
                pitch_node = pitch_node->next;
                if (pitch_node) {
                    (*camera_path)->pitch_path_end->next = (PitchPathNode*) malloc(sizeof(PitchPathNode));
                    (*camera_path)->pitch_path_end = (*camera_path)->pitch_path_end->next;
                    (*camera_path)->pitch_path_end->next = NULL;
                }
            } while (pitch_node);
        } else {
            (*camera_path)->pitch_path_end = (*camera_path)->pitch_path = NULL;
        }
        CameraPathNode* yaw_node = parsed_scene->path[YAW_LIST];
        if (yaw_node) {
            (*camera_path)->yaw_path_end = (*camera_path)->yaw_path = (RotationPathNode*) malloc(sizeof(RotationPathNode));
            (*camera_path)->yaw_path_end->next = NULL;
            do {
                bool dir_set = false, rotation_set = false, frame_set = false;
                for (int i = 0; i < yaw_node->values.len; i++) {
                    switch (yaw_node->values.values[i].type) {
                        case FRAME:
                            (*camera_path)->yaw_path_end->frame = yaw_node->values.values[i].frame;
                            frame_set = true;
                            break;
                        case DIR:
                            (*camera_path)->yaw_path_end->vec = vec_to_f3(yaw_node->values.values[i].vec);
                            dir_set = true;
                            break;
                        case ROTATION:
                            (*camera_path)->yaw_path_end->rotation = yaw_node->values.values[i].rotation;
                            rotation_set = true;
                            break;
                        default:
                            fputs("[!] Invalid value provided for camera yaw path node", stderr);
                            exit(EXIT_FAILURE);
                    }
                }
                if (!dir_set || !rotation_set || !frame_set) {
                    fputs("[!] Insufficient values provided for camera yaw path node", stderr);
                    exit(EXIT_FAILURE);
                }
                yaw_node = yaw_node->next;
                if (yaw_node) {
                    (*camera_path)->yaw_path_end->next = (RotationPathNode*) malloc(sizeof(RotationPathNode));
                    (*camera_path)->yaw_path_end = (*camera_path)->yaw_path_end->next;
                    (*camera_path)->yaw_path_end->next = NULL;
                }
            } while (yaw_node);
        } else {
            (*camera_path)->yaw_path_end = (*camera_path)->yaw_path = NULL;
        }
        CameraPathNode* roll_node = parsed_scene->path[ROLL_LIST];
        if (roll_node) {
            (*camera_path)->roll_path_end = (*camera_path)->roll_path = (RotationPathNode*) malloc(sizeof(RotationPathNode));
            (*camera_path)->roll_path_end->next = NULL;
            do {
                bool dir_set = false, rotation_set = false, frame_set = false;
                for (int i = 0; i < roll_node->values.len; i++) {
                    switch (roll_node->values.values[i].type) {
                        case FRAME:
                            (*camera_path)->roll_path_end->frame = roll_node->values.values[i].frame;
                            frame_set = true;
                            break;
                        case UP:
                            (*camera_path)->roll_path_end->vec = vec_to_f3(roll_node->values.values[i].vec);
                            dir_set = true;
                            break;
                        case ROTATION:
                            (*camera_path)->roll_path_end->rotation = roll_node->values.values[i].rotation;
                            rotation_set = true;
                            break;
                        default:
                            fputs("[!] Invalid value provided for camera roll path node", stderr);
                            exit(EXIT_FAILURE);
                    }
                }
                if (!dir_set || !rotation_set || !frame_set) {
                    fputs("[!] Insufficient values provided for camera roll path node", stderr);
                    exit(EXIT_FAILURE);
                }
                roll_node = roll_node->next;
                if (roll_node) {
                    (*camera_path)->roll_path_end->next = (RotationPathNode*) malloc(sizeof(RotationPathNode));
                    (*camera_path)->roll_path_end = (*camera_path)->roll_path_end->next;
                    (*camera_path)->roll_path_end->next = NULL;
                }
            } while (roll_node);
        } else {
            (*camera_path)->roll_path_end = (*camera_path)->roll_path = NULL;
        }
    } else {
        *camera_path = NULL;
    }

    // Free parsed scene struct
    free_scene(parsed_scene);
}

void init_params(RenderParameters* params) {
    *params = (RenderParameters) {
        .cam_pos = CAM_POS,
        .cam_dir = CAM_DIR,
        .cam_up = CAM_UP,
        .cam_speed = CAM_SPEED,
        .cam_rotation_speed = CAM_ROTATION_SPEED,
        .x_res = X_RES,
        .y_res = Y_RES,
        .x_fov = X_FOV,
        .pixel_ray_grid_dim = PIXEL_RAY_GRID_DIM,
        .ray_bounce_limit = RAY_BOUNCE_LIMIT,
        .pixels_per_tile = TILE_PIXELS,
        .num_frames = NO_FRAME_LIMIT,
        .image_quality = NVJPEG_IMAGE_QUALITY,
        .use_opengl = false,
        .nvjpeg_first = false,
        .nvjpeg_last = true,
        .show_frametime = false,
        .use_denoising = true,
        .use_bloom = true,
        .nvjpeg_output = NULL,
        .use_cam_path = true,
        .append_cam_path = false,
        .complete_cam_path = false,
        .cam_path_output = NULL,
        .cam_path_framerate = 0,
    };
}

void parse_file(FILE* input, int* num_objects, PointsMesh** meshes, RenderParameters* params, CameraPath** camera_path) {
    yyin = input;
    puts("[*] Starting parsing...");
    int result = yyparse();
    if (result || yyerrors) {
        fprintf(stderr, "[!] Parsing failed with %d errors!\n", yyerrors);
        exit(EXIT_FAILURE);
    }
    puts("[*] Parsing finished");
    parse_input(num_objects, meshes, params, camera_path);
}
