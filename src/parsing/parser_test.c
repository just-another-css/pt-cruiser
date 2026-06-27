#include <stdio.h>
#include <stdlib.h>
#include "parser_api.h"
#include "parser.h"

#define DEFAULT_TAB 0

extern FILE *yyin;
extern int yyerrors;
extern Scene_t *parsed_scene;

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <input_file>\n", argv[0]);
        exit(EXIT_FAILURE);
    }
    FILE *fp = fopen(argv[1], "r");
    if (!fp) {
        fprintf(stderr, "[!] Error: Cannot open file %s\n", argv[1]);
        exit(EXIT_FAILURE);
    }
    yyin = fp;
    puts("[*] Starting parsing...");
    if (yyparse() == 0 && yyerrors == 0) {
        puts("[+] Successfully parsed!\n\n=================================\n");
        print_scene(parsed_scene, DEFAULT_TAB);
        free_scene(parsed_scene);
    } else {
        printf("[!] Failed with %d errors!\n", yyerrors);
        exit(EXIT_FAILURE);
    }
    fclose(fp);
    exit(EXIT_SUCCESS);
}
