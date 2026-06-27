#include <GL/glew.h>
#include <GLFW/glfw3.h>
#include <cuda_gl_interop.h>
#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include "bvh.h"
#include "light_sources.h"
#include "objects.h"
extern "C" {
    #include "parser_api.h"
    #include "parser.h"
}
#include "pathtracing.h"
#include "postprocess.h"
#include "math_utils.h"
#include <time.h>

#include "test_scene.h"

#define API_ERROR(msg) {\
    fputs(msg, stderr);\
    glfwDestroyWindow(window);\
    glfwTerminate();\
    exit(EXIT_FAILURE);\
}

// // GL & CUDA global variables
static GLFWwindow *window;
static GLuint pbo; // Pixel Buffer Object
static GLuint textureID;
static struct cudaGraphicsResource *cuda_pbo_resource;

static FrameBuffers fb;
static DenoiserState ds;
static JpegState js;

// Variables to be updated by parsed file accordingly
// const int img_width = 800;
// const int img_height = 600;

/* OpenGL & CUDA Initialisation */
static void init_opengl(void) {
    /* Variable Initialisations */
    if (!glfwInit()) {
        fputs("Failed to initialise GLFW", stderr);
        exit(EXIT_FAILURE);
    }
    window = glfwCreateWindow(X_RES, Y_RES, "Extension - CUDA Rendering", NULL, NULL);
    if (!window) {
        glfwTerminate();
        exit(EXIT_FAILURE);
    }
    glfwMakeContextCurrent(window);
    if (glewInit() != GLEW_OK) {
        API_ERROR("Failed to initialise GLEW");
    }
    /* Create PBO */
    glGenBuffers(1, &pbo);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo);
    glBufferData(GL_PIXEL_UNPACK_BUFFER, X_RES * Y_RES * sizeof(uchar4), NULL, GL_DYNAMIC_DRAW);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    // Register PBO to CUDA
    cudaGraphicsGLRegisterBuffer(&cuda_pbo_resource, pbo, cudaGraphicsRegisterFlagsWriteDiscard);
    /* Create Textures */
    glGenTextures(1, &textureID);
    glBindTexture(GL_TEXTURE_2D, textureID);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glBindTexture(GL_TEXTURE_2D, 0);
    /* postprocessing setup */
    postprocess_init(&fb, &ds, X_RES, Y_RES);
}

#ifndef TEST
extern FILE *yyin;
extern int yyerrors;
extern Scene_t *parsed_scene;

static void parse_input(int *num_objects, PointsMesh **mesh, float3 **lighting) {
    *num_objects = parsed_scene->len;
    *mesh = (PointsMesh*) malloc(parsed_scene->len * sizeof(PointsMesh));
    MALLOC_CHECK(*mesh);
    *lighting = (float3*) malloc(parsed_scene->len * sizeof(float3));
    MALLOC_CHECK(*lighting);
    for (int i = 0; i < parsed_scene->len; i++) {
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
        (*mesh)[i].materials = (Material*) malloc(num_triangles * sizeof(Material));
        MALLOC_CHECK((*mesh)[i].materials);
        (*mesh)[i].uv = (float2*) malloc(3 * num_triangles * sizeof(float2));
        MALLOC_CHECK((*mesh)[i].uv);
        for (int tri = 0; tri < num_triangles; tri++) {
            (*mesh)[i].a[tri] = parsed_scene->objects[i].faces->faces[tri].fst;
            (*mesh)[i].b[tri] = parsed_scene->objects[i].faces->faces[tri].snd;
            (*mesh)[i].c[tri] = parsed_scene->objects[i].faces->faces[tri].thr;
            bool material_flag = false, uv_flag = false;
            for (int a = 0; a < parsed_scene->objects[i].faces->faces[tri].desc_args->len; a++) {
                if (parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].type == 0) {
                    (*mesh)[i].materials[tri] = parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].material;
                    material_flag = true;
                }
                if (parsed_scene->objects[i].faces->faces[tri].desc_args->args[a].type == 2) {
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
                }
            }
            if (!material_flag) {
                fprintf(stderr, "[!] Material data is missing for object %d, face %d\n", i, tri);
                exit(EXIT_FAILURE);
            }
            if (!uv_flag) {
                fprintf(stderr, "[!] UV data is missing for object %d, face %d\n", i, tri);
                exit(EXIT_FAILURE);
            }
            if (tri && (*mesh)[i].materials[tri] != (*mesh)[i].materials[tri - 1]) {
                printf("[!] Note: In object %d, face %d is using a different material than others in the object.\n", i, tri);
            }
        }
        for (int v = 0; v < num_vertices; v++) {
            Vec_t now_v = parsed_scene->objects[i].points->list[v];
            (*mesh)[i].vertices[v] = make_float3(now_v.x, now_v.y, now_v.z);
        }
        bool light_flag = false;
        for (int a = 0; a < parsed_scene->objects[i].desc_args->len; a++) {
            if (parsed_scene->objects[i].desc_args->args[a].type == 1) {
                // The same value is copied over three times
                // If multiple colour is needed, upgrade the type system in parser_api
                float value = parsed_scene->objects[i].desc_args->args[a].lighting;
                (*lighting)[i] = make_float3(value, value, value);
                light_flag = true;
            }
        }
        if (!light_flag && (*mesh)[i].materials[0] == LIGHT_SOURCE) {
            fprintf(stderr, "[!] Lighting data is missing for light source: object %d\n", i);
            exit(EXIT_FAILURE);
        }
    }
    // print_scene(parsed_scene, 0);
    free_scene(parsed_scene);
}
#endif

