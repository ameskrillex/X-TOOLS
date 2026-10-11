#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <windows.h>
#include <ws2tcpip.h>
#include <atomic>
#include <filesystem>
#include <fstream>
#include <string>
#include <ctime>
#include "vendor/json.hpp"
using J=nlohmann::json;
namespace fs=std::filesystem;
static HMODULE module;
static HANDLE threadHandle=nullptr;
static SRWLOCK lifecycle=SRWLOCK_INIT;
static std::atomic<int> status{0}; // 0 stopped, 1 starting, 2 listening, negative error
static std::atomic<bool> stopping{false};
static fs::path folder;
static std::string token;
static int port=18766;
static double now(){return static_cast<double>(time(nullptr));}
static std::string readFile(const fs::path& p,size_t limit=300000){
 std::ifstream f(p,std::ios::binary);if(!f)return {};
 std::string s(limit+1,'\0');f.read(s.data(),s.size());s.resize(static_cast<size_t>(f.gcount()));
 if(s.size()>limit)throw std::runtime_error("file limit");return s;
}
static J parse(const std::string& s){
 return J::parse(s,[](int depth,J::parse_event_t,J&){if(depth>32)throw std::runtime_error("depth");return true;});
}
static J readJson(const char* name){try{return parse(readFile(folder/name));}catch(...){return nullptr;}}
static void writeFile(const char* name,const std::string& s){
 auto path=folder/name,tmp=folder/(std::string(name)+".native.tmp");
 {std::ofstream f(tmp,std::ios::binary|std::ios::trunc);f.write(s.data(),s.size());if(!f)throw std::runtime_error("write");}
 if(!MoveFileExW(tmp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING))throw std::runtime_error("replace");
}
static bool fresh(const J& j){return j.is_object()&&j.contains("expires")&&j["expires"].is_number()&&j["expires"].get<double>()>=now();}
static bool same(const J& a,const J& b,const char* k){return a.contains(k)&&b.contains(k)&&a[k]==b[k];}
static void reply(SOCKET s,int code,const std::string& body={}){
 std::string out="HTTP/1.1 "+std::to_string(code)+" Result\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: "+std::to_string(body.size())+"\r\n\r\n"+body;
 for(size_t n=0;n<out.size();){int sent=send(s,out.data()+n,static_cast<int>(out.size()-n),0);if(sent<=0)break;n+=sent;}
}
static bool dialogSafe(const J& d){
 if(!d.is_object()||!d.contains("DIALOG_TYPE")||!d["DIALOG_TYPE"].is_number_integer())return false;
 if(!d.value("DIALOG_HEADER",J()).is_string()||!d.value("DIALOG_TEXT",J()).is_string())return false;
 auto header=d["DIALOG_HEADER"].get<std::string>();
 for(char& c:header)if(static_cast<unsigned char>(c)<128)c=static_cast<char>(tolower(c));
 for(auto word:{"password","login","auth","Парол","парол","Авториза","авториза","Регистрац","регистрац","Код","код"})if(header.find(word)!=std::string::npos)return false;
 int t=d["DIALOG_TYPE"];return t==0||t==2||t==4||t==5;
}
static J cleanDialog(const J& d){
 if(!dialogSafe(d))return nullptr;
 J result=J::object();for(auto k:{"DIALOG_TYPE","DIALOG_HEADER","DIALOG_TEXT"})result[k]=d[k];
 result["DIALOG_KEYS"]=J::array();if(d.value("DIALOG_KEYS",J()).is_array())for(const auto& key:d["DIALOG_KEYS"])if(key.is_string()&&result["DIALOG_KEYS"].size()<2)result["DIALOG_KEYS"].push_back(key);return result;
}
static void handle(SOCKET socket,J& credential,std::string& lastCapture){
 DWORD timeout=1500;setsockopt(socket,SOL_SOCKET,SO_RCVTIMEO,(char*)&timeout,sizeof(timeout));setsockopt(socket,SOL_SOCKET,SO_SNDTIMEO,(char*)&timeout,sizeof(timeout));
 auto deadline=GetTickCount64()+2500;
 std::string raw;char buf[4096];size_t split;
 while((split=raw.find("\r\n\r\n"))==std::string::npos){
  if(raw.size()>8192||GetTickCount64()>deadline)throw std::runtime_error("header");
  int n=recv(socket,buf,sizeof(buf),0);if(n<=0)throw std::runtime_error("receive");raw.append(buf,n);
 }
 if(split>8192)throw std::runtime_error("header");
 auto first=raw.find("\r\n");auto line=raw.substr(0,first);
 auto matches=[&](const std::string& path){return line=="POST "+path+" HTTP/1.1"||line=="POST "+path+" HTTP/1.0";};
 bool cred=matches("/"+token+"/credential");
 if(!cred&&!matches("/"+token)){reply(socket,404);return;}
 size_t length=0;bool found=false;
 for(size_t pos=first+2;pos<split;){auto end=raw.find("\r\n",pos);auto h=raw.substr(pos,end-pos);for(char& c:h)c=static_cast<char>(tolower(static_cast<unsigned char>(c)));
  if(h.rfind("transfer-encoding:",0)==0)throw std::runtime_error("encoding");
  if(h.rfind("content-length:",0)==0){if(found)throw std::runtime_error("duplicate");found=true;auto v=h.substr(15);size_t used=0;length=std::stoul(v,&used);if(v.find_first_not_of(" \t",used)!=std::string::npos)throw std::runtime_error("length");}
  pos=end+2;
 }
 if(!found||!length||length>=(cred?4096:300000))throw std::runtime_error("size");
 std::string body=raw.substr(split+4);
 while(body.size()<length){if(GetTickCount64()>deadline)throw std::runtime_error("deadline");int n=recv(socket,buf,static_cast<int>(std::min(sizeof(buf),length-body.size())),0);if(n<=0)throw std::runtime_error("body");body.append(buf,n);}
 if(body.size()!=length)throw std::runtime_error("body length");
 J state=parse(body);if(!state.is_object())throw std::runtime_error("object");
 if(cred){
  if(!state.contains("password")||!state["password"].is_string()||state["password"].get_ref<const std::string&>().empty()||state["password"].get_ref<const std::string&>().size()>=1024||!fresh(state)||state["expires"].get<double>()>now()+4||!state.value("session",J()).is_string()||!state.value("login",J()).is_string())throw std::runtime_error("credential");
  credential=J::object();for(auto k:{"session","login","password","expires"})credential[k]=state[k];reply(socket,204);return;
 }
 if(!state.value("session",J()).is_string()||state["session"].get_ref<const std::string&>().size()>=100||!state.value("serial",J()).is_number_integer()||!state.value("revision",J()).is_number_integer())throw std::runtime_error("state");
 J safe=J::object();for(auto k:{"session","serial","revision","active","intentAck","ready","captureReady"})if(state.contains(k)&&state[k].is_primitive())safe[k]=state[k];
 safe["dialog"]=cleanDialog(state.value("dialog",J()));
 if(state.value("auth",J()).is_object()){safe["auth"]=J::object();for(auto k:{"show","login","error","manual"})if(state["auth"].contains(k)&&state["auth"][k].is_primitive())safe["auth"][k]=state["auth"][k];}
 safe["time"]=now();writeFile("snapshot.json",safe.dump());
 auto cap=cleanDialog(state.value("capture",J()));auto policy=readJson("capture.json");
 auto key=J::array({state["session"],state["serial"],state["revision"]}).dump();
 if(!cap.is_null()&&state.value("captureReady",false)&&fresh(policy)&&policy["expires"].get<double>()<=now()+1200&&key!=lastCapture){
  auto path=folder/"dossier-capture.jsonl";auto row=J{{"time",now()},{"session",state["session"]},{"serial",state["serial"]},{"revision",state["revision"]},{"dialog",cap}}.dump()+"\n";
  std::error_code ec;auto size=fs::exists(path)?fs::file_size(path,ec):0;
  if(!ec&&size+row.size()<=8388608){std::ofstream f(path,std::ios::binary|std::ios::app);f<<row;if(f)lastCapture=key;}
 }
 auto response=readJson("response.json"),intent=readJson("intent.json");
 if(!fresh(response)||!same(response,state,"session")||!same(response,state,"serial")||!same(response,state,"revision"))response=nullptr;
 if(!fresh(intent)||!same(intent,state,"session"))intent=nullptr;
 J login=nullptr;if(fresh(credential)&&same(credential,state,"session")){login=credential;credential=nullptr;}
 reply(socket,200,J{{"kind","envelope"},{"response",response},{"intent",intent},{"credential",login}}.dump());
}
static DWORD WINAPI worker(void*){
 SOCKET listener=INVALID_SOCKET;bool initialized=false;
 try{
  WSADATA data;if(WSAStartup(MAKEWORD(2,2),&data))throw std::runtime_error("winsock");initialized=true;
  listener=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);if(listener==INVALID_SOCKET)throw std::runtime_error("socket");
  BOOL exclusive=TRUE;setsockopt(listener,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,(char*)&exclusive,sizeof(exclusive));
  sockaddr_in addr{};addr.sin_family=AF_INET;addr.sin_port=htons(static_cast<u_short>(port));addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
  if(bind(listener,(sockaddr*)&addr,sizeof(addr))||listen(listener,4)){status=-3;throw std::runtime_error("bind");}
  status=2;J credential;std::string lastCapture;double heartbeat=0;
  while(!stopping){
   if(now()!=heartbeat){writeFile("heartbeat.txt",std::to_string(static_cast<long long>(now())));heartbeat=now();}
   if(!fresh(credential))credential=nullptr;
   fd_set set;FD_ZERO(&set);FD_SET(listener,&set);timeval wait{0,200000};int ready=select(0,&set,nullptr,nullptr,&wait);if(ready<0)throw std::runtime_error("select");if(!ready)continue;
   SOCKET client=accept(listener,nullptr,nullptr);if(client==INVALID_SOCKET)continue;
   try{handle(client,credential,lastCapture);}catch(...){reply(client,400);}
   // Flush the response before closing even when a rejected request body is in flight.
   shutdown(client,SD_SEND);DWORD drainTimeout=50;
   setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,(char*)&drainTimeout,sizeof(drainTimeout));
   char drain[1024];for(int total=0;total<8192;){int n=recv(client,drain,sizeof(drain),0);if(n<=0)break;total+=n;}
   closesocket(client);
  }
 }catch(...){if(status>=0)status=-2;}
 if(listener!=INVALID_SOCKET)closesocket(listener);if(initialized)WSACleanup();if(stopping)status=0;return 0;
}
extern "C" __declspec(dllexport) int __cdecl XTBridgeStatus(){return status;}
extern "C" __declspec(dllexport) int __cdecl XTBridgeStart(){
 AcquireSRWLockExclusive(&lifecycle);
 if(threadHandle&&WaitForSingleObject(threadHandle,0)==WAIT_TIMEOUT){int s=status;ReleaseSRWLockExclusive(&lifecycle);return s;}
 if(threadHandle){CloseHandle(threadHandle);threadHandle=nullptr;}
 try{
  wchar_t path[32768];DWORD n=GetModuleFileNameW(module,path,32768);if(!n||n>=32768)throw std::runtime_error("path");
  folder=fs::path(path).parent_path()/L"moonloader"/L"X-TOOL"/L"cef-bridge";
  auto config=readJson("transport.json");token=config.at("token").get<std::string>();
  if(token.size()!=48||token.find_first_not_of("0123456789abcdef")!=std::string::npos)throw std::runtime_error("token");
  port=config.value("port",18766);if(port<1024||port>65535)throw std::runtime_error("port");
  HMODULE pinned;if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&XTBridgeStart),&pinned))throw std::runtime_error("pin");
  stopping=false;status=1;threadHandle=CreateThread(nullptr,0,worker,nullptr,0,nullptr);if(!threadHandle)status=-2;
 }catch(...){status=-1;}
 int result=status;ReleaseSRWLockExclusive(&lifecycle);return result;
}
extern "C" __declspec(dllexport) int __cdecl XTBridgeStop(){
 AcquireSRWLockExclusive(&lifecycle);stopping=true;
 int result=1;if(threadHandle){if(WaitForSingleObject(threadHandle,6000)==WAIT_OBJECT_0){CloseHandle(threadHandle);threadHandle=nullptr;}else result=0;}
 ReleaseSRWLockExclusive(&lifecycle);return result;
}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID){if(reason==DLL_PROCESS_ATTACH){module=instance;DisableThreadLibraryCalls(instance);}return TRUE;}
