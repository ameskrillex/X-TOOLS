#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
int main(){
 HMODULE dll=LoadLibraryW(L"XToolsBridge.asi");if(!dll)return 10;
 auto start=(int(__cdecl*)())GetProcAddress(dll,"XTBridgeStart");
 auto status=(int(__cdecl*)())GetProcAddress(dll,"XTBridgeStatus");
 auto stop=(int(__cdecl*)())GetProcAddress(dll,"XTBridgeStop");
 if(!start||!stop||!status)return 11;
 if(start()<0)return 12;
 for(int n=0;n<100&&status()==1;n++)Sleep(20);
 printf("%d\n",status());fflush(stdout);
 if(status()==2&&start()!=2)return 14;
 getchar();int result=stop();printf("stopped=%d status=%d\n",result,status());
 return result?0:13;
}
