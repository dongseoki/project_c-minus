/* ====================================================================== */

%{

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include "symbol.c"

/* ====================================================================== */

#define MAX_NO_CODES	1024	/* maximum number of codes generated */
#define MAX_LINE	256	/* max code line length */
#define NO_TMP_REGIS	27	/* r0 ~ r26 for temporaly registers */
#define REGI_RETURN	27	/* r27 is for return value */

/* ====================================================================== */

extern FILE *yyin;		/* FILE * for input file */
extern char *yytext;		/* current lexeme is stored here */

extern char *lex;		/* lexeme of ID and NUM from scanner */
extern int source_line_no;	/* souce line number */

/* ====================================================================== */

void regi_init(void);
void regi_print(void);
void regi_free(int i);
int regi_new(void);
void backpatch(unsigned int ip1, unsigned int ip2);
void backpatch_funcalls(void);
void print_code(void);
int yyerror(char *message);

/* ====================================================================== */

char *prog_name;		/* program file name from argv[] */
char option_symbol;		/* -s option means print symbol table */

int position;			/* current symbol's kind */

int global_offset;		/* global variable offset */
int local_offset;		/* local variable offset */
int *current_offset;		/* current offset pointer */

int farg_count;			/* no of formal args in function declaration */
int aarg_count;			/* no of actual args in function call */

char *current_fun_name = 0;	/* current function name */

unsigned int ip = 0;		/* instruction pointer */
unsigned int ip_array[100];// ip array!
char * func_name_array[100]; // function name! 
unsigned int ip_array_index = 0;
unsigned int nomorereturn = 0;


char *code[MAX_NO_CODES];	/* generated codes */
char regi_used[NO_TMP_REGIS];	/* 1 if register is used */

/* ====================================================================== */

typedef struct l_type_struct {	/* lex attribute for var and num */
  char *lex;
} l_type;

typedef struct t_type_struct {	/* type attribute for type_specifier */
  unsigned char type;
} t_type;

typedef struct r_type_struct { //속성 <rval> 형의 regi
  unsigned char regi;
} r_type;

typedef struct p_type_struct {
  unsigned int ip;
} p_type;

typedef struct token_type_struct {
  char * token_name;
} token_type;

typedef struct return_type_struct {
  unsigned int return_count;
} return_type;


%}

/* ====================================================================== */

%start program

