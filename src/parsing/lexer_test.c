#include <stdio.h>
#include <stdlib.h>
#include "lexsupport.h"

extern FILE *yyin;

int main(int argc, char *argv[])
{
    if (argc > 2) {
        fprintf(stderr, "Usage: %s [input-file]\n", argv[0]);
        return EXIT_FAILURE;
    }

    if (argc == 2) {
        yyin = fopen(argv[1], "r");
        if (yyin == NULL) {
            perror(argv[1]);
            return EXIT_FAILURE;
        }
    }

    for (;;) {
        Token tok = lex_next_token();
        print_token(stdout, tok);
        if (tok.code == 0)
            break;
        if (tok.code == TOK_ERROR) {
            fprintf(stderr, "Lexer encountered an error.\n");
            break;
        }
    }

    if (argc == 2)
        fclose(yyin);

    return EXIT_SUCCESS;
}