#include "arg_processing.h"

#define MIN_FOV FLT_MIN
#define MAX_FOV M_PI

static void process_int_arg(int argc, char** argv, int* i, int* value, bool* assigned, int min_value, int max_value) {
    if (*i + 1 == argc) { // i starts at option; move to first component argument
        fprintf(stderr, "[!] No value provided for option '%s'\n", argv[*i]);
        exit(EXIT_FAILURE);
    }
    char* endptr;
    *value = strtol(argv[(*i)++ + 1], &endptr, 10);
    if (*endptr) {
        fprintf(stderr, "[!] Incorrectly formatted value '%s' for option '%s' (expected an int)\n", argv[*i], argv[*i - 1]);
        exit(EXIT_FAILURE);
    }
    if (*value < min_value || *value > max_value) {
        fprintf(stderr, "[!] Value %d ('%s') for option '%s' is not within permitted range [%d, %d]\n", *value, argv[*i], argv[*i - 1], min_value, max_value);
        exit(EXIT_FAILURE);
    }
    *assigned = true;
}

static void process_float_arg(int argc, char** argv, int* i, float* value, bool* assigned, float min_value, float max_value) {
    if (*i + 1 == argc) { // i starts at option; move to first component argument
        fprintf(stderr, "[!] Insufficient values provided for option '%s'\n", argv[*i]);
        exit(EXIT_FAILURE);
    }
    char* endptr;
    *value = strtof(argv[(*i)++ + 1], &endptr);
    if (*endptr) {
        fprintf(stderr, "[!] Incorrectly formatted value '%s' for option '%s' (expected a float)\n", argv[*i], argv[*i - 1]);
        exit(EXIT_FAILURE);
    }
    if (*value < min_value || *value > max_value) {
        fprintf(stderr, "[!] Value %f ('%s') for option '%s' is not within permitted range [%f, %f]\n", *value, argv[*i], argv[*i - 1], min_value, max_value);
        exit(EXIT_FAILURE);
    }
    *assigned = true;
}

static void process_float3_args(int argc, char** argv, int* i, float3* value, bool* assigned, bool force_nonzero, bool normalise) {
    float* value_f = &value->x;
    char* endptr;
    for (int j = 0; j < 3; j++) {
        if (*i + 1 == argc) { // i starts at option; move to first component argument
            fprintf(stderr, "[!] Insufficient values provided for option '%s'\n", argv[*i - j]);
            exit(EXIT_FAILURE);
        }
        value_f[j] = strtof(argv[(*i)++ + 1], &endptr);
        if (*endptr) {
            fprintf(stderr, "[!] Incorrectly formatted value '%s' for option '%s' (expected a float)\n", argv[*i], argv[*i - j - 1]);
            exit(EXIT_FAILURE);
        }
    }
    if (force_nonzero && vec_mag(*value) == 0) {
        fprintf(stderr, "[!] Value for option '%s' must be nonzero\n", argv[*i - 3]);
        exit(EXIT_FAILURE);
    }
    if (normalise) norm_vec_ip(value);
    *assigned = true;
}

static void process_filepath_arg(int argc, char** argv, int* i, char** filepath, bool* assigned, bool check_exists) {
    if (++(*i) < argc) {
        *filepath = argv[*i];
        if (check_exists) {
            FILE* file_test = fopen(*filepath, "r");
            if (file_test) fclose(file_test);
            else {
                fprintf(stderr, "[!] File '%s' provided with option '%s' could not be found\n", *filepath, argv[*i - 1]);
                exit(EXIT_FAILURE);
            }
        }
    } else {
        fprintf(stderr, "[!] No file provided with option '%s'\n", argv[*i - 1]);
        exit(EXIT_FAILURE);
    }
    *assigned = true;
}

