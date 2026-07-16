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
                   "    -acp,  --append-camera-path     Append camera path to loaded SDL file\n"
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

void process_args(int argc, char** argv, RenderParameters* params, int* num_objects, PointsMesh** meshes, CameraPath** cam_path) {
    int i = 1;

    // Process options
    bool first_image_set = false, last_image_set = false, every_image_set = false;
    bool append_cam_path_set = false, write_cam_path_set = false;
    bool x_fov_set = false, y_fov_set = false;
    AssignedRenderParameters assigned_params = (AssignedRenderParameters) {}; // zero/false-init
    for (; i < argc; i++) {
        if (*argv[i] != '-') break;
        if (argv[i][1] == '-' && !argv[i][2]) { i++; break; }
        if (!strcmp(argv[i] + 1, "i") || !strcmp(argv[i] + 1, "-image")) process_filepath_arg(argc, argv, &i, &params->nvjpeg_output, &assigned_params.nvjpeg_output, false);
        else if (!strcmp(argv[i] + 1, "r") || !strcmp(argv[i] + 1, "-realtime")) {
            params->use_opengl = true;
            assigned_params.use_opengl = true;
        }
        else if (!strcmp(argv[i] + 1, "ri")) {
            params->use_opengl = true;
            assigned_params.use_opengl = true;
            process_filepath_arg(argc, argv, &i, &params->nvjpeg_output, &assigned_params.nvjpeg_output, false);
            assigned_params.nvjpeg_output = true;
        }
        else if (!strcmp(argv[i] + 1, "fi") || !strcmp(argv[i] + 1, "-first-image")) {
            if (!last_image_set && !every_image_set) {
                params->nvjpeg_first = true;
                first_image_set = true;
                if (params->nvjpeg_last) params->nvjpeg_last = false;
                if (params->nvjpeg_every) params->nvjpeg_every = false;
            }
            else {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with options -li/--last-image & -ei/--every-image\n", argv[i]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "li") || !strcmp(argv[i] + 1, "-last-image")) {
            if (!first_image_set && !every_image_set) {
                params->nvjpeg_last = true;
                last_image_set = true;
                if (params->nvjpeg_first) params->nvjpeg_first = false;
                if (params->nvjpeg_every) params->nvjpeg_every = false;
            }
            else {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with options -fi/--first-image & -ei/--every-image\n", argv[i]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "ei") || !strcmp(argv[i] + 1, "-every-image")) {
            if (!first_image_set && !last_image_set) {
                params->nvjpeg_every = true;
                every_image_set = true;
                if (params->nvjpeg_first) params->nvjpeg_first = false;
                if (params->nvjpeg_last) params->nvjpeg_last = false;
            }
            else {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with options -fi/--first-image & -li/--last-image\n", argv[i]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "ft") || !strcmp(argv[i] + 1, "-show-frametime")) {
            params->show_frametime = true;
            assigned_params.show_frametime = true;
        }
        else if (!strcmp(argv[i] + 1, "nb") || !strcmp(argv[i] + 1, "-no-bloom")) {
            params->use_bloom = false;
            assigned_params.use_bloom = true;
        }
        else if (!strcmp(argv[i] + 1, "nd") || !strcmp(argv[i] + 1, "-no-denoising")) {
            params->use_denoising = false;
            assigned_params.use_denoising = true;
        }
        else if (!strcmp(argv[i] + 1, "cam") || !strcmp(argv[i] + 1, "-camera-position")) process_float3_args(argc, argv, &i, &params->cam_pos, &assigned_params.cam_pos, false, false);
        else if (!strcmp(argv[i] + 1, "dir") || !strcmp(argv[i] + 1, "-camera-direction")) process_float3_args(argc, argv, &i, &params->cam_dir, &assigned_params.cam_dir, true, true);
        else if (!strcmp(argv[i] + 1, "up") || !strcmp(argv[i] + 1, "-camera-up")) process_float3_args(argc, argv, &i, &params->cam_up, &assigned_params.cam_up, true, true);
        else if (!strcmp(argv[i] + 1, "spd") || !strcmp(argv[i] + 1, "-camera-speed")) process_float_arg(argc, argv, &i, &params->cam_speed, &assigned_params.cam_speed, 0, FLT_MAX);
        else if (!strcmp(argv[i] + 1, "rspd") || !strcmp(argv[i] + 1, "-camera-rot-speed")) process_float_arg(argc, argv, &i, &params->cam_rotation_speed, &assigned_params.cam_rotation_speed, 0, FLT_MAX);
        else if (!strcmp(argv[i] + 1, "ncp") || !strcmp(argv[i] + 1, "-no-camera-path")) {
            params->use_cam_path = false;
            assigned_params.use_cam_path = true;
        }
        else if (!strcmp(argv[i] + 1, "scp") || !strcmp(argv[i] + 1, "-start-camera-path")) {
            params->start_cam_path = true;
            assigned_params.start_cam_path = true;
        }
        else if (!strcmp(argv[i] + 1, "ccp") || !strcmp(argv[i] + 1, "-complete-camera-path")) {
            params->complete_cam_path = true;
            assigned_params.complete_cam_path = true;
        }
        else if (!strcmp(argv[i] + 1, "pfr") || !strcmp(argv[i] + 1, "-path-framerate")) process_int_arg(argc, argv, &i, &params->cam_path_framerate, &assigned_params.cam_path_framerate, 0, INT_MAX);
        else if (!strcmp(argv[i] + 1, "acp") || !strcmp(argv[i] + 1, "-append-camera-path")) {
            if (write_cam_path_set) {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with option -wcp/--write-camera-path\n", argv[i]);
                exit(EXIT_FAILURE);
            }
            params->append_cam_path = true;
            params->cam_path_output = argv[1];
            append_cam_path_set = true;
        }
        else if (!strcmp(argv[i] + 1, "wcp") || !strcmp(argv[i] + 1, "-write-camera-path")) {
            if (append_cam_path_set) {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with option -acp/--append-camera-path\n", argv[i]);
                exit(EXIT_FAILURE);
            }
            params->append_cam_path = false;
            process_filepath_arg(argc, argv, &i, &params->cam_path_output, &assigned_params.cam_path_output, false);
            write_cam_path_set = true;
        }
        else if (!strcmp(argv[i] + 1, "xf") || !strcmp(argv[i] + 1, "-x-fov")) {
            if (!y_fov_set) {
                process_float_arg(argc, argv, &i, &params->x_fov, &assigned_params.x_fov, MIN_FOV, MAX_FOV);
                x_fov_set = true;
            } else {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with option -yf/--y-fov\n", argv[i]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "yf") || !strcmp(argv[i] + 1, "-y-fov")) {
            if (!x_fov_set) {
                process_float_arg(argc, argv, &i, &params->y_fov, &assigned_params.y_fov, MIN_FOV, MAX_FOV);
                y_fov_set = true;
            } else {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with option -xf/--x-fov\n", argv[i]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "nf") || !strcmp(argv[i] + 1, "-num-frames")) process_int_arg(argc, argv, &i, &params->num_frames, &assigned_params.num_frames, 0, INT_MAX);
        else if (!strcmp(argv[i] + 1, "iq") || !strcmp(argv[i] + 1, "-image-quality")) process_int_arg(argc, argv, &i, &params->image_quality, &assigned_params.image_quality, 0, 100);
        else if (!strcmp(argv[i] + 1, "xr") || !strcmp(argv[i] + 1, "-x-resolution")) process_int_arg(argc, argv, &i, &params->x_res, &assigned_params.x_res, 1, INT_MAX);
        else if (!strcmp(argv[i] + 1, "yr") || !strcmp(argv[i] + 1, "-y-resolution")) process_int_arg(argc, argv, &i, &params->y_res, &assigned_params.y_res, 1, INT_MAX);
        else if (!strcmp(argv[i] + 1, "prgd") || !strcmp(argv[i] + 1, "-pixel-ray-grid-dim")) process_int_arg(argc, argv, &i, &params->pixel_ray_grid_dim, &assigned_params.pixel_ray_grid_dim, 1, INT_MAX);
        else if (!strcmp(argv[i] + 1, "rbl") || !strcmp(argv[i] + 1, "-ray-bounce-limit")) process_int_arg(argc, argv, &i, &params->ray_bounce_limit, &assigned_params.ray_bounce_limit, 1, INT_MAX);
        else if (!strcmp(argv[i] + 1, "ppt") || !strcmp(argv[i] + 1, "-pixels-per-tile")) process_int_arg(argc, argv, &i, &params->pixels_per_tile, &assigned_params.pixels_per_tile, 1, INT_MAX);
        else {
            fprintf(stderr, "[!] Unrecognised option '%s' provided\n", argv[i]);
            exit(EXIT_FAILURE);
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