%union {
  l_type lval;
  t_type tval;
  r_type rval;
  p_type pval;
  token_type tokenval;
  return_type returnval;
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
%type <rval> simple_expression additive_expression term factor call
%type <pval> if_rpar if_else while_lpar while_rpar
%type <tokenval> relop addop mulop
%type <returnval> statement_list statement selection_stmt return_stmt funcall_stmt compound_stmt

%%

/* ====================================================================== */

program :
	{
		struct symbol *symbolp;
		position=GLOBAL;
		current_table=global_table=create_table("_global");
		current_offset=&global_offset;
		*current_offset=0;
		
		fprintf(stdout, "---------- ---------- ---------- ---------- ---------- ----------\n");
		fprintf(stdout, "%-10s %-10s %-10s %-10s %10s %10s\n", "table", "symbol", "kind", "type", "size", "offset");
		fprintf(stdout, "---------- ---------- ---------- ---------- ---------- ----------\n");
		
		// C Stratup Code
		generate("%d: ld gp, 0(0)", ip++);
		generate("%d: st 0, 0(0)", ip++);
		generate("%d: lda fp, -%%d(gp)", ip++);
		generate("%d: lda sp, -%%d(gp)", ip++);
		generate("%d: push fp", ip++);
		generate("%d: lda 0, 2(pc)", ip++);
		generate("%d: push 0", ip++);
		symbolp = add_symbol(global_table, "main", FUNCTIONI, VOID_TYPE, 0, 0);
		generate("%d: ldc pc, %%d", ip++);
		symbolp->ip[0] = ip - 1;
		symbolp->ipc = 1;
		generate("%d: halt",ip++);
	}
	var_declaration_list fun_declaration_list
	{
		print_table(global_table);
		fprintf(stdout, "---------- ---------- ---------- ---------- ---------- ----------\n");
		
		backpatch(2, global_offset);
		backpatch(3, global_offset);
		backpatch_funcalls();
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
	
		fprintf(stdout, " funcation ip :%d\n", ip);
		ip_array[ip_array_index] = ip;
		func_name_array[ip_array_index] = $<lval>2.lex;
		ip_array_index++;
	
	
		struct symbol *symbolp;
		position = ARGUMENT;
		current_table = local_table = create_table($<lval>2.lex);
		
		//add 하기 전에 이 symbol이 처음이 아니라면 중복이라고 할 수 있음.
		if(strcmp($<lval>2.lex, "main")!=0 ){
			if ((symbolp=find_symbol(global_table,$<lval>2.lex)) != NULL)
				error("error 12: redefined function \"%s\"", $<lval>2.lex);
		}
		current_offset = &local_offset;
		*current_offset = 0;
		farg_count = 0;
	}
	LPAR params RPAR
	{
		struct symbol *symbolp;
		symbolp = find_symbol(global_table, $<lval>2.lex);
		/*if(strcmp($<lval>2.lex, "main")!=0 && symbolp == NULL){
			add_symbol(global_table, $<lval>2.lex,FUNCTION, $<tval>1.type, farg_count, ip);
		}*/
		if (strcmp($<lval>2.lex, "main")!=0 && symbolp == NULL) {
			add_symbol(global_table, $<lval>2.lex, FUNCTION, $<tval>1.type, farg_count, ip);
		} else {
			if (symbolp->kind == FUNCTIONI) {
				symbolp->kind = FUNCTION;
				symbolp->type = $<tval>1.type;
				symbolp->offset = ip;
				if (symbolp->size != farg_count)
					error("error 40: wrong no argument function \"%s\"", $<lval>2.lex);
			} else {
				error("error 12: redefined function \"%s\"", $<lval>2.lex);
			}
		}
			position=LOCAL;
	}
		LBRACE local_declarations
	{
		// 현재 ip값을 저장해두자.
		// lex 값도 저장해두자.
		// 그 아이피가 나오면 출력 가능하도록!
		

		generate("%d: lda sp, -%d(sp)", ip++, *current_offset - farg_count);
	}
	statement_list RBRACE
	{
		fprintf(stdout, "return_count1 = %d\n", $<returnval>11.return_count);
		if(!(strcmp($<lval>2.lex, "main")!=0 && $<returnval>11.return_count == 1)){
			generate("%d: ldc %d, 0", ip++, REGI_RETURN);
			generate("%d: lda sp, 0(fp)", ip++);
			generate("%d: ld fp, 0(fp)", ip++);
			generate("%d: ld pc, -1(sp)", ip++);
		}
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
	{
		if($<returnval>1.return_count ==1 ||$<returnval>2.return_count ==1){
			$<returnval>$.return_count = 1;
			fprintf(stdout, "return_count2 = %d\n", $<returnval>$.return_count);
		}
	}
    | empty
;


statement 
    : compound_stmt 
	{
	if($<returnval>1.return_count ==1){
			$<returnval>$.return_count = 1;
			fprintf(stdout, "return_count5 = %d\n", $<returnval>$.return_count);
		}
	}
    | expression_stmt 
    | selection_stmt 
	{
		if($<returnval>1.return_count ==1){
			$<returnval>$.return_count = 1;
			fprintf(stdout, "return_count3 = %d\n", $<returnval>$.return_count);
		}
	}
    | iteration_stmt 
    | funcall_stmt 
	{
		if($<returnval>1.return_count ==1){
			$<returnval>$.return_count = 1;
			fprintf(stdout, "return_count3 = %d\n", $<returnval>$.return_count);
		}
	}
    | return_stmt
	{
		if($<returnval>1.return_count ==1){
			$<returnval>$.return_count = 1;
			fprintf(stdout, "return_count3 = %d\n", $<returnval>$.return_count);
		}
	}
    | input_stmt 
    | output_stmt
;


compound_stmt 
    : LBRACE statement_list RBRACE
	{
		if($<returnval>2.return_count ==1){
			$<returnval>$.return_count = 1;
			fprintf(stdout, "return_count4 = %d\n", $<returnval>$.return_count);
		}
	}
;


expression_stmt 
    : expression SEMICOLON 
	{
		regi_free($<rval>1.regi);
	}
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
		
		if(symbolp->kind == GLOBAL) {
			int offset = symbolp->offset;
			generate("%d: st %d, -%d(gp)", ip++, $<rval>3.regi, offset);
			$<rval>$.regi = $<rval>3.regi;
		} else {
			int offset = symbolp->offset;
			generate("%d: st %d, -%d(fp)", ip++, $<rval>3.regi, offset + 2);
			$<rval>$.regi = $<rval>3.regi;
		}
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
			
		
		if(symbolp->kind == GLOBAL) {
			int regi1 = regi_new();
			int regi2 = regi_new();
			int offset = symbolp->offset;
			
			
			//add regi1, gp, expression 표현값
			//st call의 regi, -(offset)(regi1);
			
			generate("%d: add %d, gp, %d", ip++, regi1, $<rval>3.regi);
			//reg[regi1] = reg[gp]+expression표현값
			
			generate("%d: st %d, -%d(%d)", ip++, $<rval>6.regi, offset, regi1);
			
			$<rval>$.regi = $<rval>6.regi;
			regi_free(regi1);
			regi_free($<rval>3.regi);
		} else {
			// 목표 fp-2-offset + index 의 주소에 expression의 결과를 저장하고자 함!
			int regi1 = regi_new();
			int regi2 = regi_new();
			int offset = symbolp->offset;
			
			
			if (symbolp->type == INT_P_TYPE) {
				generate("%d: ld %d, -%d(fp)", ip++, regi1, offset + 2);
				generate("%d: add %d, %d, %d", ip++, regi2, regi1, $<rval>3.regi);
				//generate("%d: st %d, -%d(%d)", ip++, $<rval>6.regi, offset, regi2);
				generate("%d: st %d, 0(%d)", ip++, $<rval>6.regi, regi2);
			} else {
				generate("%d: add %d, fp, %d", ip++, regi1, $<rval>3.regi);
				generate("%d: st %d, -%d(%d)", ip++, $<rval>6.regi, offset + 2, regi1);
			}
			
			$<rval>$.regi = $<rval>6.regi;
			regi_free(regi1);
			regi_free(regi2);
			regi_free($<rval>3.regi);
		}
	}
	| simple_expression
	{
		$<rval>$.regi = $<rval>1.regi;
	}
;


simple_expression 
    : additive_expression relop additive_expression
	{
		int regi = regi_new();
		generate("%d: %s %d, %d, %d", ip++, $<tokenval>2.token_name, regi, $<rval>1.regi, $<rval>3.regi);
		regi_free($<rval>1.regi);
		regi_free($<rval>3.regi);
		$<rval>$.regi = regi;
	}
    | additive_expression
	{
		$<rval>$.regi = $<rval>1.regi;
	}
;



relop 
    : LT 
	{
		$<tokenval>$.token_name = "lt";
	}
    | LE
	{
		$<tokenval>$.token_name = "le";
	}
    | GT 
	{
		$<tokenval>$.token_name = "gt";
	}
    | GE 
	{
		$<tokenval>$.token_name = "ge";
	}
    | EQ 
	{
		$<tokenval>$.token_name = "eq";
	}
    | NE
	{
		$<tokenval>$.token_name = "ne";
	}
;

additive_expression
	: additive_expression addop term
	{
		int regi = regi_new();
		generate("%d: %s %d, %d, %d", ip++, $<tokenval>2.token_name, regi, $<rval>1.regi, $<rval>3.regi);
		regi_free($<rval>1.regi);
		regi_free($<rval>3.regi);
		$<rval>$.regi = regi;
	}
	| term
	{
		$<rval>$.regi = $<rval>1.regi;
	}
;


addop 
    : PLUS 
	{
		$<tokenval>$.token_name = "add";
	}
    | MINUS
	{
		$<tokenval>$.token_name = "sub";
	}
	
;


term 
    : term mulop factor
	{
		int regi = regi_new();
		generate("%d: %s %d, %d, %d", ip++, $<tokenval>2.token_name, regi, $<rval>1.regi, $<rval>3.regi);
		regi_free($<rval>1.regi);
		regi_free($<rval>3.regi);
		$<rval>$.regi = regi;
	}
    | factor
	{
		$<rval>$.regi = $<rval>1.regi;
	}
;


mulop 
    : MULTIPLY 
	{
		$<tokenval>$.token_name = "mul";
	}
    | DIVIDE
	{
		$<tokenval>$.token_name = "div";
	}
;


//변수 사용
factor
	: LPAR expression RPAR
	{
		$<rval>$.regi = $<rval>2.regi;
	}
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
		if(symbolp->kind == GLOBAL) {
			int regi = regi_new();
			int offset = symbolp->offset;
			if(symbolp->type == INT_ARRAY_TYPE)
				generate("%d: lda %d, -%d(gp)", ip++, regi, offset);
			else
				generate("%d: ld %d, -%d(gp)", ip++, regi, offset);
			$<rval>$.regi = regi;
		} else {
			//...
			//local인 경우.
			int regi = regi_new();
			int offset = symbolp->offset;
			if(symbolp->type == INT_ARRAY_TYPE)
				generate("%d: lda %d, -%d(fp)", ip++, regi, offset+2); // +2 는 내 생각.
			else
				generate("%d: ld %d, -%d(fp)", ip++, regi, offset+2); // 이거도 마찬가지ㅣ
			$<rval>$.regi = regi;
		}
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
			
		if(symbolp->kind == GLOBAL) {
			int regi1 = regi_new();
			int regi2 = regi_new();
			int offset = symbolp->offset;
			generate("%d: add %d, gp, %d", ip++, regi1, $<rval>3.regi);
			//reg[regi1] = reg[gp]+expression표현값
			generate("%d: ld %d, -%d(%d)", ip++, regi2, offset, regi1);
			//reg[regi2] = dMem[-offset+reg[regi1]]
			//reg[regi2] = dMem[reg[gp]-offset+expression표현값]
			regi_free(regi1);
			regi_free($<rval>3.regi);
			$<rval>$.regi = regi2;
		} else {
			int regi1 = regi_new();
			int regi2 = regi_new();
			int offset = symbolp->offset;
			
			
			if (symbolp->type == INT_P_TYPE) {
				generate("%d: ld %d, -%d(fp)", ip++, regi2, offset + 2);
				generate("%d: add %d, %d, %d", ip++, regi1, regi2, $<rval>3.regi);
				//generate("%d: ld %d, -%d(%d)", ip++, regi2, offset, regi1);
				generate("%d: ld %d, 0(%d)", ip++, regi2, regi1);
			} else {
				generate("%d: add %d, fp, %d", ip++, regi1, $<rval>3.regi);
				generate("%d: ld %d, -%d(%d)", ip++, regi2, offset + 2, regi1);
			}
			
			
			/*generate("%d: add %d, fp, %d", ip++, regi1, $<rval>3.regi);
			generate("%d: ld %d, -%d(%d)", ip++, regi2, offset+2, regi1); // -2는 내생각.*/

			// test
			
			regi_free(regi1);
			regi_free($<rval>3.regi);
			$<rval>$.regi = regi2;
		}
	}
    | num 
	{
		int regi = regi_new();
		int num = atoi(lex);
		//int num = atoi($<lval>1.lex);
		generate("%d: ldc %d, %d", ip++, regi, num);
		$<rval>$.regi = regi;
	}
    | PLUS num 
	{
		int regi = regi_new();
		int num = atoi(lex);
		generate("%d: ldc %d, %d", ip++, regi, num);
		$<rval>$.regi = regi;
	}
    | MINUS num
	{
		int regi = regi_new();
		int num = atoi(lex);
		num = num * (-1);
		generate("%d: ldc %d, %d", ip++, regi, num);
		$<rval>$.regi = regi;
	}
