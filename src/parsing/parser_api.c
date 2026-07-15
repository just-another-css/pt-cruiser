#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser_api.h"

#define DESC_ARGS_INITIAL_CAPACITY 16
#define INT_LIST_INITIAL_CAPACITY 4
#define LIST_INITIAL_CAPACITY 256

static void make_empty_list(void** list, int* cap, int init_cap, size_t elem_size) {
    *list = malloc(init_cap * elem_size);
    assert(*list);
    *cap = init_cap;
}

static void make_list(void** list, int* len, int* cap, int init_cap, size_t elem_size) {
    make_empty_list(list, cap, init_cap, elem_size);
    *len = 1;
}

static inline void append_list(void** list, int* len, int* cap, void* elem, size_t elem_size) {
    if (*len + 1 >= *cap) {
        *cap <<= 1;
        *list = realloc(*list, *cap * elem_size);
        assert(*list);
    }
    memcpy((char*)(*list) + (*len)++ * elem_size, elem, elem_size);
}

UV make_uv(float x, float y) {
    UV uv = {
        .x = x,
        .y = y
    };
    return uv;
}

UVs* make_uvs(UV head) {
    UVs *uvs = malloc(sizeof(UVs));
    assert (uvs);
    uvs->len = 1;
    uvs->list[0] = head;
    return uvs;
}

UVs* append_uvs(UVs *uvs, UV value) {
    if (uvs->len == 3) {
        fputs("[!] Each face should only have 3 uv values!", stderr);
        exit(EXIT_FAILURE);
    }
    uvs->list[uvs->len++] = value;
    return uvs;
}

DescArg make_material(char *text) {
    return (DescArg) {
        .type = MATERIAL_DESC_ARG,
        .material = text
    };
}

DescArg make_lighting(float value) {
    return (DescArg) {
        .type = LIGHTING_DESC_ARG,
        .lighting = value
    };
}

DescArg make_uvdata(UVs *uvs) {
    return (DescArg) {
        .type = UV_DESC_ARG,
        .uvs = uvs
    };
}

DescArgs* make_desc_args(DescArg head) {
    DescArgs* args = malloc(sizeof(DescArgs));
    assert(args);
    make_list(&args->args, &args->len, &args->capacity, DESC_ARGS_INITIAL_CAPACITY, sizeof(DescArg));
    args->args[0] = head;
    return args;
}

DescArgs* make_empty_desc_args(void) {
    DescArgs* args = malloc(sizeof(DescArgs));
    assert(args);
    args->len = 0;
    args->capacity = 0;
    return args;
}

DescArgs* append_desc_args(DescArgs* args, DescArg value) {
    append_list(&args->args, &args->len, &args->capacity, &value, sizeof(DescArg));
    return args;
}

void free_desc_args(DescArgs* args) {
    for (int i = 0; i < args->len; i++) {
        if (args->args[i].type == UV_DESC_ARG) {
            free(args->args[i].uvs);
        }
    }
    free(args->args);
    free(args);
}

IntList* make_int_list(int head) {
    IntList *list = malloc(sizeof(IntList));
    assert(list);
    make_list(&list->list, &list->len, &list->capacity, INT_LIST_INITIAL_CAPACITY, sizeof(int));
    list->list[0] = head;
    return list;
}

IntList* append_int_list(IntList *int_list, int value) {
    append_list(&int_list->list, &int_list->len, &int_list->capacity, &value, sizeof(int));
    return int_list;
}

void free_int_list(IntList *list) {
    free(list->list);
    free(list);
}

Face_t make_face(IntList *list, DescArgs *args) {
    if (list->len != 3) {
        fprintf(stderr, "[!] All faces must have 3 vertices; %d were provided", list->len);
        exit(EXIT_FAILURE);
    }
    Face_t face = {
        .fst = list->list[0],
        .snd = list->list[1],
        .thr = list->list[2],
        .desc_args = args ? args : make_empty_desc_args()
    };
    free_int_list(list);
    return face;
}

FaceList_t* make_face_list(Face_t face) {
    FaceList_t* list = malloc(sizeof(FaceList_t));
    assert(list);
    make_list(&list->faces, &list->len, &list->capacity, LIST_INITIAL_CAPACITY, sizeof(Face_t));
    list->faces[0] = face;
    return list;
}

FaceList_t* append_face_list(FaceList_t* facelist, Face_t face) {
    append_list(&facelist->faces, &facelist->len, &facelist->capacity, &face, sizeof(Face_t));
    return facelist;
}

