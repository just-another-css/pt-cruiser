#include "test_scene.h"
#include "include/bound_box.h"
#include "include/math_utils.h"

#define NUM_SCENE_1_OBJECTS 8
#define NUM_SCENE_2_OBJECTS 4
#define NUM_SCENE_3_OBJECTS 7
#define NUM_SCENE_4_OBJECTS 7
#define NUM_SCENE_5_OBJECTS 5

static void initialise_unit_cube(PointsMesh* mesh, float3 offset, Material material, float scale) {
    const int num_triangles = 12, num_vertices = 8;
    *mesh = {
        .triangle_count = num_triangles,
        .vertex_count = num_vertices,
        .a = (int*) malloc(num_triangles * sizeof(int)),
        .b = (int*) malloc(num_triangles * sizeof(int)),
        .c = (int*) malloc(num_triangles * sizeof(int)),
        .vertices = (float3*) malloc(num_vertices * sizeof(float3)),
        .uv = (float2*) malloc(3 * num_triangles * sizeof(float2)),
        .materials = (Material*) malloc(num_triangles * sizeof(Material)),
    };
    float3 vertices[] = {
        offset,
        add_vec(offset, make_float3(scale, 0,     0)),
        add_vec(offset, make_float3(0,     scale, 0)),
        add_vec(offset, make_float3(0,     0,     scale)),
        add_vec(offset, make_float3(scale, scale, 0)),
        add_vec(offset, make_float3(scale, 0,     scale)),
        add_vec(offset, make_float3(0,     scale, scale)),
        add_vec(offset, make_float3(scale, scale, scale)),
    };
    memcpy(mesh->vertices, vertices, num_vertices * sizeof(float3));
    int a[] = {0,1,0,0,0,0,3,5,1,1,2,2};
    int b[] = {2,2,3,6,1,5,5,7,7,4,7,6};
    int c[] = {1,4,6,2,5,3,6,6,5,7,4,7};
    memcpy(mesh->a, a, num_triangles * sizeof(int));
    memcpy(mesh->b, b, num_triangles * sizeof(int));
    memcpy(mesh->c, c, num_triangles * sizeof(int));
    for (int i = 0; i < num_triangles * 3; i += 3) {
        mesh->uv[i] = make_float2(0, 0);
        mesh->uv[i + 1] = make_float2(0, 1);
        mesh->uv[i + 2] = make_float2(1, 0);
    }
    for (int i = 0; i < num_triangles; i++) mesh->materials[i] = material;
}

static void set_lightings(float3* lightings, PointsMesh* meshes, int n) {
    for (int i = 0; i < n; i++)
        lightings[i] = (meshes[i].materials[0] == LIGHT_SOURCE) ? make_float3(0.4f,0.4f,0.4f) : make_float3(0,0,0);
}

void initialise_test_scene_1(int* num_objects, PointsMesh** meshes, float3** lightings) {
    *num_objects = NUM_SCENE_1_OBJECTS;
    // Initialise meshes
    *meshes = (PointsMesh*) malloc(NUM_SCENE_1_OBJECTS * sizeof(PointsMesh));
    initialise_unit_cube(*meshes, make_float3(1.0f, 2.0f, 4), LIGHT_SOURCE, 3);
    initialise_unit_cube(*meshes + 1, make_float3(-1.5f, -0.5f, 5), METAL, 1);
    initialise_unit_cube(*meshes + 2, make_float3(0, 0, 3), GLASS, 1);
    initialise_unit_cube(*meshes + 3, make_float3(0, 3, 8), DIFFUSE, 1);
    initialise_unit_cube(*meshes + 4, make_float3(0, 0, 50), GLASS, 1);
    initialise_unit_cube(*meshes + 5, make_float3(-3, -5, 10), DIFFUSE, 1);
    initialise_unit_cube(*meshes + 6, make_float3(-0.5f, -0.5f, 2), GLASS, 1);
    initialise_unit_cube(*meshes + 7, make_float3(-0.5f, -0.5f, 4), LIGHT_SOURCE, 2);
    *lightings = (float3*) malloc(NUM_SCENE_1_OBJECTS * sizeof(float3));
    set_lightings(*lightings, *meshes, NUM_SCENE_1_OBJECTS);
}



void initialise_test_scene_2(int* num_objects, PointsMesh** meshes, float3** lightings) {
    *num_objects = NUM_SCENE_2_OBJECTS;
    *meshes = (PointsMesh*) malloc(NUM_SCENE_2_OBJECTS * sizeof(PointsMesh));
    initialise_unit_cube(*meshes, make_float3(0, 0, 5), GLASS, 1);
    initialise_unit_cube(*meshes + 1, make_float3(3, 0, 5), METAL, 1);
    initialise_unit_cube(*meshes + 2, make_float3(-5, -5, -5), DIFFUSE, 15); // floor
    initialise_unit_cube(*meshes + 3, make_float3(0, 5, 3), LIGHT_SOURCE, 1);
    *lightings = (float3*) malloc(NUM_SCENE_2_OBJECTS * sizeof(float3));
    set_lightings(*lightings, *meshes, NUM_SCENE_2_OBJECTS);
}