;

//selection_stmt 
//    : IF LPAR expression RPAR statement ELSE statement
//;

selection_stmt
	: IF LPAR expression
	{
		generate("%d: jle %d, %%d(pc)", ip++, $<rval>3.regi);
		regi_free($<rval>3.regi);
	}	
	if_rpar statement
	{
		generate("%d: ldc pc, %%d", ip++);
		backpatch($<pval>5.ip - 1, ip - $<pval>5.ip);
	}
	if_else statement
	{
		backpatch($<pval>8.ip - 1, ip); // 2번으로가서  it 문 뒤를 수행하도록 pc를 이동!
		if($<returnval>9.return_count==1 )
			$<returnval>$.return_count=1;
		
	}
;

if_rpar
	: RPAR
	{
		$<pval>$.ip = ip;
	}
;

if_else
	: ELSE
	{
		$<pval>$.ip = ip;
	}
;

//iteration_stmt 
//    : WHILE LPAR expression RPAR statement
//;

iteration_stmt
	: WHILE while_lpar expression
	{
		generate("%d: jle %d, %%d(pc)", ip++, $<rval>3.regi);
		regi_free($<rval>3.regi);
	}
	while_rpar statement
	{
		generate("%d: ldc pc, %d", ip++, $<pval>2.ip);
		backpatch($<pval>5.ip - 1, ip - $<pval>5.ip); // 탈출 하기 위함!
	}
