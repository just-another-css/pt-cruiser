#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser_api.h"

#define DESC_ARGS_INITIAL_CAPACITY 16
#define INT_LIST_INITIAL_CAPACITY 4
#define LIST_INITIAL_CAPACITY 256

static void make_list(void** list, int* len, int* cap, int init_cap, size_t elem_size) {
    *list = malloc(init_cap * elem_size);
    assert(*list);
    *cap = init_cap;
    *len = 1;
}

static void resize_list(void** list, int len, int* cap, size_t elem_size) {
    if (len + 1 >= *cap) {
        *cap <<= 1;
        *list = realloc(*list, *cap * elem_size);
        assert(*list);
    }
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
        .type = 0,
        .material = text
    };
}

DescArg make_lighting(float value) {
    DescArg result;
    result.type = 1;
    result.lighting = value;
    return result;
}

DescArg make_uvdata(UVs *uvs) {
    DescArg result = {
        .type = 2,
        .uvs = uvs
    };
    return result;
}

DescArgs* make_desc_args(DescArg head) {
    DescArgs* args = malloc(sizeof(DescArgs));
    assert(args);
    make_list(&args->args, &args->len, &args->capacity, DESC_ARGS_INITIAL_CAPACITY, sizeof(DescArg));
    args->args[0] = head;
    return args;
}

static void resize_desc_args(DescArgs *args) {
    resize_list(&args->args, args->len, &args->capacity, sizeof(DescArg));
}

DescArgs* append_desc_args(DescArgs* args, DescArg value) {
    resize_desc_args(args);
    args->args[args->len++] = value;
    return args;
}

void free_desc_args(DescArgs* args) {
    for (int i = 0; i < args->len; i++) {
        if (args->args[i].type == 2) {
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

static void resize_int_list(IntList *list) {
    resize_list(&list->list, list->len, &list->capacity, sizeof(int));
}

IntList* append_int_list(IntList *int_list, int value) {
    resize_int_list(int_list);
    int_list->list[int_list->len++] = value;
    return int_list;
}

void free_int_list(IntList *list) {
    free(list->list);
    free(list);
}

Face_t make_face(IntList *list, DescArgs *args) {
    if (list->len != 3) {
        fprintf(stderr, "[!] A triangular face should only have 3 vertices, %d is given", list->len);
        exit(EXIT_FAILURE);
    }
    Face_t face = {
        .fst = list->list[0],
        .snd = list->list[1],
        .thr = list->list[2],
        .desc_args = args
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

static void resize_face_list(FaceList_t *list) {
    resize_list(&list->faces, list->len, &list->capacity, sizeof(Face_t));
}

FaceList_t* append_face_list(FaceList_t* facelist, Face_t face) {
    resize_face_list(facelist);
    facelist->faces[facelist->len++] = face;
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

static void resize_vecs(VecList_t *vecs) {
    resize_list(&vecs->list, vecs->len, &vecs->capacity, sizeof(Vec_t));
}

VecList_t* append_vecs(VecList_t *vecs, Vec_t value) {
    resize_vecs(vecs);
    vecs->list[vecs->len++] = value;
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

Mat_t make_material_def(char* name, MatArgs* args) {
    return (Mat_t) {
        .name = name,
        .args = args
    };
}

void free_material(Mat_t material) {
    free(material.name);
    free(material.args->texture_path);
    free(material.args);
}

Definition_t union_obj(Obj_t obj) {
    return (Definition_t) {
        .type = OBJECT,
        .obj = obj
    };
}

Definition_t union_mat(Mat_t mat) {
    return (Definition_t) {
        .type = MATERIAL,
        .mat = mat
    };
}

static Scene_t* init_scene() {
    Scene_t* scene = malloc(sizeof(Scene_t));
    assert(scene);
    make_list(&scene->objects, &scene->obj_len, &scene->obj_capacity, LIST_INITIAL_CAPACITY, sizeof(Obj_t));
    make_list(&scene->materials, &scene->mat_len, &scene->mat_capacity, LIST_INITIAL_CAPACITY, sizeof(Mat_t));
    return scene;
}

Scene_t* make_scene(Definition_t definition) {
    Scene_t* scene = init_scene();
    switch (definition.type) {
        case OBJECT:
            scene->objects[0] = definition.obj;
            break;
        case MATERIAL:
            scene->materials[0] = definition.mat;
            break;
    }
    return scene;
}

static void resize_scene_obj(Scene_t* scene) {
    resize_list(&scene->objects, scene->obj_len, &scene->obj_capacity, sizeof(Obj_t));
}

static Scene_t* append_scene_obj(Scene_t* scene, Obj_t object) {
    resize_scene_obj(scene);
    scene->objects[scene->obj_len++] = object;
    return scene;
}

static void resize_scene_mat(Scene_t* scene) {
    resize_list(&scene->materials, scene->mat_len, &scene->mat_capacity, sizeof(Mat_t));
}

static Scene_t* append_scene_mat(Scene_t* scene, Mat_t material) {
    resize_scene_mat(scene);
    scene->materials[scene->mat_len++] = material;
    return scene;
}

Scene_t* append_scene(Scene_t* scene, Definition_t definition) {
    switch (definition.type) {
        case OBJECT:
            append_scene_obj(scene, definition.obj);
            break;
        case MATERIAL:
            append_scene_mat(scene, definition.mat);
            break;
    }
    return scene;
}

void free_scene(Scene_t* scene) {
    for (int i = 0; i < scene->obj_len; i++) free_object(scene->objects[i]);
    for (int i = 0; i < scene->mat_len; i++) free_material(scene->materials[i]);
    free(scene->objects);
    free(scene->materials);
    free(scene);
}
