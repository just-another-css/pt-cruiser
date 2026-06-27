CC      = gcc
CFLAGS  = -g -Wall -I../include
LDFLAGS = -g
BUILD   = parser_test $(LIB)
OBJS    = parser_api.o parser.o lex.yy.o parser_test.o
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

lexer_test: $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) $(LDFLAGS) -o lexer_test $(LDLIBS)

parser_test: $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) $(LDFLAGS) -o parser_test

lex.yy.c: lexer.l
	flex $(LFLAGS) -o lex.yy.c lexer.l

parser.c parser.h:	parser.y
	yacc $(YFLAGS) -o parser.c parser.y

lex.yy.o: parser.h parser_api.h

lexer_test.o: lexsupport.h
lexsupport.o: lexsupport.h
parser.o:	  parser.h parser_api.h
parser_api.o: parser_api.h ../include/materials.h
