#include <stdio.h>
#include <stdlib.h>
void printLAorder(int str_length,int argc ,char * argv[]){
        //0(폴더이름) 1..부터.....
        int i=0;
        int index = 0;
        int length_alpha= argc -2;// 알파벳에 담긴 심볼의 개수를 나타낸다.
        int xMethod[str_length]; // 출력하고자 하는 문자열의 길이에 맞게 진법개념의 배열 선언.
        for(i=0;i<str_length ;i++)
                xMethod[i] = 0;
        if(str_length ==0){
                printf("\n");
                return;
        }
        while(1){
                index = str_length-1;
				// xMethod 배열이 [_ , _ , 1] 일때 1이 표시된 위치를 가리키도록 한다.
                while(1){
                        if(xMethod[index]==length_alpha){
                                if(index==0) // 종료조건. case.. gen 0 1 2 3.. xMethod :3XX.
                                        return;
                                xMethod[index]=0; // 그자리수를 초기화하고
                                index--; // 자리수를 올리고 ex) 1의자리->10의자리!
                                xMethod[index]++;// 그 자리수를 증가시킴.=>while반복
                        }
                        else
                                break;

                }
                index = str_length-1;
                for(int i=0;i<str_length;i++)
                        printf("%s", argv[xMethod[i]+1]); 
				// 각 배열에 담진 숫자를 인덱스로 활용하여 각각의 스트링을 표현하였습니다.
				//ex) xMethod 배열의 내용[1,2,1] => argv[1+1] argv[2+1] argv[1+1] =>yzy
                printf("\n");
                xMethod[index]++;
				// 다음값을 출력하기 위해 xMethod 배열의 마지막index에 해당하는 값을 1증가시킨다.
				// ex) xMethod 배열이 [_ , _ , 1] => [_ , _ , 2]
        }

        return ;

}

int main(int argc, char * argv[]){
        int i=0;
        int final_length= atoi(argv[argc-1]);
		// atoi 를 이용, 명줄에서 받은 마지막 숫자를 최종 문자열의 길이로 받는다.
        for(i=0;i<=final_length;i++){
                printLAorder(i, argc,argv);
				// i는 출력하고자 하는 스트링의 길이, argc, argv는 그대로 활용.
        }
        return 0;
}