void initialise_test_scene_3(int* num_objects, PointsMesh** meshes, float3** lightings) {
    *num_objects = NUM_SCENE_3_OBJECTS;
    *meshes = (PointsMesh*) malloc(NUM_SCENE_3_OBJECTS * sizeof(PointsMesh));
    initialise_unit_cube(*meshes, make_float3(0, 0, 0), DIFFUSE, 1);
    initialise_unit_cube(*meshes + 1, make_float3(4, 0, 0), DIFFUSE, 1);
    initialise_unit_cube(*meshes + 2, make_float3(2, 0, 4), METAL, 1);
    initialise_unit_cube(*meshes + 3, make_float3(-5, -5, -5), DIFFUSE, 15); // floor
    initialise_unit_cube(*meshes + 4, make_float3(-2, 4, 0), LIGHT_SOURCE, 0.5); // left
    initialise_unit_cube(*meshes + 5, make_float3(6, 4, 0), LIGHT_SOURCE, 0.5); // right
    initialise_unit_cube(*meshes + 6, make_float3(2, 6, 4), LIGHT_SOURCE, 0.5); // top
    *lightings = (float3*) malloc(NUM_SCENE_3_OBJECTS * sizeof(float3));
    set_lightings(*lightings, *meshes, NUM_SCENE_3_OBJECTS);
}

void initialise_test_scene_4(int* num_objects, PointsMesh** meshes, float3** lightings) {
    *num_objects = NUM_SCENE_4_OBJECTS;
    *meshes = (PointsMesh*) malloc(NUM_SCENE_4_OBJECTS * sizeof(PointsMesh));

    // Room: large cube enclosing the camera at (0,0,-5).
    // Spans (-10,-8,-12) to (10,12,8), so the camera is comfortably inside.
    initialise_unit_cube(*meshes, make_float3(-10, -8, -12), DIFFUSE, 20);

    // Ceiling light: small cube near the top, centered over the room.
    initialise_unit_cube(*meshes + 1, make_float3(-1, 10.5f, -3), METAL, 2);

    // Desk top: a wide, thin slab in front of the camera.
    initialise_unit_cube(*meshes + 2, make_float3(-3, -3, 2), DIFFUSE, 1);
    // (the cube isn't actually thin — see note below)

    // Desk legs: four thin tall cubes under the corners of the desktop.
    initialise_unit_cube(*meshes + 3, make_float3(-3.0f, -6, 2.0f), GLASS, 0.4f);
    initialise_unit_cube(*meshes + 4, make_float3( 2.6f, -6, 2.0f), METAL, 0.4f);
    initialise_unit_cube(*meshes + 5, make_float3(-3.0f, -6, 5.6f), LIGHT_SOURCE, 0.4f);
    initialise_unit_cube(*meshes + 6, make_float3( 2.6f, -6, 5.6f), DIFFUSE, 0.4f);

    *lightings = (float3*) malloc(NUM_SCENE_4_OBJECTS * sizeof(float3));
    set_lightings(*lightings, *meshes, NUM_SCENE_4_OBJECTS);
}

#define NUM_SCENE_5_OBJECTS 5

void initialise_test_scene_5_vulnerable(int *num_objects, PointsMesh **meshes, float3 **lightings) {
    *num_objects = NUM_SCENE_5_OBJECTS;
    *meshes = (PointsMesh*) malloc(NUM_SCENE_5_OBJECTS * sizeof(PointsMesh));
    initialise_unit_cube(*meshes, make_float3(15, 0, 0), LIGHT_SOURCE, 1);
    initialise_unit_cube(*meshes + 1, make_float3(19, 1, 0), METAL, 5);
    initialise_unit_cube(*meshes + 2, make_float3(16, 1, 0), DIFFUSE, 2);
    initialise_unit_cube(*meshes + 3, make_float3(15, 2, 0), DIFFUSE, 1);
    initialise_unit_cube(*meshes + 4, make_float3(20, 4, 0), DIFFUSE, 1);
    *lightings = (float3*) malloc(NUM_SCENE_5_OBJECTS * sizeof(float3));
    set_lightings(*lightings, *meshes, NUM_SCENE_5_OBJECTS);
}

void initialise_test_scene_5(int* num_objects, PointsMesh** meshes, float3** lightings) {
    *num_objects = NUM_SCENE_5_OBJECTS;
    *meshes = (PointsMesh*) malloc(NUM_SCENE_5_OBJECTS * sizeof(PointsMesh));
    initialise_unit_cube(*meshes, make_float3(15, 0, 0), LIGHT_SOURCE, 1);
    initialise_unit_cube(*meshes + 1, make_float3(19, 1, 0), DIFFUSE, 5);
    initialise_unit_cube(*meshes + 2, make_float3(16, 1, 0), DIFFUSE, 2);
    initialise_unit_cube(*meshes + 3, make_float3(16, 5, 1), METAL, 1);
    initialise_unit_cube(*meshes + 4, make_float3(10, 1, 1), GLASS, 1);
    *lightings = (float3*) malloc(NUM_SCENE_5_OBJECTS * sizeof(float3));
    set_lightings(*lightings, *meshes, NUM_SCENE_5_OBJECTS);
    (*lightings)[3] = make_float3(0.4f,0.4f,0.4f);
}