static void init_device(void) {
    // Initialise test meshes
    int num_objects = 0;
    float3* lightings = NULL;
    PointsMesh* meshes = NULL;
#ifdef TEST
    initialise_test_scene_5(&num_objects, &meshes, &lightings);
#else
    parse_input(&num_objects, &meshes, &lightings);
#endif
    CUDA_CHECK(cudaGetLastError());
    // Initialise objects list
    initialise_objects(num_objects, lightings, meshes);
    CUDA_CHECK(cudaGetLastError());
    create_bvh();
    CUDA_CHECK(cudaGetLastError());
    initialise_materials_data();
    CUDA_CHECK(cudaGetLastError());
    // Initialise test textures
    initialise_material_texture(METAL, "textures/metal_texture.png");
    initialise_material_texture(GLASS, "textures/diffuse_texture.png");
    initialise_material_texture(LIGHT_SOURCE, "textures/light_source_texture.png");
    initialise_material_texture(DIFFUSE, "textures/diffuse_texture2.png");
    initialise_material_texture(LIGHT_DIFFUSE, "textures/diffuse_texture.png");
    initialise_material_texture(RED_DIFFUSE, "textures/red.png");
    initialise_material_texture(GREEN_DIFFUSE, "textures/green.png");
    CUDA_CHECK(cudaGetLastError());
    // Initialise light source data
    initialise_light_sources(num_objects, lightings, meshes);
    CUDA_CHECK(cudaGetLastError());
}

static void get_key_input(GLFWwindow* window, float3* cam_pos, float3* cam_up, float3* cam_dir) {
    if (glfwGetKey(window, GLFW_KEY_W) == GLFW_PRESS) add_vec_ip(cam_pos, *cam_dir);
    else if (glfwGetKey(window, GLFW_KEY_S) == GLFW_PRESS) add_vec_ip(cam_pos, scale_vec(-1, *cam_dir));
    else if (glfwGetKey(window, GLFW_KEY_A) == GLFW_PRESS) add_vec_ip(cam_pos, vec_cross_prod(*cam_up, *cam_dir));
    else if (glfwGetKey(window, GLFW_KEY_D) == GLFW_PRESS) add_vec_ip(cam_pos, scale_vec(-1, vec_cross_prod(*cam_up, *cam_dir)));
    else if (glfwGetKey(window, GLFW_KEY_Q) == GLFW_PRESS) add_vec_ip(cam_pos, *cam_up);
    else if (glfwGetKey(window, GLFW_KEY_E) == GLFW_PRESS) add_vec_ip(cam_pos, scale_vec(-1, *cam_up));
}

