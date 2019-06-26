/*========================================*/

%{

#include "parser.h"
#include <string.h>

/* ====================================================================== */

#define ACCEPT(x) return(x)
#define ACCEPT_LEX(x) \
{ \
	yytext[yyleng] ='\0'; \
	lex = malloc(yyleng + 1); \
  	strcpy(lex, yytext); \
	return(x); \
}
int source_line_no = 1;

/* ====================================================================== */

char *lex;			/* current lexeme of ID or NUM */

/* ====================================================================== */

%}

digit				[0-9]
letter				[a-zA-Z]

%%

"void"				ACCEPT(VOID);
"int"				ACCEPT(INT);


"if"				ACCEPT(IF);
"else"				ACCEPT(ELSE);
"while"				ACCEPT(WHILE);
"return"			ACCEPT(RETURN);
"input"				ACCEPT(INPUT);
"output"			ACCEPT(OUTPUT);


"+"					ACCEPT(PLUS);
"-"					ACCEPT(MINUS);
"*"					ACCEPT(MULTIPLY);

"/"					ACCEPT(DIVIDE);
"<"					ACCEPT(LT);
"<="				ACCEPT(LE);
">"					ACCEPT(GT);
">="				ACCEPT(GE);
"=="				ACCEPT(EQ);
"!="				ACCEPT(NE);

"="					ACCEPT(ASSIGN);
","					ACCEPT(COMMA);
";"					ACCEPT(SEMICOLON);
"("					ACCEPT(LPAR);
")"					ACCEPT(RPAR);

"{"					ACCEPT(LBRACE);
"}"					ACCEPT(RBRACE);
"["					ACCEPT(LBRACKET);
"]"					ACCEPT(RBRACKET);


" "	;
"\t"	;
"\r"	;
"\n"	source_line_no++;


"/*"    comments();
"//"	line_comments();



({letter}|_)({letter}|{digit}|_)*	ACCEPT_LEX(ID);
{digit}{digit}*				ACCEPT_LEX(NUM);

.					ACCEPT(UNDEFINED);

%%

/* ====================================================================== */
void comments(){
	int c;
	for(;;){
		while((c=input())!='*' && c!=EOF){
			if(c=='\n')
				source_line_no++;
			continue;		
		}
		
		if(c=='*')
		{
			while((c=input()) == '*'){
				if(c=='\n')
					source_line_no++;
			}
			if(c=='/')
				break;
		}
	}
}
void line_comments(){
	int c;
	for(;;){
		while((c=input())!='\n' && c!=EOF)
		;
		if(c=='\n'){
			source_line_no++;
			break;
		}
	}
}

/* ====================================================================== */