void free_face_list(FaceList_t* facelist) {
    for (int i = 0; i < facelist->len; i++) {
        free_desc_args(facelist->faces[i].desc_args);
    }
    free(facelist->faces);
    free(facelist);
}

Vec_t make_vec(float x, float y, float z) {
    Vec_t vec = {
        .x = x,
        .y = y,
        .z = z
    };
    return vec;
}

VecList_t* make_vecs(Vec_t head) {
    VecList_t *vecs = malloc(sizeof(VecList_t));
    assert(vecs);
    make_list(&vecs->list, &vecs->len, &vecs->capacity, LIST_INITIAL_CAPACITY, sizeof(Vec_t));
    vecs->list[0] = head;
    return vecs;
}

VecList_t* append_vecs(VecList_t *vecs, Vec_t value) {
    append_list(&vecs->list, &vecs->len, &vecs->capacity, &value, sizeof(Vec_t));
    return vecs;
}

void free_vecs(VecList_t *vecs) {
    free(vecs->list);
    free(vecs);
}

Obj_t make_object(char *name, VecList_t *vecs, FaceList_t *faces, DescArgs *args) {
    Obj_t object;
    object.name = name;
    // object.name = malloc(strlen(name) + 1);
    // assert (object.name);
    // memcpy(object.name, name, strlen(name) + 1);
    object.points = vecs;
    object.faces = faces;
    object.desc_args = args;
    return object;
}

void free_object(Obj_t object) {
    free_vecs(object.points);
    free_face_list(object.faces);
    free_desc_args(object.desc_args);
    free(object.name);
}

MatArg make_mat_texture(char* texture_path) {
    return (MatArg) {
        .type = TEXTURE,
        .filename = texture_path
    };
}

MatArg make_mat_num_arg(char* arg, float num_val) {
    MatArg res = {
        .num_val = num_val
    };
    switch (*arg) {
        case 't':
            res.type = arg[1] == 'e' ? TEXTURE : TRANSPARENCY;
            break;
        case 'c':
            res.type = CRITANGLE;
            break;
        case 'r':
            res.type = arg[1] == 'e' ? REFRINDEX : ROUGHNESS;
            break;
        case 's':
            res.type = SMOOTHNESS;
            break;
    }
    free(arg); // pointer arg is essentially discarded after this function
    return res;
}

MatArgs* append_mat_args(MatArgs* args, MatArg arg);

MatArgs* make_mat_args(MatArg arg) {
    MatArgs* args = malloc(sizeof(MatArgs));
    assert(args);
    args->texture_path = NULL;
    args->transparency = -1;
    args->crit_angle = -1;
    args->refr_index = -1;
    args->smoothness = -1;
    args->roughness = -1;
    return append_mat_args(args, arg);
}

MatArgs* append_mat_args(MatArgs* args, MatArg arg) {
    switch (arg.type) {
        case TEXTURE:
            args->texture_path = arg.filename;
            break;
        case TRANSPARENCY:
            args->transparency = arg.num_val;
            break;
        case CRITANGLE:
            args->crit_angle = arg.num_val;
            break;
        case REFRINDEX:
            args->refr_index = arg.num_val;
            break;
        case SMOOTHNESS:
            args->smoothness = arg.num_val;
            break;
        case ROUGHNESS:
            args->roughness = arg.num_val;
            break;
    }
    return args;
}

Mat_t make_material_def(char* name, char* base_mat, MatArgs* args) {
    return (Mat_t) {
        .name = name,
        .base = base_mat,
        .args = args
    };
}

void free_material(Mat_t material) {
    free(material.name);
    if (material.args) {
        free(material.args->texture_path);
        free(material.args);
    }
}

Param_t make_float_param(char* name, float value) {
    return (Param_t) {
        .num_value = value,
        .type = FLOAT_PARAM,
        .name = name,
    };
}

Param_t make_int_param(char* name, int value) {
    return (Param_t) {
        .num_value = value,
        .type = INT_PARAM,
        .name = name,
    };
}

Param_t make_vec_param(char* name, Vec_t value) {
    return (Param_t) {
        .vec_value = value,
        .type = VEC_PARAM,
        .name = name,
    };
}

void free_param(Param_t param) {
    free(param.name);
}

CameraPathNodeValue make_path_frame(int frame) {
    return (CameraPathNodeValue) {
        .type = FRAME,
        .frame = frame
    };
}

