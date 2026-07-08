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
#include "arg_processing.h"
#include "pathtracing.h"
#include "postprocess.h"
#include "math_utils.h"
#include <time.h>
#include "camera_paths.h"

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

static void get_key_input(GLFWwindow* window, RenderParameters* params, float3* translation, float3* rotation) {
    *translation = scale_vec(params->cam_speed, make_float3(
        (glfwGetKey(window, GLFW_KEY_A) == GLFW_PRESS) - (glfwGetKey(window, GLFW_KEY_D) == GLFW_PRESS),
        (glfwGetKey(window, GLFW_KEY_R) == GLFW_PRESS) - (glfwGetKey(window, GLFW_KEY_F) == GLFW_PRESS),
        (glfwGetKey(window, GLFW_KEY_W) == GLFW_PRESS) - (glfwGetKey(window, GLFW_KEY_S) == GLFW_PRESS)
    ));
    *rotation = scale_vec(params->cam_rotation_speed, make_float3(
        (glfwGetKey(window, GLFW_KEY_UP) == GLFW_PRESS) - (glfwGetKey(window, GLFW_KEY_DOWN) == GLFW_PRESS),
        (glfwGetKey(window, GLFW_KEY_LEFT) == GLFW_PRESS) - (glfwGetKey(window, GLFW_KEY_RIGHT) == GLFW_PRESS),
        (glfwGetKey(window, GLFW_KEY_E) == GLFW_PRESS) - (glfwGetKey(window, GLFW_KEY_Q) == GLFW_PRESS)
    ));
}

static void render_frame(RenderParameters params, char* img_output) {
    size_t num_bytes;
    if (params.use_opengl) {
        CUDA_CHECK(cudaGraphicsMapResources(1, &cuda_pbo_resource, 0));
        CUDA_CHECK(cudaGraphicsResourceGetMappedPointer((void **) &fb.ldr_buf, &num_bytes, cuda_pbo_resource));
    }

    pathtrace(params.cam_pos, params.cam_up, params.cam_dir, fb.hdr_buf, fb.light_mask,
        params.x_res, params.y_res, params.pixel_ray_grid_dim, params.pixels_per_tile, params.ray_bounce_limit, params.x_fov);

    /* postprocessing: denoise -> bloom -> tonemap -> gamma -> ldr_buf */
    postprocess_run(&fb, &ds, params.use_denoising, params.use_bloom);
    if (img_output) postprocess_save_jpeg(&fb, &js, img_output);
    if (params.use_opengl) {
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

static void calc_frametime(struct timespec* prev) {
    struct timespec cur;
    timespec_get(&cur, TIME_UTC);
    float frametime = (cur.tv_sec - prev->tv_sec) * 1000.0 + (cur.tv_nsec - prev->tv_nsec) / 1000000.0;
    fprintf(stderr, "Time: %f ms / %f fps\n", frametime, 1000.0 / frametime);
    *prev = cur;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fputs("[!] No SDL file provided\n", stderr);
        return EXIT_FAILURE;
    }
    process_help_arg(argc, argv);
    
    FILE *input_fp = fopen(argv[1], "r");
    if (!input_fp) {
        fprintf(stderr, "[!] Error: Cannot open file %s\n", argv[1]);
        return EXIT_FAILURE;
    }
    int num_objects;
    PointsMesh* meshes;
    RenderParameters params;
    init_params(&params);
    parse_file(input_fp, &num_objects, &meshes, &params);
    puts("[+] Successfully parsed provided SDL file");
    fclose(input_fp);

    process_args(argc, argv, &params);

    if (!params.use_opengl && !params.nvjpeg_output) {
        fputs("[!] No output method provided\n", stderr);
        return EXIT_FAILURE;
    }

    if (params.use_opengl) init_opengl(params.x_res, params.y_res);
    if (params.nvjpeg_output) {
        /* postprocessing setup */
        postprocess_init(&fb, &ds, params.x_res, params.y_res);
        postprocess_jpeg_init(&fb, &js, params.image_quality);
    }
    
    init_device(num_objects, meshes);
    
    float3 cam_translation, cam_rotation;
    CameraPath path;

    int frame_count = 0;
    struct timespec prev;
    if (params.show_frametime) timespec_get(&prev, TIME_UTC);
    if (params.use_opengl) {
        char* nvjpeg_frame_output = params.nvjpeg_last ? NULL : params.nvjpeg_output; // do not save every frame if nvjpeg_last set
        while (!glfwWindowShouldClose(window) && (frame_count != params.num_frames || !frame_count)) {
            get_key_input(window, &params, &cam_translation, &cam_rotation);
            move_cam(&params, cam_translation, cam_rotation);
            if (!frame_count) init_path(&path, &params, cam_translation, cam_rotation); // frame_count is 1 on first frame
            else build_path(&path, &params, frame_count - 1, cam_translation, cam_rotation);
            render_frame(params, nvjpeg_frame_output);
            glfwSwapBuffers(window);
            glfwPollEvents();
            if (params.show_frametime) calc_frametime(&prev);
            if (nvjpeg_frame_output && params.nvjpeg_first && params.nvjpeg_output) nvjpeg_frame_output = NULL; // prevent saving future frames to file
            frame_count++;
        }
        if (params.nvjpeg_last) postprocess_save_jpeg(&fb, &js, params.nvjpeg_output);
    } else {
        do {
            render_frame(params, params.nvjpeg_output);
            if (params.show_frametime) calc_frametime(&prev);
        } while (++frame_count < params.num_frames);
    }
    
    clean_device();
    if (params.use_opengl) clean_opengl();
    else postprocess_jpeg_cleanup(&fb, &js);
    return EXIT_SUCCESS;
}