void process_help_arg(int argc, char** argv) {
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--") && 
                !(!strcmp(argv[i - 1] + 1, "i") || !strcmp(argv[i - 1] + 1, "-image") || !strcmp(argv[i - 1] + 1, "ri")
                || !strcmp(argv[i - 1] + 1, "wcp") || !strcmp(argv[i - 1] + 1, "-write-camera-path"))) return;
        if (!strcmp(argv[i] + 1, "h") || !strcmp(argv[i] + 1, "-help")) {
            float3 default_cam_pos = CAM_POS, default_cam_dir = CAM_DIR, default_cam_up = CAM_UP;
            printf("Path Tracing CUDA Renderer with User Interface and Syntactic Entity\nRepresentation (PT CRUISER)\n\n"
                   "Usage: %s [\033[3moptions\033[0m [--]] <\033[3mSDL input...\033[0m>\n"
                   " \033[1mOPTIONS:\033[0m                                                                       \n"
                   "    -h,    --help                   Print usage information and exit\n"
                   "  Output:\n"
                   "    -i,    --image \033[3mFILE\033[0m             Provide a path to a JPEG (.jpg/.jpeg) image \n"
                   "                                    file to save rendered frames to\n"
                   "    -iq,   --image-quality \033[3mINT\033[0m      Set image quality [0-100] (default: %d)\n"
                   "    -fi,   --first-image            Save first frame to image file\n"
                   "    -li,   --last-image             Save last frame to image file (default)\n"
                   "    -ei,   --every-image            Save every frame to image file\n"
                   "    -r,    --realtime               Display rendered frames in an interactive   \n"
                   "                                    window and continue rendering until the     \n"
                   "                                    window is closed or a provided frame cap is \n"
                   "                                    reached\n"
                   "    -ri \033[3mFILE\033[0m                        Equivalent to '-r -i \033[3mFILE\033[0m'\n"
                   "  Rendering:\n"
                   "    -nf,   --num-frames \033[3mINT\033[0m         Set a cap on the number of frames rendered\n"
                   "                                    (default: %d; 0: unlimited)\n"
                   "    -ft,   --show-frametime         Print the frametime and FPS for every frame\n"
                   "    -nb,   --no-bloom               Disable bloom postprocessing\n"
                   "    -nd,   --no-denoising           Disable denoising postprocessing\n"
                   "    -xr,   --x-resolution \033[3mINT\033[0m       Set x/horizontal resolution (%d)\n"
                   "    -yr,   --y-resolution \033[3mINT\033[0m       Set y/vertical resolution (%d)\n"
                   "    -xf,   --x-fov \033[3mFLOAT\033[0m            Set x/horizontal field of view (%.2f)\n"
                   "    -yf,   --y-fov \033[3mFLOAT\033[0m            Set y/vertical field of view (%.2f)\n"
                   "    -prgd, --pixel-ray-grid-dim \033[3mINT\033[0m   Set dimension of pixel ray grids (%d)\n"
                   "    -rbl,  --ray-bounce-limit \033[3mINT\033[0m   Set pathtracing ray bounce limit (%d)\n"
                   "    -ppt,  --pixels-per-tile \033[3mINT\033[0m    Set number of pixels in each tile (%d)\n"
                   "  Camera & Camera Paths:\n"
                   "    -cam,  --camera-position \033[3mX Y Z\033[0m    Set initial camera position (%.0f,%.0f,%.0f)\n"
                   "    -dir,  --camera-direction \033[3mX Y Z\033[0m   Set initial camera direction (%.0f,%.0f,%.0f)\n"
                   "    -up,   --camera-up \033[3mX Y Z\033[0m          Set initial camera up vector (%.0f,%.0f,%.0f)\n"
                   "    -spd,  --camera-speed \033[3mFLOAT\033[0m       Set camera movement speed (%.2f)\n"
                   "    -rspd, --camera-rot-speed \033[3mFLOAT\033[0m   Set camera rotation speed (%.2f)\n"
                   "    -ncp,  --no-camera-path \033[3mFILE\033[0m    Ignore any camera paths in SDL file\n"
                   "    -scp,  --start-camera-path      Start tracing camera path on first frame\n"
                   "    -ccp,  --complete-camera-path   Override frame cap to render at least all\n"
                   "                                    frames in loaded camera path\n"
                   "    -pfr,  --path-framerate \033[3mINT\033[0m     Set camera path framerate for loaded and\n"
                   "                                    recorded paths (default: %d; 0: none set)\n"
                   "    -wcp,  --write-camera-path \033[3mFILE\033[0m   Overwrite given file with camera path\n"
                   " \033[1mOPERANDS:\033[0m\n"
                   "    <SDL input...>                  SDL (.sdl) file(s) defining a scene\n"
                   "\n\033[3mDefault values in parentheses, e.g. (10); vector components are float values\033[0m\n\n", argv[0],
                   NVJPEG_IMAGE_QUALITY, NO_FRAME_LIMIT, X_RES, Y_RES, X_FOV, Y_FOV, PIXEL_RAY_GRID_DIM, RAY_BOUNCE_LIMIT, TILE_PIXELS,
                   default_cam_pos.x, default_cam_pos.y, default_cam_pos.z, default_cam_dir.x, default_cam_dir.y, default_cam_dir.z, default_cam_up.x, default_cam_up.y, default_cam_up.z,
                   (float) CAM_SPEED, (float) CAM_ROTATION_SPEED, NO_PATH_FRAMERATE
            );
            exit(EXIT_SUCCESS);
        }
    }
}