;

while_lpar
	: LPAR
	{
		$<pval>$.ip = ip;
	}
;

while_rpar
	: RPAR
	{
		$<pval>$.ip = ip;
	}
;


funcall_stmt 
    : var ASSIGN call 
	{
		char *var = $<lval>1.lex;
		struct symbol *symbolp;
		//... 심볼을 발견 못하면?
		symbolp = lookup_symbol(var);
		if(symbolp == NULL)
			error("error 20: undefined variable \"%s\"", $<lval>1.lex);
		if (symbolp->kind == 3 || symbolp->kind == 4)
			error("error 30: type error variable \"%s\"", $<lval>1.lex);

		if(symbolp->kind == GLOBAL) {
			int offset = symbolp->offset;
			generate("%d: st %d, -%d(gp)", ip++, $<rval>3.regi, offset);
			regi_free($<rval>3.regi);
		} else {
			int offset = symbolp->offset;
			generate("%d: st %d, -%d(fp)", ip++, $<rval>3.regi, offset + 2);
			regi_free($<rval>3.regi);
		}
	}
    | var LBRACKET expression RBRACKET ASSIGN call 
	{
		char *var = $<lval>2.lex;
		struct symbol *symbolp;
		symbolp = lookup_symbol(var);
		
		if(symbolp == NULL) //...
			error("error 21: undefined array \"%s\"", $<lval>1.lex);
		if (symbolp->kind == 3 || symbolp->kind == 4)
			error("error 31: type error array \"%s\"", $<lval>1.lex);
		
		if (symbolp->kind == GLOBAL) {
			int regi1 = regi_new();
			int offset = symbolp->offset;
			
			generate("%d: add %d, gp, %d", ip++, regi1, $<rval>3.regi);
			//reg[regi1] = reg[gp]+expression표현값
			
			generate("%d: st %d, -%d(%d)", ip++, $<rval>6.regi, offset, regi1);
			
			// st call의regi , -offset(regi1)
			//dMem[-offset + reg[regi1]] = call의regi
			//dMem[reg[gp]-offset+expression표현값] = call의 regi
			
			regi_free(regi1);
			regi_free($<rval>6.regi);
		} else {
			// 목표 fp-2-offset + index 의 주소에 call의 결과를 저장하고자 함!
			
			int regi1 = regi_new();
			int offset = symbolp->offset;
			
			//add regi1, fp, expression 표현값
			//st call의 regi, -(offset+2)(regi1);
			
			generate("%d: add %d, fp, %d", ip++, regi1, $<rval>3.regi);
			generate("%d: st %d, -%d(%d)", ip++, $<rval>6.regi, offset + 2, regi1);
			regi_free(regi1);
			regi_free($<rval>6.regi);
		}
	}
    | call
	{
		regi_free($<rval>1.regi);
	}
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
		generate("%d: lda sp, -2(sp)", ip++);
	}
	LPAR args RPAR
	{
		int regi;
		struct symbol *symbolp;
		symbolp = lookup_symbol($<lval>1.lex);
		
		//fprintf(stdout, "kind/type/ = %d %d\n", symbolp->kind, symbolp->type);
		//fprintf(stdout, "size/aarg_count = %d %d\n", symbolp->size, aarg_count);
		
		if(symbolp->size != aarg_count)
			error("error 40: wrong no argument function \"%s\"", $<lval>1.lex);
			
		generate("%d: st fp, -%d(fp)", ip++, *current_offset + 2);
		generate("%d: lda fp, -%d(fp)", ip++, *current_offset + 2);
		regi = regi_new();
		generate("%d: lda %d, 2(pc)", ip++, regi);
		generate("%d: st %d, -1(fp)", ip++, regi);
		regi_free(regi);
		
		if (symbolp->offset != 0) {
			generate("%d: ldc pc, %d", ip++, symbolp->offset);
		} else {
			generate("%d: ldc pc, %%d", ip++);
			symbolp->ip[symbolp->ipc] = ip - 1;
			symbolp->ipc = symbolp->ipc + 1;
			//... 교수님 코드 참조.	
		}
		regi = regi_new();
		generate("%d: lda %d, 0(%d)", ip++, regi, REGI_RETURN);
		$<rval>$.regi = regi;
	}
