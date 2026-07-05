#include <GL/glew.h>
#include <GLFW/glfw3.h>
#include <cuda_gl_interop.h>
#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include "bvh.h"
#include "light_sources.h"
#include "objects.h"
#include "scene_processing.h"
#include "pathtracing.h"
#include "postprocess.h"
#include "math_utils.h"
#include <time.h>

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
static void init_opengl(int x_res, int y_res) {
    /* Variable Initialisations */
    if (!glfwInit()) {
        fputs("Failed to initialise GLFW", stderr);
        exit(EXIT_FAILURE);
    }
    window = glfwCreateWindow(x_res, y_res, "Extension - CUDA Rendering", NULL, NULL);
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
    glBufferData(GL_PIXEL_UNPACK_BUFFER, x_res * y_res * sizeof(uchar4), NULL, GL_DYNAMIC_DRAW);
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
    postprocess_init(&fb, &ds, x_res, y_res);
}

static void init_device(int num_objects, PointsMesh* meshes) {
    // Initialise objects list
    int* light_source_objs;
    initialise_objects(num_objects, meshes, &light_source_objs);
    CUDA_CHECK(cudaGetLastError());
    create_bvh();
    CUDA_CHECK(cudaGetLastError());
    // Initialise light source data
    initialise_light_sources(num_objects, meshes, light_source_objs);
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

static void render_frame(bool use_opengl, char* img_output, float3 cam_pos, float3 cam_up, float3 cam_dir, RenderParameters params) {
    size_t num_bytes;
    if (use_opengl) {
        CUDA_CHECK(cudaGraphicsMapResources(1, &cuda_pbo_resource, 0));
        CUDA_CHECK(cudaGraphicsResourceGetMappedPointer((void **) &fb.ldr_buf, &num_bytes, cuda_pbo_resource));
    }

    pathtrace(cam_pos, cam_up, cam_dir, fb.hdr_buf, fb.light_mask,
        params.x_res, params.y_res, params.pixel_ray_grid_dim, params.pixels_per_tile, params.ray_bounce_limit, params.x_fov);

    /* postprocessing: denoise -> bloom -> tonemap -> gamma -> ldr_buf */
    postprocess_run(&fb, &ds);
    if (img_output) postprocess_save_jpeg(&fb, &js, img_output);
    if (use_opengl) {
        CUDA_CHECK(cudaGraphicsUnmapResources(1, &cuda_pbo_resource, 0));
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo);
        glBindTexture(GL_TEXTURE_2D, textureID);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, params.x_res, params.y_res, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
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

static void process_float3_args(int argc, char** argv, int* i, float3* value) {
    float* value_f = &value->x;
    for (int j = 0; j < 3; j++) {
        if (*i + 1 == argc) { // i starts at option; move to first component argument
            fprintf(stderr, "[!] Insufficient values provided for option '%s'\n", argv[*i - j - 1]);
            exit(EXIT_FAILURE);
        }
        value_f[j] = atof(argv[(*i)++ + 1]);
    }
}

static void process_args(int argc, char** argv, bool* use_opengl, char** nvjpeg_output, bool* nvjpeg_first_only, float3* cam_pos, float3* cam_dir, float3* cam_up) {
    *use_opengl = false;
    *nvjpeg_output = NULL;
    *nvjpeg_first_only = false;
    for (int i = 2; i < argc; i++) {
        if (*argv[i] != '-') {
            fprintf(stderr, "[!] Option '%s' is incorrectly formatted\n", argv[i]);
            exit(EXIT_FAILURE);
        }
        if (!strcmp(argv[i] + 1, "i") || !strcmp(argv[i] + 1, "-image")) {
            if (++i < argc) {
                *nvjpeg_output = argv[i];
            } else {
                fprintf(stderr, "[!] No output file provided with option '%s' \n", argv[i - 1]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "r") || !strcmp(argv[i] + 1, "-realtime")) *use_opengl = true;
        else if (!strcmp(argv[i] + 1, "fio") || !strcmp(argv[i] + 1, "-first-image-only")) *nvjpeg_first_only = true;
        else if (!strcmp(argv[i] + 1, "cam") || !strcmp(argv[i] + 1, "-camera-position")) process_float3_args(argc, argv, &i, cam_pos);
        else if (!strcmp(argv[i] + 1, "dir") || !strcmp(argv[i] + 1, "-camera-direction")) process_float3_args(argc, argv, &i, cam_dir);
        else if (!strcmp(argv[i] + 1, "up") || !strcmp(argv[i] + 1, "-camera-up")) process_float3_args(argc, argv, &i, cam_up);
        else {
            fprintf(stderr, "[!] Unrecognised option '%s' provided\n", argv[i]);
            exit(EXIT_FAILURE);
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fputs("[!] No SDL file provided", stderr);
        fprintf(stderr, "Usage: %s <SDL source file> [<nvJPEG dest>]\n", argv[0]);
        return EXIT_FAILURE;
    }
    FILE *input_fp = fopen(argv[1], "r");
    if (!input_fp) {
        fprintf(stderr, "[!] Error: Cannot open file %s\n", argv[1]);
        return EXIT_FAILURE;
    }
    int num_objects;
    PointsMesh* meshes;
    RenderParameters params;
    parse_file(input_fp, &num_objects, &meshes, &params);
    puts("[+] Successfully parsed provided SDL file");
    fclose(input_fp);
    
    bool use_opengl, nvjpeg_first_only;
    char* nvjpeg_output;

    // float3 cam_pos = make_float3(-4000, 400, -1500), cam_dir = make_float3(1,0,0), cam_up = make_float3(0,1,0); // PT Cruiser scene
    float3 cam_pos = make_float3(0, 0, -3), cam_dir = make_float3(0,0,1), cam_up = make_float3(0,1,0); // Cornell box
    //float3 cam_pos = make_float3(0, 0, 0), cam_dir = make_float3(0,0,1), cam_up = make_float3(0,1,0); // Default

    process_args(argc, argv, &use_opengl, &nvjpeg_output, &nvjpeg_first_only, &cam_pos, &cam_dir, &cam_up);

    if (use_opengl) init_opengl(params.x_res, params.y_res);
    if (nvjpeg_output) {
        /* postprocessing setup */
        postprocess_init(&fb, &ds, params.x_res, params.y_res);
        postprocess_jpeg_init(&fb, &js, 90);
    }
    
    init_device(num_objects, meshes);
    
    struct timespec prev, cur;
    timespec_get(&prev, TIME_UTC);
    if (use_opengl) {
        while (!glfwWindowShouldClose(window)) {
            get_key_input(window, &cam_pos, &cam_up, &cam_dir);
            render_frame(use_opengl, nvjpeg_output, cam_pos, cam_up, cam_dir, params);
            glfwSwapBuffers(window);
            glfwPollEvents();
            timespec_get(&cur, TIME_UTC);
            float frametime = (cur.tv_sec - prev.tv_sec) * 1000.0 + (cur.tv_nsec - prev.tv_nsec) / 1000000.0;
            fprintf(stderr, "Time: %f ms / %f fps\n", frametime, 1000 / frametime);
            prev = cur;
            if (nvjpeg_first_only && nvjpeg_output) nvjpeg_output = NULL; // prevent saving future frames to file
        }
    } else {
        render_frame(use_opengl, nvjpeg_output, cam_pos, cam_up, cam_dir, params);
        timespec_get(&cur, TIME_UTC);
        float frametime = (cur.tv_sec - prev.tv_sec) * 1000.0 + (cur.tv_nsec - prev.tv_nsec) / 1000000.0;
        fprintf(stderr, "Time: %f ms / %f fps\n", frametime, 1000 / frametime);
    }
    
    clean_device();
    if (use_opengl) clean_opengl();
    else postprocess_jpeg_cleanup(&fb, &js);
    return EXIT_SUCCESS;
}
