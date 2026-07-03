#ifndef PARSER_API_H
#define PARSER_API_H

#include <stdbool.h>

typedef struct {
    float x;
    float y;
} UV;

typedef struct {
    UV list[3];
    int len;
} UVs;

typedef struct {
    // 0: material; 1; lighting; 2: uv
    int type;
    union {
        char* material;
        float lighting;
        UVs *uvs;
    };
} DescArg;

typedef struct {
    DescArg* args;
    int capacity;
    int len;
} DescArgs;

typedef struct {
    float x;
    float y;
    float z;
} Vec_t;

typedef struct {
    int *list;
    int capacity;
    int len;
} IntList;

typedef struct {
    Vec_t *list;
    int capacity;
    int len;
} VecList_t;

typedef struct {
    int fst;
    int snd;
    int thr;
    DescArgs* desc_args;
} Face_t;

typedef struct {
    Face_t* faces;
    int capacity;
    int len;
} FaceList_t;

typedef struct {
    char* name;
    VecList_t* points;
    FaceList_t* faces;
    DescArgs* desc_args;
} Obj_t;

typedef struct {
    Obj_t* objects;
    int capacity;
    int len;
} Scene_t;

extern UV make_uv(float x, float y);
extern UVs* make_uvs(UV head);
extern UVs* append_uvs(UVs *uvs, UV value);

extern DescArg make_material(char *text);
extern DescArg make_lighting(float value);
extern DescArg make_uvdata(UVs *uvs);

extern DescArgs* make_desc_args(DescArg head);
extern DescArgs* append_desc_args(DescArgs* args, DescArg value);
extern void free_desc_args(DescArgs* args);

extern IntList* make_int_list(int head);
extern IntList* append_int_list(IntList *int_list, int value);
extern void free_int_list(IntList *list);

extern Face_t make_face(IntList *list, DescArgs *args);

extern FaceList_t* make_face_list(Face_t face);
extern FaceList_t* append_face_list(FaceList_t* facelist, Face_t face);
extern void free_face_list(FaceList_t* facelist);

extern Vec_t make_vec(float x, float y, float z);

extern VecList_t* make_vecs(Vec_t head);
extern VecList_t* append_vecs(VecList_t *vecs, Vec_t value);
extern void free_vecs(VecList_t *vecs);

extern Obj_t make_object(char *name, VecList_t *vecs, FaceList_t *faces, DescArgs *args);
extern void free_object(Obj_t object);

extern Scene_t* make_scene(Obj_t object);
extern Scene_t* append_scene(Scene_t* scene, Obj_t object);
extern void free_scene(Scene_t* scene);

extern void print_scene(Scene_t *scene, int tabs);

#endif
