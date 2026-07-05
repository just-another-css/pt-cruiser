#include "arg_processing.h"

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

static void process_float_arg(int argc, char** argv, int* i, float* value) {
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
}

static void process_float3_args(int argc, char** argv, int* i, float3* value, bool normalise) {
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
    norm_vec_ip(value);
}

void process_args(int argc, char** argv, RenderParameters* params) {
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
            if (!params->nvjpeg_last) params->nvjpeg_first = true;
            else {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with options -li/--last-image\n", argv[i]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "li") || !strcmp(argv[i] + 1, "-last-image")) {
            if (!params->nvjpeg_first) params->nvjpeg_last = true;
            else {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with options -fi/--first-image\n", argv[i]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "ft") || !strcmp(argv[i] + 1, "-show-frametime")) params->show_frametime = true;
        else if (!strcmp(argv[i] + 1, "nd") || !strcmp(argv[i] + 1, "-no-denoising")) params->use_denoising = false;
        else if (!strcmp(argv[i] + 1, "nb") || !strcmp(argv[i] + 1, "-no-bloom")) params->use_bloom = false;
        else if (!strcmp(argv[i] + 1, "cam") || !strcmp(argv[i] + 1, "-camera-position")) process_float3_args(argc, argv, &i, &params->cam_pos, false);
        else if (!strcmp(argv[i] + 1, "dir") || !strcmp(argv[i] + 1, "-camera-direction")) process_float3_args(argc, argv, &i, &params->cam_dir, true);
        else if (!strcmp(argv[i] + 1, "up") || !strcmp(argv[i] + 1, "-camera-up")) process_float3_args(argc, argv, &i, &params->cam_up, true);
        else if (!strcmp(argv[i] + 1, "spd") || !strcmp(argv[i] + 1, "-camera-speed")) process_float_arg(argc, argv, &i, &params->cam_speed);
        else if (!strcmp(argv[i] + 1, "nf") || !strcmp(argv[i] + 1, "-num-frames")) process_int_arg(argc, argv, &i, &params->num_frames, 0, INT_MAX);
        else if (!strcmp(argv[i] + 1, "iq") || !strcmp(argv[i] + 1, "-image-quality")) process_int_arg(argc, argv, &i, &params->image_quality, 0, 100);
        else {
            fprintf(stderr, "[!] Unrecognised option '%s' provided\n", argv[i]);
            exit(EXIT_FAILURE);
        }
    }
}