CameraPathNodeValue make_path_vec(CameraPathNodeValueType type, Vec_t vec) {
    return (CameraPathNodeValue) {
        .type = type,
        .vec = vec
    };
}

CameraPathNodeValue make_path_rotation(float rotation) {
    return (CameraPathNodeValue) {
        .type = ROTATION,
        .rotation = rotation
    };
}

CameraPathNodeValues append_path_vals(CameraPathNodeValues values, CameraPathNodeValue value);

CameraPathNodeValues make_path_vals(CameraPathNodeValue value) {
    CameraPathNodeValues values = (CameraPathNodeValues) {
        .values = malloc(MAX_NUM_PATH_VALS * sizeof(CameraPathNodeValue))
    };
    return append_path_vals(values, value);
}

CameraPathNodeValues append_path_vals(CameraPathNodeValues values, CameraPathNodeValue value) {
    if (values.len == MAX_NUM_PATH_VALS) {
        fputs("[!] Too many values provided for a camera path node", stderr);
        exit(EXIT_FAILURE);
    }
    values.values[values.len++] = value;
    return values;
}

CameraPathNode* make_cam_path_node(CameraPathNodeValues values) {
    CameraPathNode* node = (CameraPathNode*) malloc(sizeof(CameraPathNode));
    node->values = values;
    node->next = NULL;
    node->end = node;
    return node;
}

CameraPathNode* append_cam_path_node(CameraPathNode* list, CameraPathNode* next) {
    list->end->next = next;
    list->end = next;
    return list;
}

CameraPathList make_path_list(CameraPathListType type, CameraPathNode* list) {
    return (CameraPathList) {
        .type = type,
        .list = list
    };
}

CameraPath_t append_cam_path(CameraPath_t path, CameraPathList list);

CameraPath_t make_cam_path(CameraPathList list) {
    CameraPath_t path = (CameraPath_t) { 
        .lists = calloc(NUM_CAM_PATH_LISTS, sizeof(CameraPathNode*)),
    };
    return append_cam_path(path, list);
}

static inline void check_path_fps(int fps) {
    if (!fps) {
        fputs("[!] Camera path fps cannot be zero", stderr);
        exit(EXIT_FAILURE);
    }
}

CameraPath_t make_cam_path_fps(int fps) {
    check_path_fps(fps);
    return (CameraPath_t) {
        .lists = calloc(NUM_CAM_PATH_LISTS, sizeof(CameraPathNode*)),
        .fps = fps,
    };
}

CameraPath_t append_cam_path(CameraPath_t path, CameraPathList list) {
    path.lists[list.type] = list.list;
    return path;
}

CameraPath_t set_cam_path_fps(CameraPath_t path, int fps) {
    check_path_fps(fps);
    path.fps = fps;
    return path;
}

void free_cam_path(CameraPath_t path) {
    // TODO: traverse lists and free
}

Scene_t scene;

void append_scene_obj(Obj_t obj) {
    append_list(&scene.objects, &scene.obj_len, &scene.obj_capacity, &obj, sizeof(Obj_t));
}

void append_scene_mat(Mat_t mat) {
    append_list(&scene.materials, &scene.mat_len, &scene.mat_capacity, &mat, sizeof(Mat_t));
}

void append_scene_param(Param_t param) {
    append_list(&scene.params, &scene.param_len, &scene.param_capacity, &param, sizeof(Param_t));
}

void append_scene_path(CameraPath_t path) {
    if (scene.path_set) {
        fputs("[!] Multiple camera paths defined\n", stderr);
        exit(EXIT_FAILURE);
    }
    scene.path = path;
    scene.path_set = true;
}

void init_scene() {
    scene = (Scene_t) {}; // zero-init all structs and lengths
    make_empty_list(&scene.objects, &scene.obj_capacity, LIST_INITIAL_CAPACITY, sizeof(Obj_t));
    make_empty_list(&scene.materials, &scene.mat_capacity, LIST_INITIAL_CAPACITY, sizeof(Mat_t));
    make_empty_list(&scene.params, &scene.param_capacity, LIST_INITIAL_CAPACITY, sizeof(Param_t));
}

void free_scene() {
    for (int i = 0; i < scene.obj_len; i++) free_object(scene.objects[i]);
    for (int i = 0; i < scene.mat_len; i++) free_material(scene.materials[i]);
    for (int i = 0; i < scene.param_len; i++) free_param(scene.params[i]);
    free(scene.objects);
    free(scene.materials);
    free(scene.params);
}