#define PROCESS_IMAGE_CONTROL_ARG(arg, excl_arg1, excl_arg2, excl_desc) { \
    if (!excl_arg1##_image_set && !excl_arg2##_image_set) { \
        params->nvjpeg_##arg = true; \
        arg##_image_set = true; \
        if (params->nvjpeg_##excl_arg1) params->nvjpeg_##excl_arg1 = false; \
        if (params->nvjpeg_##excl_arg2) params->nvjpeg_##excl_arg2 = false; \
    } \
    else { \
        fprintf(stderr, "[!] Option '%s' is mutually exclusive with options " excl_desc "\n", argv[i]); \
        exit(EXIT_FAILURE); \
    } \
}

#define PROCESS_FOV_ARG(arg, excl_arg, excl_desc) { \
    if (!excl_arg##_fov_set) { \
        process_float_arg(argc, argv, &i, &params->arg##_fov, &assigned_params.arg##_fov, MIN_FOV, MAX_FOV); \
        arg##_fov_set = true; \
    } else { \
        fprintf(stderr, "[!] Option '%s' is mutually exclusive with option " excl_desc "\n", argv[i]); \
        exit(EXIT_FAILURE); \
    } \
}

#define MATCH_LONG_OPTION(option, label) if (!strcmp(arg + 2, option)) goto label;

void process_args(int argc, char** argv, RenderParameters* params, int* num_objects, PointsMesh** meshes, CameraPath** cam_path) {
    int i = 1;

    // Process options
    bool first_image_set = false, last_image_set = false, every_image_set = false;
    bool x_fov_set = false, y_fov_set = false;
    AssignedRenderParameters assigned_params = (AssignedRenderParameters) {}; // zero/false-init
    for (; i < argc; i++) {
        if (*argv[i] != '-') break;
        if (argv[i][1] == '-' && !argv[i][2]) { i++; break; }
        char* arg = argv[i] + 1; // omit leading '-'
        switch (*arg) {
            case 'i':
                switch (arg[1]) {
                    case '\0':
set_image:              process_filepath_arg(argc, argv, &i, &params->nvjpeg_output, &assigned_params.nvjpeg_output, false);
                        break;
                    case 'q':
                        if (arg[2]) goto invalid_option;
set_image_quality:      process_int_arg(argc, argv, &i, &params->image_quality, &assigned_params.image_quality, 0, 100);
                        break;
                    default:
                        goto invalid_option;
                }
                break;
            case 'r':
                switch (arg[1]) {
                    case 'i':
                        if (arg[2]) goto invalid_option;
                        process_filepath_arg(argc, argv, &i, &params->nvjpeg_output, &assigned_params.nvjpeg_output, false);
                        // fallthrough
                    case '\0':
set_realtime:           params->use_opengl = true;
                        assigned_params.use_opengl = true;
                        break;
                    case 'b':
                        if (arg[2] != 'l' || arg[3]) goto invalid_option;
set_bounce_limit:       process_int_arg(argc, argv, &i, &params->ray_bounce_limit, &assigned_params.ray_bounce_limit, 1, INT_MAX);
                        break;
                    case 's':
                        if (strcmp(arg + 2, "pd")) goto invalid_option;
set_cam_rotspeed:       process_float_arg(argc, argv, &i, &params->cam_rotation_speed, &assigned_params.cam_rotation_speed, 0, FLT_MAX);
                        break;
                    default:
                        goto invalid_option;
                }
                break;
            case 'f':
                switch (arg[1]) {
                    case 'i':
set_first_img:          PROCESS_IMAGE_CONTROL_ARG(first, last, every, "-li/--last-image & -ei/--every-image");
                        break;
                    case 't':
set_show_ft:            params->show_frametime = true;
                        assigned_params.show_frametime = true;
                        break;
                    default:
                        goto invalid_option;
                }
                break;
            case 'l':
                if (arg[1] != 'i') goto invalid_option;
set_last_img:   PROCESS_IMAGE_CONTROL_ARG(last, first, every, "-fi/--first-image & -ei/--every-image");
                break;
            case 'e':
                if (arg[1] != 'i') goto invalid_option;
set_every_img:  PROCESS_IMAGE_CONTROL_ARG(every, first, last, "-fi/--first-image & -li/--last-image");
                break;
            case 'n':
                if (!strcmp(arg + 1, "cp")) {
set_no_campath:     params->use_cam_path = false;
                    assigned_params.use_cam_path = true;
                    break;
                } else if (arg[2]) goto invalid_option;
                switch (arg[1]) {
                    case 'f':
set_num_frames:         process_int_arg(argc, argv, &i, &params->num_frames, &assigned_params.num_frames, 0, INT_MAX);
                        break;
                    case 'b':
set_no_bloom:           params->use_bloom = false;
                        assigned_params.use_bloom = true;
                        break;
                    case 'd':
set_no_denoising:       params->use_denoising = false;
                        assigned_params.use_denoising = true;
                        break;
                    default:
                        goto invalid_option;
                }
                break;
            case 'x':
                if (arg[2]) goto invalid_option;
                switch (arg[1]) {
                    case 'r':
set_x_res:              process_int_arg(argc, argv, &i, &params->x_res, &assigned_params.x_res, 1, INT_MAX);
                        break;
                    case 'f':
set_x_fov:              PROCESS_FOV_ARG(x, y, "-yf/--y-fov");
                        break;
                    default:
                        goto invalid_option;
                }
                break;
            case 'y':
                if (arg[2]) goto invalid_option;
                switch (arg[1]) {
                    case 'r':
set_y_res:              process_int_arg(argc, argv, &i, &params->y_res, &assigned_params.y_res, 1, INT_MAX);
                        break;
                    case 'f':
set_y_fov:              PROCESS_FOV_ARG(y, x, "-xf/--x-fov");
                        break;
                    default:
                        goto invalid_option;
                }
                break;
            case 'p':
                if (!strcmp(arg + 1, "rgd"))
set_prgd:           process_int_arg(argc, argv, &i, &params->pixel_ray_grid_dim, &assigned_params.pixel_ray_grid_dim, 1, INT_MAX);
                else if (!strcmp(arg + 1, "pt"))
set_pixels_per_tile:process_int_arg(argc, argv, &i, &params->pixels_per_tile, &assigned_params.pixels_per_tile, 1, INT_MAX);
                else if (!strcmp(arg + 1, "fr"))
set_campath_fr:     process_int_arg(argc, argv, &i, &params->cam_path_framerate, &assigned_params.cam_path_framerate, 0, INT_MAX);
                else goto invalid_option;
                break;
            case 'c':
                if (!strcmp(arg + 1, "am"))
set_cam_pos:        process_float3_args(argc, argv, &i, &params->cam_pos, &assigned_params.cam_pos, false, false);
                else if (!strcmp(arg + 1, "cp")) {
set_complete_campath:
                    params->complete_cam_path = true;
                    assigned_params.complete_cam_path = true;
                } else goto invalid_option;
                break;
            case 'd':
                if (strcmp(arg + 1, "ir")) goto invalid_option;
set_cam_dir:    process_float3_args(argc, argv, &i, &params->cam_dir, &assigned_params.cam_dir, true, true);
                break;
            case 'u':
                if (strcmp(arg + 1, "p")) goto invalid_option;
set_cam_up:     process_float3_args(argc, argv, &i, &params->cam_up, &assigned_params.cam_up, true, true);
                break;
            case 's':
                if (!strcmp(arg + 1, "pd"))
set_cam_speed:      process_float_arg(argc, argv, &i, &params->cam_speed, &assigned_params.cam_speed, 0, FLT_MAX);
                else if (!strcmp(arg + 1, "cp")) {
set_start_campath:  params->start_cam_path = true;
                    assigned_params.start_cam_path = true;
                } else goto invalid_option;
                break;
            case 'w':
                if (strcmp(arg + 1, "cp")) goto invalid_option;
set_campath_path:
                process_filepath_arg(argc, argv, &i, &params->cam_path_output, &assigned_params.cam_path_output, false);
                break;
            case '-':
                switch (arg[1]) {
                    case 'i':
                        MATCH_LONG_OPTION("mage", set_image)
                        MATCH_LONG_OPTION("mage-quality", set_image_quality)
                        goto invalid_option;
                    case 'r':
                        MATCH_LONG_OPTION("ealtime", set_realtime)
                        MATCH_LONG_OPTION("ay-bounce-limit", set_bounce_limit)
                        goto invalid_option;
                    case 'f':
                        MATCH_LONG_OPTION("irst-image", set_first_img)
                        goto invalid_option;
                    case 'l':
                        MATCH_LONG_OPTION("ast-image", set_last_img)
                        goto invalid_option;
                    case 'e':
                        MATCH_LONG_OPTION("very-image", set_every_img)
                        goto invalid_option;
                    case 's':
                        MATCH_LONG_OPTION("how-frametime", set_show_ft)
                        MATCH_LONG_OPTION("tart-camera-path", set_start_campath)
                        goto invalid_option;
                    case 'n':
                        MATCH_LONG_OPTION("o-bloom", set_no_bloom)
                        MATCH_LONG_OPTION("o-denoising", set_no_denoising)
                        MATCH_LONG_OPTION("o-camera-path", set_no_campath)
                        MATCH_LONG_OPTION("um-frames", set_num_frames)
                        goto invalid_option;
                    case 'c':
                        MATCH_LONG_OPTION("amera-position", set_cam_pos)
                        MATCH_LONG_OPTION("amera-direction", set_cam_dir)
                        MATCH_LONG_OPTION("amera-up", set_cam_up)
                        MATCH_LONG_OPTION("amera-speed", set_cam_speed)
                        MATCH_LONG_OPTION("amera-rot-speed", set_cam_rotspeed)
                        MATCH_LONG_OPTION("omplete-camera-path", set_complete_campath)
                        goto invalid_option;
                    case 'p':
                        MATCH_LONG_OPTION("ath-framerate", set_campath_fr)
                        MATCH_LONG_OPTION("ixel-ray-grid-dim", set_prgd)
                        MATCH_LONG_OPTION("ixels-per-tile", set_pixels_per_tile)
                        goto invalid_option;
                    case 'w':
                        MATCH_LONG_OPTION("rite-camera-path", set_campath_path)
                        goto invalid_option;
                    case 'x':
                        MATCH_LONG_OPTION("-fov", set_x_fov)
                        MATCH_LONG_OPTION("-resolution", set_x_res)
                        goto invalid_option;
                    case 'y':
                        MATCH_LONG_OPTION("-fov", set_y_fov)
                        MATCH_LONG_OPTION("-resolution", set_y_res)
                        goto invalid_option;
                    default:
                        goto invalid_option;
                }
            default:
invalid_option: fprintf(stderr, "[!] Unrecognised option '%s' provided\n", argv[i]);
                exit(EXIT_FAILURE);
                break;
        }
    }
    if (x_fov_set) {
        params->y_fov = params->x_fov * params->y_res / params->x_res;
        if (params->y_fov < MIN_FOV || params->y_fov > MAX_FOV) {
            fprintf(stderr, "[!] Y FOV %f is not within permitted range [%f, %f] due to provided resolution and X FOV\n", params->y_fov, MIN_FOV, MAX_FOV);
            exit(EXIT_FAILURE);
        }
    }
    else if (y_fov_set) {
        params->x_fov = params->y_fov * params->x_res / params->y_res;
        if (params->x_fov < MIN_FOV || params->x_fov > MAX_FOV) {
            fprintf(stderr, "[!] X FOV %f is not within permitted range [%f, %f] due to provided resolution and Y FOV\n", params->x_fov, MIN_FOV, MAX_FOV);
            exit(EXIT_FAILURE);
        }
    }

    // Process SDL files
    if (i < argc) for (; i < argc; i++) parse_file(argv[i]);
    else {
        fputs("[!] No SDL files were provided\n", stderr);
        exit(EXIT_FAILURE);
    }
    process_scene(num_objects, meshes, params, &assigned_params, cam_path);
}