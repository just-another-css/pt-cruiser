#ifndef LEX_SUPPORT_H
#define LEX_SUPPORT_H

typedef enum {
    // Keywords
    TOK_EOF = 0,
    TOK_POINTS = 1,
    TOK_FACES,
    TOK_CENTRE,
    TOK_COLOUR,
    TOK_MATERIAL,
    TOK_TEXTURE,
    TOK_MAT_NUM_ARG,

    // Numbers
    TOK_INT,
    TOK_FLOAT,

    // Text
    TOK_STRING,
    TOK_FILEPATH,
    TOK_IDENT, // Identifiers
    TOK_FILENAME,

    // Punctuation characters
    TOK_LBRACE,
    TOK_RBRACE,
    TOK_LSQBRACKET,
    TOK_RSQBRACKET,
    TOK_LPAREN,
    TOK_RPAREN,
    TOK_EQUALS,
    TOK_COMMA,
    TOK_COLON,
    TOK_QUOTE,

    // Misc
    TOK_NEWLINE,
    TOK_ERROR
} TokenEncoding;

typedef union {
    int ival;
    float fval;
    char* sval;
} YYSTYPE;

extern YYSTYPE yylval;
extern int yylineno; // Line number

typedef struct {
    TokenEncoding code;
    YYSTYPE value;
    int line;
} Token;

extern Token lex_next_token(void);

extern const char* lex_token_name(TokenEncoding code);

extern void lex_error(char ch, int line);

extern int yylex(void);

extern void print_token( FILE * out, Token tok );

#endif
