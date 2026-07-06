#include "arg_processing.h"

#define MIN_FOV FLT_MIN
#define MAX_FOV M_PI

static void process_int_arg(int argc, char** argv, int* i, int* value, int min_value, int max_value) {
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
}

static void process_float_arg(int argc, char** argv, int* i, float* value, float min_value, float max_value) {
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
}

static void process_float3_args(int argc, char** argv, int* i, float3* value, bool force_nonzero, bool normalise) {
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
}

static void process_filepath_arg(int argc, char** argv, int* i, char** filepath, bool skip_exists_check) {
    if (++(*i) < argc) {
        *filepath = argv[*i];
        if (skip_exists_check) return;
        FILE* file_test = fopen(*filepath, "r");
        if (file_test) fclose(file_test);
        else {
            fprintf(stderr, "[!] File '%s' provided with option '%s' could not be found\n", *filepath, argv[*i - 1]);
            exit(EXIT_FAILURE);
        }
    } else {
        fprintf(stderr, "[!] No file provided with option '%s'\n", argv[*i - 1]);
        exit(EXIT_FAILURE);
    }
}

void process_help_arg(int argc, char** argv) {
    for (int i = 1; i < argc; i++) {
        if (*argv[i] == '-' && (!strcmp(argv[i] + 1, "h") || !strcmp(argv[i] + 1, "-help"))) {
            printf("Path Tracing CUDA Renderer with User Interface and Syntactic Entity\nRepresentation (PT CRUISER)\n\n"
                   "Usage: %s <sdl_input> [options]\n"
                   "  Arguments:\n"
                   "    <sdl_input>                     SDL (.sdl) file defining a scene\n"
                   "  Options:                                                                      \n"
                   "    -h,    --help                   Print usage information and exit\n"
                   "    -i,    --image <file>           Provide a path to a JPEG (.jpg/.jpeg) image \n"
                   "                                    file to save rendered frames to\n"
                   "    -iq,   --image-quality <int>    Set image quality [0-100] (default: 90)\n"
                   "    -fi,   --first-image            Save first frame to image file\n"
                   "    -li,   --last-image             Save last frame to image file (default)\n"
                   "    -ei,   --every-image            Save every frame to image file\n"
                   "    -r,    --realtime               Display rendered frames in an interactive   \n"
                   "                                    window and continue rendering until the     \n"
                   "                                    window is closed or a provided frame cap is \n"
                   "                                    reached\n"
                   "    -ri <file>                      Equivalent to '-r -i <file>'\n"
                   "    -nf,   --num-frames <int>       Set a cap on the number of frames rendered\n"
                   "    -ft,   --show-frametime         Print the frametime and FPS for every frame\n"
                   "    -nb,   --no-bloom               Disable bloom postprocessing\n"
                   "    -nd,   --no-denoising           Disable denoising postprocessing\n"
                   "    -cam,  --camera-position <x> <y> <z>  Set initial camera position\n"
                   "    -dir,  --camera-direction <x> <y> <z> Set initial camera direction vector\n"
                   "    -up,   --camera-up <x> <y> <z>        Set initial camera up vector\n"
                   "    -spd,  --camera-speed <float>   Set camera movement speed\n"
                   "    -xf,   --x-fov <float>          Set x/horizontal field of view\n"
                   "    -yf,   --y-fov <float>          Set y/vertical field of view\n"
                   "    -xr,   --x-resolution <int>     Set x/horizontal resolution\n"
                   "    -yr,   --y-resolution <int>     Set y/vertical resolution\n"
                   "    -prgd, --pixel-ray-grid-dim <int>     Set dimension of pixel ray grids\n"
                   "    -rbl,  --ray-bounce-limit <int> Set pathtracing ray bounce limit\n"
                   "    -ppt,  --pixels-per-tile <int>  Set number of pixels in each rendering tile\n"
                   "\n", argv[0]
            );
            exit(EXIT_SUCCESS);
        }
    }
}

