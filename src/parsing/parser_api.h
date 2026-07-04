#ifndef PARSER_API_H
#define PARSER_API_H

#include <stdbool.h>

#define MATERIAL_DESC_ARG 0
#define LIGHTING_DESC_ARG 1
#define UV_DESC_ARG 2

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

typedef enum {
    TEXTURE,
    TRANSPARENCY,
    CRITANGLE,
    REFRINDEX,
    SMOOTHNESS,
    ROUGHNESS,
} MatArgType;

typedef struct {
    MatArgType type;
    union {
        float num_val;
        char* filename;
    };
} MatArg;

typedef struct {
    char* texture_path;
    float transparency;
    float crit_angle;
    float refr_index;
    float smoothness;
    float roughness;
} MatArgs;

typedef struct {
    char* name;
    char* base;
    MatArgs* args;
} Mat_t;

typedef struct {
    char* name;
    union {
        float fval;
        int ival;
    };
} Param_t;

typedef enum {
    OBJECT,
    MATERIAL,
    PARAM,
} DefinitionType;

typedef struct {
    DefinitionType type;
    union {
        Obj_t obj;
        Mat_t mat;
        Param_t param;
    };
} Definition_t;

typedef struct {
    Obj_t* objects;
    int obj_capacity;
    int obj_len;
    Mat_t* materials;
    int mat_capacity;
    int mat_len;
    Param_t* params;
    int param_capacity;
    int param_len;
} Scene_t;

extern UV make_uv(float x, float y);
extern UVs* make_uvs(UV head);
extern UVs* append_uvs(UVs *uvs, UV value);

extern DescArg make_material(char *text);
extern DescArg make_lighting(float value);
extern DescArg make_uvdata(UVs *uvs);

extern DescArgs* make_desc_args(DescArg head);
extern DescArgs* make_empty_desc_args(void);
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

extern MatArg make_mat_texture(char* texture_path);
extern MatArg make_mat_num_arg(char* arg, float num_val);
extern MatArgs* make_mat_args(MatArg arg);
extern MatArgs* append_mat_args(MatArgs* args, MatArg arg);

extern Mat_t make_material_def(char* name, char* base_mat, MatArgs* args);
extern void free_material(Mat_t material);

extern Param_t make_float_param(char* name, float value);
extern Param_t make_int_param(char* name, int value);
extern void free_param(Param_t param);

extern Definition_t union_obj(Obj_t obj);
extern Definition_t union_mat(Mat_t mat);
extern Definition_t union_param(Param_t param);

extern Scene_t* make_scene(Definition_t definition);
extern Scene_t* append_scene(Scene_t* scene, Definition_t definition);
extern void free_scene(Scene_t* scene);

#endif