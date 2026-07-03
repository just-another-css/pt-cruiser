CC      = gcc
CFLAGS  = -g -Wall -I../include
LDFLAGS = -g
BUILD   = $(LIB)
OBJS    = parser_api.o parser.o lex.yy.o
LFLAGS  = -l
YFLAGS  = -vd
ARFLAGS = rcs
LIB		= libparsing.a
LIBOBJS = parser_api.o parser.o lex.yy.o

all: $(BUILD)

clean:
	/bin/rm -f $(BUILD) $(OBJS) core a.out .nfs* lex.yy.c

$(LIB): $(LIBOBJS)
	$(AR) $(ARFLAGS) $(LIB) $(LIBOBJS)

lex.yy.c: lexer.l
	flex $(LFLAGS) -o lex.yy.c lexer.l

parser.c parser.h:	parser.y
	yacc $(YFLAGS) -o parser.c parser.y

lex.yy.o: parser.h parser_api.h

lexer_test.o: lexsupport.h
lexsupport.o: lexsupport.h
parser.o:	  parser.h parser_api.h
parser_api.o: parser_api.h
