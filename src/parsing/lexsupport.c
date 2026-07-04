#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lexsupport.h"

YYSTYPE yylval;

Token lex_next_token(void) {
    Token tok;
    memset(&tok, 0, sizeof(tok));

    int token_code = yylex();
    // detect EOF
    if (token_code == TOK_EOF) {
        tok.code = TOK_EOF;
        tok.line = yylineno;
        return tok;
    }

    tok.code  = (TokenEncoding)token_code;
    tok.line = yylineno;
    tok.value = yylval;

    return tok;
}

void lex_error(char ch, int line) {
    if (ch >= 32 && ch <= 127) { // Printable character
        fprintf(stderr, "Lexical error at line %d, unexpected character '%c' (0x%02X)", line, ch, (unsigned int)ch);
    } else { // Unprintable and/or invalid character
        fprintf(stderr, "Lexical error at line %d, unexpected character (0x%02X)", line, (unsigned int)ch);
    }
}
