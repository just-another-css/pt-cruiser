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

const char *lex_token_name(TokenEncoding code)
{
    switch (code) {
        case TOK_POINTS:     return "TOK_POINTS     ('points')";
        case TOK_FACES:      return "TOK_FACES      ('faces')";
        case TOK_CENTRE:     return "TOK_CENTRE     ('centre')";
        case TOK_COLOUR:     return "TOK_COLOUR     ('colour')";
        case TOK_MATERIAL:   return "TOK_MATERIAL   ('material')";
        case TOK_INT:        return "TOK_INT";
        case TOK_FLOAT:      return "TOK_FLOAT";
        case TOK_STRING:     return "TOK_STRING";
        case TOK_IDENT:      return "TOK_IDENT";
        case TOK_LBRACE:     return "TOK_LBRACE     ('{')";
        case TOK_RBRACE:     return "TOK_RBRACE     ('}')";
        case TOK_LSQBRACKET:   return "TOK_LBRACKET   ('[')";
        case TOK_RSQBRACKET:   return "TOK_RBRACKET   (']')";
        case TOK_LPAREN:     return "TOK_LPAREN     ('(')";
        case TOK_RPAREN:     return "TOK_RPAREN     (')')";
        case TOK_EQUALS:     return "TOK_EQUALS     ('=')";
        case TOK_COMMA:      return "TOK_COMMA      (',')";
        case TOK_COLON:      return "TOK_COLON      (':')";
        case TOK_NEWLINE:    return "TOK_NEWLINE";
        case TOK_EOF:        return "TOK_EOF";
        case TOK_ERROR:    return "TOK_UNKNOWN";
        default:             return "(unrecognised token code)";
    }
}

void print_token(FILE* out, Token tok)
{
    fprintf(out, "line %3d  %-38s", tok.line, lex_token_name(tok.code));

    switch (tok.code) {
        case TOK_INT:
            fprintf(out, "  value = %d", tok.value.ival);
            break;

        case TOK_FLOAT:
            fprintf(out, "  value = %f", tok.value.fval);
            break;

        case TOK_STRING:
        case TOK_IDENT:
            if (tok.value.sval != NULL)
                fprintf(out, "  value = \"%s\"", tok.value.sval);
            break;

        default:
            // keywords/punctuation have no value
            break;
    }

    putchar('\n');
}

