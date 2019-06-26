/* ====================================================================== */

%{

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include "symbol.c"

/* ====================================================================== */

extern FILE *yyin;		/* FILE * for input file */
extern char *yytext;		/* current lexeme is stored here */

extern char *lex;		/* lexeme of ID and NUM from scanner */
extern int source_line_no;	/* souce line number */

/* ====================================================================== */

int position;			/* current symbol's kind */

int global_offset;		/* global variable offset */
int local_offset;		/* local variable offset */
int *current_offset;		/* current offset pointer */

int farg_count;			/* no of formal args in function declaration */
int aarg_count;			/* no of actual args in function call */

unsigned int ip = 0;		/* instruction pointer */

/* ====================================================================== */

typedef struct l_type_struct {	/* lex attribute for var and num */
  char *lex;
} l_type;

typedef struct t_type_struct {	/* type attribute for type_specifier */
  unsigned char type;
} t_type;

%}

/* ====================================================================== */

%start program

%union {
  l_type lval;
  t_type tval;
}

%token VOID INT
%token IF ELSE WHILE RETURN
%token INPUT OUTPUT
%token PLUS MINUS MULTIPLY DIVIDE
%token LT LE GT GE EQ NE
%token ASSIGN
%token SEMICOLON COMMA
%token LPAR RPAR LBRACKET RBRACKET LBRACE RBRACE
%token ID NUM
%token UNDEFINED

%type <lval> var num
%type <tval> type_specifier

%%

/* ====================================================================== */

program :
	{
		position=GLOBAL;
		current_table=global_table=create_table("_global");
		current_offset=&global_offset;
		*current_offset=0;
		
		fprintf(stdout, "---------- ---------- ---------- ---------- ---------- ----------\n");
		fprintf(stdout, "%-10s %-10s %-10s %-10s %10s %10s\n", "table", "symbol", "kind", "type", "size", "offset");
		fprintf(stdout, "---------- ---------- ---------- ---------- ---------- ----------\n");
	}
	var_declaration_list fun_declaration_list
	{
		print_table(global_table);
		fprintf(stdout, "---------- ---------- ---------- ---------- ---------- ----------\n");
	}
;

var_declaration_list
  : var_declaration_list var_declaration
  | empty
;

fun_declaration_list 
    : fun_declaration_list fun_declaration 
    | fun_declaration
;


var_declaration
	: type_specifier var SEMICOLON
	{
		if ($<tval>1.type == 3)
			error("error 00: wrong void variable \"%s\"", $<lval>2.lex);
		if (find_symbol(current_table, $<lval>2.lex) != NULL)
			error("error 10: redefined variable \"%s\"", $<lval>2.lex);
		add_symbol(current_table, $<lval>2.lex, position, $<tval>1.type, 1, *current_offset);
		*current_offset = *current_offset + 1;
	}
	| type_specifier var LBRACKET num RBRACKET SEMICOLON
	{
		int n = atoi($<lval>4.lex);
		
		// type 이 3이다. 이것은 VOID 라는 의미다.
		// 하지만 변수의 타입으로 우리는 VOID를 사용할 수 없다.
		if ($<tval>1.type == 3)
			error("error 01: wrong void array \"%s\"", $<lval>2.lex);
			
		// 이것은 배열을 선언 하는 부분이다.
		// global과 local table 을 찾아봤는데 이미 심볼이 있다면? 재정의 된 배열인 것이다.
		//오류 결과를 출력해야 할 것이다.
		if (find_symbol(current_table, $<lval>2.lex) != NULL)
			error("error 11: redefined array \"%s\"", $<lval>2.lex);
		
		add_symbol(current_table, $<lval>2.lex, position, INT_ARRAY_TYPE, n, *current_offset + n - 1);
		*current_offset = *current_offset + n;
	}
;


//type -> int type.dtype = integer.
type_specifier 
    : INT 
	{
		$<tval>$.type=INT_TYPE; 
		// type을 int형으로 저장하는 부분. 
	}
    | VOID
	{
		$<tval>$.type=VOID_TYPE;
		// type을 void형으로 저장하는 부분.
	}
;

var 
    : ID
	{
		$<lval>$.lex = lex;
	}
;

num 
    : NUM
	{
		$<lval>$.lex = lex;
	}
;

