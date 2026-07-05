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

void process_args(int argc, char** argv, RenderParameters* params) {
    bool first_image_set = false, last_image_set = false, every_image_set = false;
    bool x_fov_set = false, y_fov_set = false;
    for (int i = 2; i < argc; i++) {
        if (*argv[i] != '-') {
            fprintf(stderr, "[!] Option '%s' is incorrectly formatted\n", argv[i]);
            exit(EXIT_FAILURE);
        }
        if (!strcmp(argv[i] + 1, "i") || !strcmp(argv[i] + 1, "-image")) {
            if (++i < argc) {
                params->nvjpeg_output = argv[i];
            } else {
                fprintf(stderr, "[!] No output file provided with option '%s' \n", argv[i - 1]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "r") || !strcmp(argv[i] + 1, "-realtime")) params->use_opengl = true;
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
        else if (!strcmp(argv[i] + 1, "nd") || !strcmp(argv[i] + 1, "-no-denoising")) params->use_denoising = false;
        else if (!strcmp(argv[i] + 1, "nb") || !strcmp(argv[i] + 1, "-no-bloom")) params->use_bloom = false;
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