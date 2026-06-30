%{
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include "parser_api.h"
#include "parser.h"

char lex_error_char = 0;
int lex_error_line = 0;
bool lex_have_error = false;

void lex_error(char ch, int line) {
    lex_error_char = ch;
    lex_error_line = line;
    lex_have_error = true;
}

%}

%option noyywrap
%option yylineno

DIGIT       [0-9]
INT         {DIGIT}+
FLOAT       -?{INT}\.{INT}
ALPHA       [A-Za-z]
OBJ_NAME    {ALPHA}+
TEXT        [A-Za-z ]+
WS          [ \t\r]+

%%

"points"            { return TOK_POINTS; }
"faces"             { return TOK_FACES; }
"centre"            { return TOK_CENTRE; }
"colour"            { return TOK_COLOUR; }
"material"          { return TOK_MATERIAL; }
"lighting"          { return TOK_LIGHTING; }
"uv"                { return TOK_UV; }

{FLOAT}             {   
                        yylval.fval = atof(yytext);
                        return TOK_FLOAT;
                    }

{INT}               {   
                        yylval.ival = atoi(yytext);
                        return TOK_INT;
                    }

\"({TEXT})\"        {   
                        int len = strlen(yytext) - 2; // -2 for quotes
                        yylval.sval = (char*) malloc(len + 1);
                        strncpy(yylval.sval, yytext + 1, len);
                        yylval.sval[len] = '\0'; // Null terminator
                        return TOK_STRING;
                    }

"//"[^\n]*          { /* Ignore all comments */ }

{OBJ_NAME}          {   
                        yylval.sval = strdup(yytext);
                        return TOK_IDENT;
                    }

"{"                 { return TOK_LBRACE; }
"}"                 { return TOK_RBRACE; }
"["                 { return TOK_LSQBRACKET; }
"]"                 { return TOK_RSQBRACKET; }
"("                 { return TOK_LPAREN; }
")"                 { return TOK_RPAREN; }
"="                 { return TOK_EQUALS; }
","                 { return TOK_COMMA; }
":"                 { return TOK_COLON; }

\n                  { return TOK_NEWLINE; }
{WS}                { /* Ignore whitespaces */ }

.                   {
                        lex_error(yytext[0], yylineno);
                        return TOK_ERROR;
                    }

%%