;

args 
    : arg_list
    | empty
;

arg_list 
    : arg_list COMMA expression
    {
        aarg_count++;
		generate("%d: push %d", ip++, $<rval>3.regi);
		regi_free($<rval>3.regi);
    } 
    | expression
	{
		aarg_count++;
		generate("%d: push %d", ip++, $<rval>1.regi);
		regi_free($<rval>1.regi);
	}
;

return_stmt
	: RETURN SEMICOLON
	{
		generate("%d: ldc %d, 0", ip++, REGI_RETURN);
		generate("%d: lda sp, 0(fp)", ip++);
		generate("%d: ld fp, 0(fp)", ip++);
		generate("%d: ld pc, -1(sp)", ip++);
		$<returnval>$.return_count = 1;
	}
	| RETURN expression SEMICOLON
	{
		
		generate("%d: lda %d, 0(%d)", ip++, REGI_RETURN, $<rval>2.regi);
		generate("%d: lda sp, 0(fp)", ip++);
		generate("%d: ld fp, 0(fp)", ip++);
		generate("%d: ld pc, -1(sp)", ip++);
		$<returnval>$.return_count = 1;
		regi_free($<rval>2.regi);
	}
;

input_stmt 
    : INPUT var SEMICOLON 
	{
		char *var = $<lval>2.lex;
		struct symbol *symbolp;
		symbolp = lookup_symbol(var);
		
		//... input 에서 lookup_symbol 했는데 안나오면?
		if(symbolp == NULL)
			error("error 20: undefined variable \"%s\"", $<lval>1.lex);
		
		if (symbolp->kind == 3 || symbolp->kind == 4)
			error("error 30: type error variable \"%s\"", $<lval>1.lex);

		if(symbolp->kind == GLOBAL) {
			int regi = regi_new();
			int offset = symbolp->offset;
			generate("%d: in %d", ip++, regi);
			generate("%d: st %d, -%d(gp)", ip++, regi, offset);
			regi_free(regi);
		} else {
			//...
			int regi = regi_new();
			int offset = symbolp->offset;
			generate("%d: in %d", ip++, regi);
			generate("%d: st %d, -%d(fp)", ip++, regi, offset+2);
			regi_free(regi);
		}
	}
    | INPUT var LBRACKET expression RBRACKET SEMICOLON
	{
		char *var = $<lval>2.lex;
		struct symbol *symbolp;
		symbolp = lookup_symbol(var);
		//... input 에서 lookup_symbol 했는데 안나오면?
		if(symbolp == NULL) //...
			error("error 21: undefined array \"%s\"", $<lval>1.lex);
		if (symbolp->kind == 3 || symbolp->kind == 4)
			error("error 31: type error array \"%s\"", $<lval>1.lex);
		
		if(symbolp->kind == GLOBAL) {
			int regi = regi_new();
			int regi2 = regi_new();
			int offset = symbolp->offset;
			generate("%d: in %d", ip++, regi);
			
			//index 계산하자.
			generate("%d: add %d, gp, %d", ip++, regi2, $<rval>4.regi);
			
			// 계산 결과를 regi 에 저장.
			generate("%d: st %d, -%d(%d)", ip++, regi ,offset, regi2);
			regi_free(regi);
			regi_free(regi2);
			regi_free($<rval>4.regi);//190616새롭게 추가
		} else {
			int regi = regi_new();
			int regi2 = regi_new();
			int offset = symbolp->offset;
			
			
			//index 계산하자.
			fprintf(stdout, "what is problem %d\n", $<rval>4.regi);
			generate("%d: in %d", ip++, regi);
			generate("%d: add %d, fp, %d", ip++, regi2, $<rval>4.regi);
			// 계산 결과를 regi 에 저장.
			generate("%d: st %d, -%d(%d)", ip++, regi ,offset + 2, regi2);
			regi_free(regi);
			regi_free(regi2);
			regi_free($<rval>4.regi);//190616새롭게 추가
		}
	}