fun_declaration
	: type_specifier var
	{		
		position = ARGUMENT;
		current_table = local_table = create_table($<lval>2.lex);
		
		//add 하기 전에 이 symbol이 처음이 아니라면 중복이라고 할 수 있음.
		if (find_symbol(global_table,$<lval>2.lex) != NULL)
			error("error 12: redefined function \"%s\"", $<lval>2.lex);
		current_offset = &local_offset;
		*current_offset = 0;
		farg_count = 0;
	}
	LPAR params RPAR
	{
		add_symbol(global_table, $<lval>2.lex,FUNCTION, $<tval>1.type, farg_count, ip);
		position=LOCAL;
	}
		LBRACE local_declarations statement_list RBRACE
	{
		print_table(current_table);
		fprintf(stdout, "---------- ---------- ---------- ---------- ---------- ----------\n");
		// 이부분은
		//main 테이블 ...
		//----
		//main 테이블 이런 식으로 나오게 한다.
	}
;

params 
    : param_list 
    | VOID
;


param_list
	: param_list COMMA param
	{
		farg_count++;
	}
	| param
	{
		farg_count = 1;
	}
;



param
: type_specifier var
	{
		// param 은 인자란 뜻이다. 여기서 type ==3 이면 즉 자료형이 void 라는 것은
		// 불가능하다. 왜냐하면 인자에 void 로 선언할 수 없기 때문이다.
		if ($<tval>1.type == 3)
			error("error 02: wrong void argument \"%s\"", $<lval>2.lex);
		if(find_symbol(current_table, $<lval>2.lex)!=NULL)
			error("error 13: redefined argument \"%s\"", $<lval>2.lex);
		add_symbol(current_table, $<lval>2.lex, position, $<tval>1.type,
		1, *current_offset);
		*current_offset = *current_offset + 1;
	}
	| type_specifier var LBRACKET RBRACKET
	{
		// 또한 인자로써 void형인 배열인자를 넣을 수 없다.
		if ($<tval>1.type == 3)
			error("error 03: wrong void array argument \"%s\"", $<lval>2.lex);
		//add 하기 전에는 항상 미리 있나 확인 해야 한다. 미리 있으면 에러를 출력하자!
		// 지금 이부분은 인자에서 배열을 선언하는 부분이다.
		// lookup_symbol 썼는데 이미 있다면 에러를 발생시키자!
		if (find_symbol(current_table,$<lval>2.lex) != NULL)
			error("error 14: redefined array argument \"%s\"", $<lval>2.lex);
		add_symbol(current_table, $<lval>2.lex, position, INT_P_TYPE,
		1, *current_offset);
		*current_offset = *current_offset + 1;
	}
;


local_declarations 
    : local_declarations var_declaration 
    | empty
;


statement_list 
    : statement_list statement 
    | empty
;


statement 
    : compound_stmt 
    | expression_stmt 
    | selection_stmt 
    | iteration_stmt 
    | funcall_stmt 
    | return_stmt 
    | input_stmt 
    | output_stmt
;


compound_stmt 
    : LBRACE statement_list RBRACE
;


expression_stmt 
    : expression SEMICOLON 
    | SEMICOLON
;


expression
	: var ASSIGN expression
	{
		char *var = $<lval>1.lex;
		struct symbol *symbolp;
		symbolp = lookup_symbol(var);
		if(symbolp == NULL)
			error("error 20: undefined variable \"%s\"", $<lval>1.lex);
		// x = 2; 이렇게 되어 있는데 알고 보니
		//x 가 함수면 변수 타입 에러를 발생시킨다! 변수 타입이 아님 오류
		if (symbolp->kind == 3 || symbolp->kind == 4)
			error("error 30: type error variable \"%s\"", $<lval>1.lex);
		//...
	}
	| var LBRACKET expression RBRACKET ASSIGN expression
	{
		char *var = $<lval>1.lex;
		struct symbol *symbolp;
		symbolp = lookup_symbol(var);
		if(symbolp == NULL) //...
			error("error 21: undefined array \"%s\"", $<lval>1.lex);
		if (symbolp->kind == 3 || symbolp->kind == 4)
			error("error 31: type error array \"%s\"", $<lval>1.lex);
	}
	| simple_expression
;


simple_expression 
    : additive_expression relop additive_expression 
    | additive_expression
;



relop 
    : LT 
    | LE 
    | GT 
    | GE 
    | EQ 
    | NE
;


additive_expression 
    : additive_expression addop term 
    | term
;


addop 
    : PLUS 
    | MINUS
;


term 
    : term mulop factor 
    | factor
;


mulop 
    : MULTIPLY 
    | DIVIDE
;


