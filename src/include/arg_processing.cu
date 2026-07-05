#include "arg_processing.h"

static void process_int_arg(int argc, char** argv, int* i, int* value) {
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
}

static void process_float_arg(int argc, char** argv, int* i, float* value) {
    if (*i + 1 == argc) { // i starts at option; move to first component argument
        fprintf(stderr, "[!] Insufficient values provided for option '%s'\n", argv[*i]);
        exit(EXIT_FAILURE);
    }
    *value = atof(argv[(*i)++ + 1]);
}

static void process_float3_args(int argc, char** argv, int* i, float3* value) {
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
}

void process_args(int argc, char** argv, bool* use_opengl, char** nvjpeg_output, bool* nvjpeg_first, bool* nvjpeg_last, bool* show_frametime, bool* use_denoising, bool* use_bloom, float3* cam_pos, float3* cam_dir, float3* cam_up, float* cam_speed, int* num_frames, int* image_quality) {
    *use_opengl = false;
    *nvjpeg_output = NULL;
    *nvjpeg_first = false;
    *nvjpeg_last = false;
    *show_frametime = false;
    *use_denoising = true;
    *use_bloom = true;
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
        else if (!strcmp(argv[i] + 1, "fi") || !strcmp(argv[i] + 1, "-first-image")) {
            if (!*nvjpeg_last) *nvjpeg_first = true;
            else {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with options -li/--last-image\n", argv[i]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "li") || !strcmp(argv[i] + 1, "-last-image")) {
            if (!*nvjpeg_first) *nvjpeg_last = true;
            else {
                fprintf(stderr, "[!] Option '%s' is mutually exclusive with options -fi/--first-image\n", argv[i]);
                exit(EXIT_FAILURE);
            }
        }
        else if (!strcmp(argv[i] + 1, "ft") || !strcmp(argv[i] + 1, "-show-frametime")) *show_frametime = true;
        else if (!strcmp(argv[i] + 1, "nd") || !strcmp(argv[i] + 1, "-no-denoising")) *use_denoising = false;
        else if (!strcmp(argv[i] + 1, "nb") || !strcmp(argv[i] + 1, "-no-bloom")) *use_bloom = false;
        else if (!strcmp(argv[i] + 1, "cam") || !strcmp(argv[i] + 1, "-camera-position")) process_float3_args(argc, argv, &i, cam_pos);
        else if (!strcmp(argv[i] + 1, "dir") || !strcmp(argv[i] + 1, "-camera-direction")) process_float3_args(argc, argv, &i, cam_dir);
        else if (!strcmp(argv[i] + 1, "up") || !strcmp(argv[i] + 1, "-camera-up")) process_float3_args(argc, argv, &i, cam_up);
        else if (!strcmp(argv[i] + 1, "spd") || !strcmp(argv[i] + 1, "-camera-speed")) process_float_arg(argc, argv, &i, cam_speed);
        else if (!strcmp(argv[i] + 1, "nf") || !strcmp(argv[i] + 1, "-num-frames")) process_int_arg(argc, argv, &i, num_frames);
        else if (!strcmp(argv[i] + 1, "iq") || !strcmp(argv[i] + 1, "-image-quality")) process_int_arg(argc, argv, &i, image_quality);
        else {
            fprintf(stderr, "[!] Unrecognised option '%s' provided\n", argv[i]);
            exit(EXIT_FAILURE);
        }
    }
}