;

output_stmt 
    : OUTPUT expression SEMICOLON
	{
		generate("%d: out %d", ip++, $<rval>2.regi);
		regi_free($<rval>2.regi);
	}
;

empty 
    :
;

%%

/* ====================================================================== */

void regi_init(void)
{
  int i;

  for (i = 0; i < NO_TMP_REGIS; i++)
    regi_used[i] = 0;
}

/* ====================================================================== */

void regi_free(int i)
{
  regi_used[i] = 0;
}

/* ====================================================================== */

int regi_new(void)
{
  int i;

  for (i = 0; i < NO_TMP_REGIS; i++) {
    if (regi_used[i] == 0) {
      regi_used[i] = 1;
      return i;
    }
  }
  error("error 50: all registers are used!");
}

/* ====================================================================== */

int generate(char *fmt, int i1, int i2, int i3, int i4, int i5)
{
  char tmp[MAX_LINE];
  char *p;

  sprintf(tmp, fmt, i1, i2, i3, i4, i5);
  p = (char *) malloc(strlen(tmp) + 1);
  strcpy(p, tmp);
  code[ip - 1] = p;
}

/* ====================================================================== */

void backpatch(unsigned int ip1, unsigned int ip2)
{
  char tmp[MAX_LINE];
  char *p;

  sprintf(tmp, code[ip1], ip2);
  p = (char *) malloc(strlen(tmp) + 1);
  strcpy(p, tmp);
  free(code[ip1]);
  code[ip1] = p;
}