static void render_frame(char* img_output, float3 cam_pos, float3 cam_up, float3 cam_dir) {
    size_t num_bytes;
    if (!*img_output) {
        CUDA_CHECK(cudaGraphicsMapResources(1, &cuda_pbo_resource, 0));
        CUDA_CHECK(cudaGraphicsResourceGetMappedPointer((void **) &fb.ldr_buf, &num_bytes, cuda_pbo_resource));
    }

    pathtrace(cam_pos, cam_up, cam_dir, fb.hdr_buf, fb.light_mask);

    /* postprocessing: denoise -> bloom -> tonemap -> gamma -> ldr_buf */
    postprocess_run(&fb, &ds);
    if (*img_output) postprocess_save_jpeg(&fb, &js, img_output);
    else {
        CUDA_CHECK(cudaGraphicsUnmapResources(1, &cuda_pbo_resource, 0));
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo);
        glBindTexture(GL_TEXTURE_2D, textureID);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, X_RES, Y_RES, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);

        glEnable(GL_TEXTURE_2D);
        glBindTexture(GL_TEXTURE_2D, textureID);
        glBegin(GL_QUADS);
            glTexCoord2f(0, 1); glVertex2f(-1, -1);
            glTexCoord2f(1, 1); glVertex2f(1, -1);
            glTexCoord2f(1, 0); glVertex2f(1, 1);
            glTexCoord2f(0, 0); glVertex2f(-1, 1);
        glEnd();
        glBindTexture(GL_TEXTURE_2D, 0);
    }
}

static void clean_opengl(void) {
    postprocess_cleanup(&fb, &ds);
    postprocess_jpeg_cleanup(&fb, &js);
    cudaGraphicsUnregisterResource(cuda_pbo_resource);
    glDeleteBuffers(1, &pbo);
    glDeleteTextures(1, &textureID);
    glfwDestroyWindow(window);
    glfwTerminate();
}

static void clean_device(void) {
    // TODO: free meshes
    // TODO: free device arrays
    free_bvh();
    free_objects();
}

int main(int argc, char **argv) {
#ifndef TEST
    if (argc < 2) {
        fputs("[!] SDL source file missing", stderr);
        fprintf(stderr, "Usage: %s <SDL source file> [<nvJPEG dest>]\n", argv[0]);
        return EXIT_FAILURE;
    }
    FILE *input_fp = fopen(argv[1], "r");
    if (!input_fp) {
        fprintf(stderr, "[!] Error: Cannot open file %s\n", argv[1]);
        return EXIT_FAILURE;
    }
    yyin = input_fp;
    puts("[*] Starting parsing...");
    int result = yyparse();
    fclose(input_fp);
    if (result || yyerrors) {
        fprintf(stderr, "[!] Parsing failed with %d errors!\n", yyerrors);
        return EXIT_FAILURE;
    }
    puts("[+] Successfully parsed!");
    bool use_opengl = argc < 3;
    int jpeg_index = 2;
#else
    bool use_opengl = argc < 2;
    int jpeg_index = 1;
#endif
    if (use_opengl) {
        init_opengl();
    } else {
        /* postprocessing setup */
        postprocess_init(&fb, &ds, X_RES, Y_RES);
        postprocess_jpeg_init(&fb, &js, 90);
    }
    
    init_device();
    // float3 cam_pos = make_float3(-4000, 400, -1500), cam_up = make_float3(0,1,0), cam_dir = make_float3(1,0,0); // PT Cruiser scene
    float3 cam_pos = make_float3(0, 0, -3), cam_up = make_float3(0,1,0), cam_dir = make_float3(0,0,1); // Cornell box
    //float3 cam_pos = make_float3(0, 0, 0), cam_up = make_float3(0,1,0), cam_dir = make_float3(0,0,1); // Default
    struct timespec prev, cur;
    timespec_get(&prev, TIME_UTC);
    if (use_opengl) {
        while (!glfwWindowShouldClose(window)) {
            get_key_input(window, &cam_pos, &cam_up, &cam_dir);
            render_frame("\0", cam_pos, cam_up, cam_dir);
            glfwSwapBuffers(window);
            glfwPollEvents();
            timespec_get(&cur, TIME_UTC);
            float frametime = (cur.tv_sec - prev.tv_sec) * 1000.0 + (cur.tv_nsec - prev.tv_nsec) / 1000000.0;
            fprintf(stderr, "Time: %f ms / %f fps\n", frametime, 1000 / frametime);
            prev = cur;
        }
    } else {
        render_frame(argv[jpeg_index], cam_pos, cam_up, cam_dir);
        timespec_get(&cur, TIME_UTC);
        float frametime = (cur.tv_sec - prev.tv_sec) * 1000.0 + (cur.tv_nsec - prev.tv_nsec) / 1000000.0;
        fprintf(stderr, "Time: %f ms / %f fps\n", frametime, 1000 / frametime);
    }
    
    clean_device();
    if (use_opengl) clean_opengl();
    else postprocess_jpeg_cleanup(&fb, &js);
    return EXIT_SUCCESS;
}
