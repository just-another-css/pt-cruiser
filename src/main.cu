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

static float time_diff(struct timespec start, struct timespec end) {
    return (end.tv_sec - start.tv_sec) * 1000.0 + (end.tv_nsec - start.tv_nsec) / 1000000.0;
}

static float time_since(struct timespec start) {
    struct timespec now;
    timespec_get(&now, TIME_UTC);
    return time_diff(start, now);
}

static void calc_frametime(struct timespec* prev, struct timespec* cur, float* frametime, bool show_frametime) {
    timespec_get(cur, TIME_UTC);
    *frametime = time_diff(*prev, *cur);
    if (show_frametime) fprintf(stderr, "Time: %f ms / %f fps\n", *frametime, 1000.0 / *frametime);
    *prev = *cur;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fputs("[!] No SDL file provided\n", stderr);
        return EXIT_FAILURE;
    }
    process_help_arg(argc, argv);
    
    int num_objects;
    PointsMesh* meshes;
    RenderParameters params;
    CameraPath* cam_path;
    init_parsing(&params);
    process_args(argc, argv, &params, &num_objects, &meshes, &cam_path);
    puts("[+] Successfully parsed options and SDL input");

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

    int frame_count = 0;
    bool loaded_camera_path = cam_path && params.use_cam_path, trace_camera_path = loaded_camera_path && params.start_cam_path, build_camera_path = false;
    if (trace_camera_path) {
        printf("[*] Tracing camera path...\n");
        start_trace_path(cam_path, &params);
    }
    struct timespec start, prev, cur, paused_start;
    bool use_frametime = params.show_frametime || params.cam_path_framerate;
    float frametime, cam_path_frametime = 1000.0 / params.cam_path_framerate, cam_path_fps_scale = 1;
    frametime = cam_path_frametime;
    int cam_path_frame_offset = 0, cam_path_frame_count;
    bool path_paused = false;
    float3 path_cam_pos, path_cam_dir, path_cam_up; // preserve cam pos/dir/up when pausing cam path
    float cum_path_paused = 0;
    int paused_start_frame = 0;
    if (params.cam_path_framerate && trace_camera_path) {
        timespec_get(&start, TIME_UTC);
        if (params.show_frametime) prev = start;
    } else if (params.show_frametime) timespec_get(&prev, TIME_UTC);
    if (params.use_opengl) {
        char* nvjpeg_frame_output = params.nvjpeg_last ? NULL : params.nvjpeg_output; // do not save every frame if nvjpeg_last set
        while (!glfwWindowShouldClose(window) && (!params.num_frames || frame_count < params.num_frames || (trace_camera_path && params.complete_cam_path) || !frame_count)) {
            if (loaded_camera_path) {
                if (trace_camera_path) {
trace:              trace_camera_path = trace_path(cam_path, params.cam_path_framerate ? ((time_diff(start, prev) - cum_path_paused) / cam_path_frametime) : (frame_count - cam_path_frame_offset), cam_path_fps_scale, &params, &cam_translation, &cam_rotation, &trace_camera_path);
                    if (!trace_camera_path) printf("[*] Camera path completed at frame %d\n", frame_count);
                    else {
                        trace_camera_path = glfwGetKey(window, GLFW_KEY_H) != GLFW_PRESS;
                        if (!trace_camera_path) printf("[*] Camera path aborted\n");
                        else if (glfwGetKey(window, GLFW_KEY_U) == GLFW_PRESS) {
                            printf("[*] Pausing camera path\n");
                            path_cam_pos = params.cam_pos;
                            path_cam_dir = params.cam_dir;
                            path_cam_up = params.cam_up;
                            cam_translation = make_float3(0,0,0);
                            cam_rotation = make_float3(0,0,0);
                            path_paused = true;
                            trace_camera_path = false;
                            if (params.cam_path_framerate) timespec_get(&paused_start, TIME_UTC);
                            else paused_start_frame = frame_count;
                        }
                    }
                } else if (!build_camera_path) {
                    if (glfwGetKey(window, GLFW_KEY_Y) == GLFW_PRESS) {
                        printf("[*] Tracing camera path...\n");
                        trace_camera_path = true;
                        cam_path_frame_offset = frame_count;
                        if (params.cam_path_framerate) {
                            timespec_get(&start, TIME_UTC);
                            cum_path_paused = 0;
                        } else cam_path_frame_offset = frame_count;
                        start_trace_path(cam_path, &params);
                    } else if (path_paused && glfwGetKey(window, GLFW_KEY_J) == GLFW_PRESS) {
                        printf("[*] Resuming camera path\n");
                        params.cam_pos = path_cam_pos;
                        params.cam_dir = path_cam_dir;
                        params.cam_up = path_cam_up;
                        path_paused = false;
                        trace_camera_path = true;
                        if (params.cam_path_framerate) cum_path_paused += time_since(paused_start);
                        else cam_path_frame_offset += frame_count - paused_start_frame;
                        goto trace;
                    }
                }
            }
            if (!trace_camera_path) {
                get_key_input(window, &params, &cam_translation, &cam_rotation);
                if (params.cam_path_output) {
                    cam_path_frame_count = params.cam_path_framerate ? (time_diff(start, prev) / cam_path_frametime) : (frame_count - cam_path_frame_offset);
                    if (build_camera_path) {
                        build_path(cam_path, &params, cam_path_frame_count, cam_translation, cam_rotation);
                        scale_vec_ip(cam_path_fps_scale, &cam_translation);
                        scale_vec_ip(cam_path_fps_scale, &cam_rotation);
                        if (glfwGetKey(window, GLFW_KEY_G) == GLFW_PRESS) {
                            build_camera_path = false;
                            finish_path(cam_path, &params, cam_path_frame_count);
                            FILE* cam_path_file = fopen(params.cam_path_output, params.append_cam_path ? "a" : "w");
                            if (params.append_cam_path) fputc('\n', cam_path_file);
                            write_path(cam_path, params.cam_path_framerate, cam_path_file);
                            fclose(cam_path_file);
                            printf("[*] Saved camera path with %d frames to %s\n", cam_path_frame_count, params.cam_path_output);
                        }
                    } else if (glfwGetKey(window, GLFW_KEY_T) == GLFW_PRESS) {
                        printf("[*] Recording camera path...\n");
                        build_camera_path = true;
                        cam_path_frame_offset = frame_count;
                        if (params.cam_path_framerate) timespec_get(&start, TIME_UTC);
                        init_path(&cam_path, &params, cam_translation, cam_rotation);
                    }
                }
            }
            move_cam(&params, cam_translation, cam_rotation);
            render_frame(params, nvjpeg_frame_output);
            glfwSwapBuffers(window);
            glfwPollEvents();
            if (use_frametime) {
                calc_frametime(&prev, &cur, &frametime, params.show_frametime);
                if ((trace_camera_path || build_camera_path) && params.cam_path_framerate) cam_path_fps_scale = frametime / cam_path_frametime;
            }
            if (nvjpeg_frame_output && params.nvjpeg_first && params.nvjpeg_output) nvjpeg_frame_output = NULL; // prevent saving future frames to file
            frame_count++;
        }
        if (params.nvjpeg_last) postprocess_save_jpeg(&fb, &js, params.nvjpeg_output);
    } else {
        do {
repeat:     if (loaded_camera_path && trace_camera_path && !(trace_camera_path = trace_path(cam_path, params.cam_path_framerate ? (time_diff(start, prev) / cam_path_frametime) : frame_count, cam_path_fps_scale, &params, &cam_translation, &cam_rotation, &trace_camera_path))) printf("[*] Camera path completed at frame %d\n", frame_count);
            render_frame(params, params.nvjpeg_output);
            if (use_frametime) {
                calc_frametime(&prev, &cur, &frametime, params.show_frametime);
                if (params.cam_path_framerate) cam_path_fps_scale = frametime / cam_path_frametime;
            }
            if (trace_camera_path && params.complete_cam_path) {
                frame_count++;
                goto repeat;
            }
        } while (++frame_count < params.num_frames);
    }
    
    if (cam_path) free_path(cam_path);
    clean_device();
    if (params.use_opengl) clean_opengl();
    else postprocess_jpeg_cleanup(&fb, &js);
    return EXIT_SUCCESS;
}
