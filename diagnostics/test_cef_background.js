const fs=require('fs'),vm=require('vm'),assert=require('assert');
let now=10000,timer,state,reply=null,loginCalls=0;
const w={__xtCefLogin:()=>loginCalls++};
vm.runInNewContext(fs.readFileSync(__dirname+'/cef-family-bridge.js','utf8'),{
 window:w,Date:{now:()=>now},Math,JSON,String,Number,Array,AbortController,
 setInterval:f=>(timer=f,1),clearInterval:()=>{},setTimeout:()=>1,clearTimeout:()=>{},
 fetch:async(u,o)=>{state=JSON.parse(o.body);return {ok:true,json:async()=>reply};}});
const tick=async()=>{timer();await new Promise(r=>setImmediate(r));};
const show=name=>w.__xtCefProbe('cef:dialog',[JSON.stringify({DIALOG_TYPE:0,DIALOG_HEADER:'Оффлайн статистика игрока',DIALOG_TEXT:'{FFFFFF}Имя:&emsp;{66c2ff}'+name+'<br>Семья: Test'})]);
(async()=>{
 await tick();
 reply={kind:'envelope',intent:{session:state.session,nonce:'i',name:'Test_User',expires:20}};
 await tick();show('Other_User');assert(!w.__xtCefHidden);
 reply.intent.nonce='j';await tick();show('Test_User');assert(w.__xtCefHidden);
 show('Test_User');assert(!w.__xtCefHidden,'manual request after consuming intent remains visible');
 reply.intent.nonce='k';reply.intent.expires=9;await tick();show('Test_User');assert(!w.__xtCefHidden);
 w.__xtCefProbe('cef:login',[JSON.stringify({AUTH_SHOW:true,AUTH_LOGIN:'Test_User',AUTH_PASS:'NEVER_CAPTURE'})]);
 reply={kind:'envelope',credential:{session:state.session,login:'Test_User',password:'test-only',expires:20}};
 await tick();assert.equal(loginCalls,1);assert(!JSON.stringify(state).includes('NEVER_CAPTURE'));
 reply.credential.password='test-only';await tick();assert.equal(loginCalls,1);
 w.__xtCefProbe('cef:loginerror',['{}']);w.__xtCefAuthStatus=()=>({show:true,login:'Test_User',error:false});
 await tick();assert(state.auth.error);assert.equal(loginCalls,1);
 console.log('PASS: target-bound hidden offst, manual/expired exclusions, auth redaction, single attempt, persistent error stop');
})().catch(e=>{console.error(e);process.exit(1)});
