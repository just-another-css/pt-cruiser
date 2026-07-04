%{
#include <stdio.h>
#include <string.h>
#include "parser_api.h"

extern int yylex (void);
extern int yylineno;

extern char lex_error_char;
extern int lex_error_line;
extern bool lex_have_error;

Scene_t *parsed_scene = NULL;
int yyerrors = 0;

void yyerror(const char *str) {
	if (lex_have_error) {
		if (lex_error_char >= 32 && lex_error_char <= 127) { // Printable character
			fprintf(stderr, "Lexical error at line %d, unexpected character '%c' (0x%02X)\n", lex_error_line, lex_error_char, (unsigned int)lex_error_char);
		} else { // Unprintable and/or invalid character
			fprintf(stderr, "Lexical error at line %d, unexpected character (0x%02X)\n", lex_error_line, (unsigned int)lex_error_char);
		}
		lex_have_error = false;
	} else {
		fprintf(stderr, "line %d: error: %s", yylineno, str);
	}
    yyerrors++;
	fflush(stderr);
}
int yywrap(void) {
    return 1;
}

%}

%union {
    int ival;
    float fval;
    char *sval;

    Scene_t *sc;
    Definition_t def;
    IntList *il;
    UV u;
    UVs *us;
    DescArgs *das;
    DescArg da;
    FaceList_t *fl;
    Face_t f;
    VecList_t *vl;
    Vec_t v;
    Obj_t o;
    Mat_t m;
    MatArgs *mas;
    MatArg ma;
    Param_t p;
}

%token TOK_POINTS TOK_FACES TOK_CENTRE TOK_COLOUR TOK_MATERIAL TOK_LIGHTING TOK_UV
%token <fval> TOK_POSFLOAT TOK_NEGFLOAT
%token <ival> TOK_INT
%token <sval> TOK_STRING TOK_MAT_NUM_ARG TOK_TEXTURE TOK_FILEPATH TOK_IDENT TOK_PARAM
%token TOK_LBRACE TOK_RBRACE TOK_LSQBRACKET TOK_RSQBRACKET TOK_LPAREN TOK_RPAREN TOK_EQUALS TOK_COMMA TOK_COLON TOK_NEWLINE
%token TOK_ERROR

%type <sc> scene
%type <def> definition
%type <il> ints int_list
%type <das> desc_args
%type <da> desc_arg
%type <fl> face_list faces
%type <f> face
%type <vl> vec_list vecs
%type <v> vec
%type <o> obj
%type <us> uv_list uvs
%type <u> uv
%type <m> material
%type <mas> mat_args
%type <ma> mat_arg
%type <p> parameter
%type <fval> float

%start top

%%
top         : scene                                     { parsed_scene = $1; }
            ;

scene       : scene TOK_NEWLINE definition              { $$ = append_scene($1, $3); }
            | definition                                { $$ = make_scene($1); }
            ;

definition  : obj                                       { $$ = union_obj($1); }
            | material                                  { $$ = union_mat($1); }
            | parameter                                 { $$ = union_param($1); }
            ;

obj         : TOK_IDENT TOK_EQUALS TOK_LBRACE
              TOK_POINTS TOK_EQUALS vec_list TOK_COMMA
              TOK_FACES TOK_EQUALS face_list desc_args
              TOK_RBRACE                                { $$ = make_object($1, $6, $10, $11); }
            ;

vec_list    : TOK_LSQBRACKET vecs TOK_RSQBRACKET        { $$ = $2; }
            ;

vecs        : vecs TOK_COMMA vec                        { $$ = append_vecs($1, $3); }
            | vec                                       { $$ = make_vecs($1); }
            ;

vec         : TOK_LPAREN float TOK_COMMA
              float TOK_COMMA
              float TOK_RPAREN                          { $$ = make_vec($2, $4, $6); }
            ;

face_list   : TOK_LSQBRACKET faces TOK_RSQBRACKET       { $$ = $2; }
            ;

faces       : faces TOK_COMMA face                      { $$ = append_face_list($1, $3); }
            | face                                      { $$ = make_face_list($1); }
            ;

face        : TOK_LBRACE TOK_POINTS TOK_EQUALS
              int_list desc_args TOK_RBRACE             { $$ = make_face($4, $5); }
            | int_list                                  { $$ = make_face($1, NULL); }
            ;

int_list    : TOK_LSQBRACKET ints TOK_RSQBRACKET        { $$ = $2; }
            ;

ints        : ints TOK_COMMA TOK_INT                    { $$ = append_int_list($1, $3); }
            | TOK_INT                                   { $$ = make_int_list($1); }
            ;

desc_args   : desc_args desc_arg                        { $$ = append_desc_args($1, $2); }
            | desc_arg                                  { $$ = make_desc_args($1); }
            |                                           { $$ = make_empty_desc_args(); }
            ;

desc_arg    : TOK_COMMA TOK_MATERIAL
              TOK_EQUALS TOK_STRING                     { $$ = make_material($4); }
            | TOK_COMMA TOK_LIGHTING
              TOK_EQUALS TOK_POSFLOAT                   { $$ = make_lighting($4); }
            | TOK_COMMA TOK_UV TOK_EQUALS uv_list       { $$ = make_uvdata($4); }
            ;

uv_list     : TOK_LSQBRACKET uvs TOK_RSQBRACKET         { $$ = $2; }
            ;

uvs         : uvs TOK_COMMA uv                          { $$ = append_uvs($1, $3); }
            | uv                                        { $$ = make_uvs($1); }
            ;

uv          : TOK_LPAREN TOK_POSFLOAT TOK_COMMA
              TOK_POSFLOAT TOK_RPAREN                   { $$ = make_uv($2, $4); }
            ;

material    : TOK_STRING TOK_COLON
              TOK_LSQBRACKET mat_args TOK_RSQBRACKET    { $$ = make_material_def($1, NULL, $4); }
            | TOK_STRING TOK_COLON TOK_STRING
              TOK_LSQBRACKET mat_args TOK_RSQBRACKET    { $$ = make_material_def($1, $3, $5); }
            | TOK_STRING TOK_COLON TOK_STRING
              TOK_LSQBRACKET TOK_RSQBRACKET             { $$ = make_material_def($1, $3, NULL); }
            ;

mat_args    : mat_args TOK_COMMA mat_arg                { $$ = append_mat_args($1, $3); }
            | mat_arg                                   { $$ = make_mat_args($1); }
            ;

mat_arg     : TOK_TEXTURE TOK_EQUALS TOK_FILEPATH       { $$ = make_mat_texture($3); }
            | TOK_MAT_NUM_ARG TOK_EQUALS TOK_POSFLOAT   { $$ = make_mat_num_arg($1, $3); }
            ;

parameter   : TOK_PARAM float                           { $$ = make_float_param($1, $2); }
            | TOK_PARAM TOK_INT                         { $$ = make_int_param($1, $2); }

float       : TOK_POSFLOAT
            | TOK_NEGFLOAT
            ;
