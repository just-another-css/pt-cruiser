#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser_api.h"

#define DESC_ARGS_INITIAL_CAPACITY 16
#define INT_LIST_INITIAL_CAPACITY 4
#define LIST_INITIAL_CAPACITY 256

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
    assert (args);
    args->args = malloc(DESC_ARGS_INITIAL_CAPACITY * sizeof(DescArg));
    assert (args->args);
    args->capacity = DESC_ARGS_INITIAL_CAPACITY;
    args->len = 1;
    args->args[0] = head;
    return args;
}

static void resize_desc_args(DescArgs *args) {
    if (args->len + 1 >= args->capacity) {
        args->capacity <<= 1;
        args->args = realloc(args->args, args->capacity * sizeof(DescArg));
        assert (args->args);
    }
}

DescArgs* append_desc_args(DescArgs* args, DescArg value) {
    resize_desc_args(args);
    args->args[args->len++] = value;
    if (args->len > 3) {
        fputs("[!] More than 3 arguments is given for Description Arguments!", stderr);
        exit(EXIT_FAILURE);
    }
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
    assert (list);
    list->list = malloc(INT_LIST_INITIAL_CAPACITY * sizeof(int));
    assert (list->list);
    list->capacity = INT_LIST_INITIAL_CAPACITY;
    list->len = 1;
    list->list[0] = head;
    return list;
}

static void resize_int_list(IntList *list) {
    if (list->len + 1 >= list->capacity) {
        list->capacity <<= 1;
        list->list = realloc(list->list, list->capacity * sizeof(int));
        assert (list->list);
    }
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
    assert(list != NULL);
    list->faces = malloc(LIST_INITIAL_CAPACITY * sizeof(Face_t));
    assert(list->faces != NULL);
    list->capacity = LIST_INITIAL_CAPACITY;
    list->faces[0] = face;
    list->len = 1;
    return list;
}

static void resize_face_list(FaceList_t *list) {
    if (list->len + 1 >= list->capacity) {
        list->capacity <<= 1;
        list->faces = realloc(list->faces, list->capacity * sizeof(Face_t));
        assert(list->faces);
    }
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
    assert (vecs);
    vecs->list = malloc(LIST_INITIAL_CAPACITY * sizeof(Vec_t));
    assert (vecs->list);
    vecs->capacity = LIST_INITIAL_CAPACITY;
    vecs->len = 1;
    vecs->list[0] = head;
    return vecs;
}

static void resize_vecs(VecList_t *vecs) {
    if (vecs->len + 1 >= vecs->capacity) {
        vecs->capacity <<= 1;
        vecs->list = realloc(vecs->list, vecs->capacity * sizeof(Vec_t));
        assert (vecs->list);
    }
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

Scene_t* make_scene(Obj_t object) {
    Scene_t* scene = malloc(sizeof(Scene_t));
    assert(scene != NULL); 
    scene->objects = malloc(LIST_INITIAL_CAPACITY * sizeof(Obj_t));
    assert(scene->objects != NULL);
    scene->objects[0] = object;
    scene->len = 1;
    scene->capacity = LIST_INITIAL_CAPACITY;
    return scene;
}

static void resize_scene(Scene_t* scene) {
    if (scene->len + 1 >= scene->capacity) {
        scene->capacity <<= 1;
        scene->objects = realloc(scene->objects, scene->capacity * sizeof(Obj_t));
        assert(scene->objects != NULL);
    }
}

Scene_t* append_scene(Scene_t* scene, Obj_t object) {
    resize_scene(scene);
    scene->objects[scene->len++] = object;
    return scene;
}

void free_scene(Scene_t* scene) {
    for (int i = 0; i < scene->len; i++) {
        free_object(scene->objects[i]);
    }
    free(scene->objects);
    free(scene);
}