/* ====================================================================== */

void backpatch_funcalls(void)
{
  int i, j;
  struct symbol *symbolp;
  
  for (i = 0; i < HASH_SIZE; i++)
    for (symbolp = global_table->hash[i]; symbolp != NULL;
	 symbolp = symbolp->next)
      for (j = 0; j < symbolp->ipc; j++)
	backpatch(symbolp->ip[j], symbolp->offset);
}

/* ====================================================================== */

unsigned int find_string_convert_to_num(const char * string){
	int i=0;
	char numstring[10];
	for(i=0;i<100;i++){
		if('0'<=string[i] && string[i] <='9')
			numstring[i] = string[i];
		else{
			numstring[i] = '\0';
			break;
		}
	}
	int num = atoi(numstring);
	//fprintf(stdout, "   ip 값 :%d\n", num);
	return num;
}


void print_code(void)
{
  int i;
  char file[MAX_LINE];
  FILE *fp;
  
  i = strlen(prog_name);
  if ((i > 2) && (prog_name[i - 2] == '.') && (prog_name[i - 1] == 'c'))
    prog_name[i - 2] = '\0';
  else if ((i > 2) && (prog_name[i - 2] == '.') && (prog_name[i - 1] == 'C'))
    prog_name[i - 2] = '\0';

  sprintf(file, "%s.tm", prog_name);
  if ((fp = fopen(file, "w")) == NULL) {
    fprintf(stderr, "%s: %s\n", file, strerror(errno));
    exit(1);
  }
  
  fprintf(fp, "// ====================\n");
  fprintf(fp, "// c startup\n");
  fprintf(fp, "// ====================\n");
  unsigned int ip_array_index = 0;
  for (i = 0; i < ip; i++){
		if(find_string_convert_to_num(code[i]) ==ip_array[ip_array_index])
		{
			fprintf(fp, "// ====================\n");
			fprintf(fp, "// %s()\n", func_name_array[ip_array_index]);
			fprintf(fp, "// ====================\n");
			ip_array_index++;
		}
		
		fprintf(fp, "%s\n", code[i]);
		/*if(strcmp(code[i], "8: halt")==0){
			fprintf(fp, "// ====================\n");
			fprintf(fp, "// main()\n");
			fprintf(fp, "// ====================\n");
		}*/
	}
  fprintf(fp, "// ====================\n");
  fclose(fp);
}