//변수 사용
factor
	: LPAR expression RPAR
	| var
	{
	//factor 는 요인, 인자라는 뜻이다.
	// 만약 앞에서 선언된것이 없는데
	//  l1 = 4 * l4; 이런식으로 써버렸다면
	// 오류를 내야 할 것이다.! l1은 선언되지 않은 변수라고!
		char *var = $<lval>1.lex;
		struct symbol *symbolp;
		symbolp = lookup_symbol(var);
		if(symbolp == NULL)
			error("error 20: undefined variable \"%s\"", $<lval>1.lex);
		//...
	}
	| var LBRACKET expression RBRACKET
	{
		char *var = $<lval>1.lex;
		struct symbol *symbolp;
		symbolp = lookup_symbol(var);
		// 이번에는 앞에서 선언된 적없던 배열을 가리키는 변수가
		//  l4_a[5] = 4 * l1;
		//나타난 것이다. 에러를 출력해야 한다!
		if(symbolp == NULL)
			error("error 21: undefined array \"%s\"", $<lval>1.lex);
	}
    | num 
    | PLUS num 
    | MINUS num
;

selection_stmt 
    : IF LPAR expression RPAR statement ELSE statement
;

iteration_stmt 
    : WHILE LPAR expression RPAR statement
;

funcall_stmt 
    : var ASSIGN call 
    | var LBRACKET expression RBRACKET ASSIGN call 
    | call
;


call
	: var
	{
		struct symbol *symbolp;
		symbolp = lookup_symbol($<lval>1.lex);
		if(symbolp == NULL)
			error("error 22: undefined function call \"%s\"", $<lval>1.lex);
		//int fun; 이렇게 변수로 선언되었는데
		//fun(10,20) 처럼 함수로 선언되버린 것이다!
		// 즉 함수 타입 오류 !
		//fprintf(stdout, "kind/type = %d %d\n", symbolp->kind, symbolp->type);
		if (symbolp->kind != 3 && symbolp->kind != 4)
			error("error 32: type error function \"%s\"", $<lval>1.lex);
		aarg_count = 0;
	}
	LPAR args RPAR
	{
		struct symbol *symbolp;
		symbolp = lookup_symbol($<lval>1.lex);
		//fprintf(stdout, "kind/type/ = %d %d\n", symbolp->kind, symbolp->type);
		//fprintf(stdout, "size/aarg_count = %d %d\n", symbolp->size, aarg_count);
		if(symbolp->size != aarg_count)
			error("error 40: wrong no argument function \"%s\"", $<lval>1.lex);
	}
;

args 
    : arg_list
    {
	aarg_count +=1;
    } 
    | empty
;

arg_list 
    : arg_list COMMA expression
    {
        aarg_count +=1;
    } 
    | expression
;

return_stmt 
    : RETURN SEMICOLON 
    | RETURN expression SEMICOLON
;

input_stmt 
    : INPUT var SEMICOLON 
    | INPUT var LBRACKET expression RBRACKET SEMICOLON
;

output_stmt 
    : OUTPUT expression SEMICOLON
;

empty 
    :
;

%%

/* ====================================================================== */

int yyerror(char *message)
{
  print_table(current_table);
  fprintf(stdout,
	"---------- ---------- ---------- ---------- ---------- ----------\n");
  print_table(global_table);
  fprintf(stdout,
	"---------- ---------- ---------- ---------- ---------- ----------\n");
  fprintf(stderr, "line %d: %s at \"%s\"\n", source_line_no, message,
	  yytext);
}

/* ====================================================================== */

int error(char *fmt, char *s1, char *s2, char *s3, char *s4)
{
  print_table(current_table);
  fprintf(stdout,
	"---------- ---------- ---------- ---------- ---------- ----------\n");
  print_table(global_table);
  fprintf(stdout,
	"---------- ---------- ---------- ---------- ---------- ----------\n");
  fprintf(stdout, "line %d: ", source_line_no);
  fprintf(stdout, fmt, s1, s2, s3, s4);
  fprintf(stdout, "\n");
  fflush(stdout);
  exit(-1);
}

/* ====================================================================== */

int main(int argc, char *argv[])
{
  if(argc != 2) {
    fprintf(stderr, "usage: symbol file\n");
    exit(1);
  }
  yyin = fopen(argv[1], "r");
  if(yyin == NULL) {
    fprintf(stderr, "%s: %s\n", argv[1], strerror(errno));
    exit(1);
  }
  yyparse();

  return 0;
}

/* ====================================================================== */


