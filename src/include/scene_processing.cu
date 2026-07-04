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

static void parse_input(int* num_objects, PointsMesh** mesh) {
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
        bool default_material_set = false, default_lighting_set = false;
        int default_material;
        float3 default_lighting;
        float value;
        for (int a = 0; a < parsed_scene->objects[i].desc_args->len; a++) {
            switch (parsed_scene->objects[i].desc_args->args[a].type) {
                case 0: // material
                    default_material = find_material(parsed_scene->objects[i].desc_args->args[a].material, material_names, parsed_scene->mat_len);
                    if (default_material == INVALID_MATERIAL) {
                        default_material = find_material(parsed_scene->objects[i].desc_args->args[a].material, default_material_names, NUM_DEFAULT_MATERIALS);
                        if (default_material == INVALID_MATERIAL) {
                            fprintf(stderr, "[!] Unidentified material '%s' used in object %d", parsed_scene->objects[i].desc_args->args[a].material, i);
                            exit(EXIT_FAILURE);
                        }
                        if (!use_default_materials[default_material]) {
                            use_default_materials[default_material] = true;
                            default_material_is[default_material] = num_total_materials++;
                        }
                        default_material = default_material_is[default_material];
                    }
                    default_material_set = true;
                    break;
                case 1: // lighting
                    value = parsed_scene->objects[i].desc_args->args[a].lighting;
                    default_lighting = make_float3(value, value, value);
                    default_lighting_set = true;
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
                    case 0: // material
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
                    case 1: // lighting
                        intensity = parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].lighting;
                        (*mesh)[i].lightings[tri] = make_float3(intensity, intensity, intensity); // lighting is effectively a scalar applied to the colour of the object's texture
                        lighting_flag = true;
                        break;
                    case 2: // uv
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
                if (default_material_set) (*mesh)[i].materials[tri] = default_material;
                else {
                    fprintf(stderr, "[!] No material was provided for face %d of object %d, and no material was provided for the object\n", tri, i);
                    exit(EXIT_FAILURE);
                }
            }
            if (!lighting_flag) {
                (*mesh)[i].lightings[tri] = default_lighting_set ? default_lighting : make_float3(0,0,0); // default to unlit or object lighting
            }
            if (!uv_flag) {
                (*mesh)[i].uv[tri * 3] = make_float2(0, 0);
                (*mesh)[i].uv[tri * 3 + 1] = make_float2(1, 0);
                (*mesh)[i].uv[tri * 3 + 2] = make_float2(0, 1);
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
    // Free parsed scene struct
    free_scene(parsed_scene);
}

void parse_file(FILE* input, int* num_objects, PointsMesh** meshes) {
    yyin = input;
    puts("[*] Starting parsing...");
    int result = yyparse();
    if (result || yyerrors) {
        fprintf(stderr, "[!] Parsing failed with %d errors!\n", yyerrors);
        exit(EXIT_FAILURE);
    }
    puts("[*] Parsing finished");
    parse_input(num_objects, meshes);
}