/* ====================================================================== */

int yyerror(char *message)
{
  if (option_symbol == 1) {
    print_table(current_table);
    fprintf(stdout,
	    "---------- ---------- ---------- ---------- ---------- ----------\n");
    print_table(global_table);
    fprintf(stdout,
	    "---------- ---------- ---------- ---------- ---------- ----------\n");
  }
  fprintf(stderr, "line %d: %s at \"%s\"\n", source_line_no, message,
	  yytext);
}

/* ====================================================================== */

int error(char *fmt, char *s1, char *s2, char *s3, char *s4)
{
  if (option_symbol == 1) {
    print_table(current_table);
    fprintf(stdout,
	    "---------- ---------- ---------- ---------- ---------- ----------\n");
    print_table(global_table);
    fprintf(stdout,
	    "---------- ---------- ---------- ---------- ---------- ----------\n");
  }
  fprintf(stdout, "line %d: ", source_line_no);
  fprintf(stdout, fmt, s1, s2, s3, s4);
  fprintf(stdout, "\n");
  fflush(stdout);
  exit(-1);
}

/* ====================================================================== */

int main(int argc, char *argv[])
{
  if (argc == 2) {
    option_symbol = 0;
    prog_name = argv[1];
  } else if (argc == 3) {
    if (strcmp(argv[1], "-s") != 0) {
      fprintf(stderr, "usage: cm [-s] file\n");
      exit(1);
    }
    option_symbol = 1;
    prog_name = argv[2];
  } else {
    fprintf(stderr, "usage: cm [-s] file\n");
    exit(1);
  }

  yyin = fopen(prog_name, "r");
  if (yyin == NULL) {
    fprintf(stderr, "%s: %s\n", prog_name, strerror(errno));
    exit(1);
  }
  yyparse();
  
  print_code();

  return 0;
}

/* ====================================================================== */