void process_args(int argc, char** argv, RenderParameters* params) {
    bool first_image_set = false, last_image_set = false, every_image_set = false;
    bool x_fov_set = false, y_fov_set = false;
    for (int i = 2; i < argc; i++) {
        if (*argv[i] != '-') {
            fprintf(stderr, "[!] Option '%s' is incorrectly formatted\n", argv[i]);
            exit(EXIT_FAILURE);
        }
        if (!strcmp(argv[i] + 1, "i") || !strcmp(argv[i] + 1, "-image")) process_filepath_arg(argc, argv, &i, &params->nvjpeg_output, true);
        else if (!strcmp(argv[i] + 1, "r") || !strcmp(argv[i] + 1, "-realtime")) params->use_opengl = true;
        else if (!strcmp(argv[i] + 1, "ri")) {
            params->use_opengl = true;
            process_filepath_arg(argc, argv, &i, &params->nvjpeg_output, true);
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
        else if (!strcmp(argv[i] + 1, "ft") || !strcmp(argv[i] + 1, "-show-frametime")) params->show_frametime = true;
        else if (!strcmp(argv[i] + 1, "nb") || !strcmp(argv[i] + 1, "-no-bloom")) params->use_bloom = false;
        else if (!strcmp(argv[i] + 1, "nd") || !strcmp(argv[i] + 1, "-no-denoising")) params->use_denoising = false;
        else if (!strcmp(argv[i] + 1, "cam") || !strcmp(argv[i] + 1, "-camera-position")) process_float3_args(argc, argv, &i, &params->cam_pos, false, false);
        else if (!strcmp(argv[i] + 1, "dir") || !strcmp(argv[i] + 1, "-camera-direction")) process_float3_args(argc, argv, &i, &params->cam_dir, true, true);
        else if (!strcmp(argv[i] + 1, "up") || !strcmp(argv[i] + 1, "-camera-up")) process_float3_args(argc, argv, &i, &params->cam_up, true, true);
        else if (!strcmp(argv[i] + 1, "spd") || !strcmp(argv[i] + 1, "-camera-speed")) process_float_arg(argc, argv, &i, &params->cam_speed, 0, FLT_MAX);
        else if (!strcmp(argv[i] + 1, "xf") || !strcmp(argv[i] + 1, "-x-fov")) {
            if (!y_fov_set) {
                process_float_arg(argc, argv, &i, &params->x_fov, MIN_FOV, MAX_FOV);
                x_fov_set = true;
            } else {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with option -yf/--y-fov\n", argv[i]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "yf") || !strcmp(argv[i] + 1, "-y-fov")) {
            if (!x_fov_set) {
                process_float_arg(argc, argv, &i, &params->y_fov, MIN_FOV, MAX_FOV);
                y_fov_set = true;
            } else {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with option -xf/--x-fov\n", argv[i]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "nf") || !strcmp(argv[i] + 1, "-num-frames")) process_int_arg(argc, argv, &i, &params->num_frames, 0, INT_MAX);
        else if (!strcmp(argv[i] + 1, "iq") || !strcmp(argv[i] + 1, "-image-quality")) process_int_arg(argc, argv, &i, &params->image_quality, 0, 100);
        else if (!strcmp(argv[i] + 1, "xr") || !strcmp(argv[i] + 1, "-x-resolution")) process_int_arg(argc, argv, &i, &params->x_res, 1, INT_MAX);
        else if (!strcmp(argv[i] + 1, "yr") || !strcmp(argv[i] + 1, "-y-resolution")) process_int_arg(argc, argv, &i, &params->y_res, 1, INT_MAX);
        else if (!strcmp(argv[i] + 1, "prgd") || !strcmp(argv[i] + 1, "-pixel-ray-grid-dim")) process_int_arg(argc, argv, &i, &params->pixel_ray_grid_dim, 1, INT_MAX);
        else if (!strcmp(argv[i] + 1, "rbl") || !strcmp(argv[i] + 1, "-ray-bounce-limit")) process_int_arg(argc, argv, &i, &params->ray_bounce_limit, 1, INT_MAX);
        else if (!strcmp(argv[i] + 1, "ppt") || !strcmp(argv[i] + 1, "-pixels-per-tile")) process_int_arg(argc, argv, &i, &params->pixels_per_tile, 1, INT_MAX);
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
}