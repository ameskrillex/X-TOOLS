const fs=require('fs'),vm=require('vm'),assert=require('assert');
let now=10000,timer,state,cmd=null,hidden=0,responses=[];
const w={__xtCefDialogHide:()=>hidden++,__xtCefDialogRespond:(b,r,guard)=>{if(guard())responses.push([b,r]);}};
vm.runInNewContext(fs.readFileSync(__dirname+'/cef-family-bridge.js','utf8'),{
 window:w,Date:{now:()=>now},Math,JSON,String,Number,Array,AbortController,
 setInterval:f=>(timer=f,1),clearInterval:()=>{},setTimeout:()=>1,clearTimeout:()=>{},
 fetch:async(u,o)=>{state=JSON.parse(o.body);return {ok:true,json:async()=>cmd};}});
const tick=async()=>{timer();await new Promise(r=>setImmediate(r));};
const show=d=>w.__xtCefProbe('cef:dialog',[JSON.stringify(d)]);
(async()=>{
 const config=JSON.parse(fs.readFileSync(__dirname+'/cef-family-local.json','utf8'));
 const rows=fs.readFileSync(config.directory+'/dossier-capture.jsonl','utf8').trim().split('\n').map(JSON.parse);
 let recognized=0;
 for(const record of rows){show(record.dialog);now+=600;await tick();if(state.ready)recognized++;}
 assert(recognized>=50);
 show({DIALOG_TYPE:4,DIALOG_HEADER:'Семья',DIALOG_TEXT:'A<br>B'});now+=600;await tick();
 cmd={session:state.session,serial:state.serial,revision:state.revision,kind:'hide',nonce:'hide',expires:now/1000+3};
 await tick();assert.equal(hidden,1);assert.equal(responses.length,0);await tick();assert.equal(hidden,1);
 cmd={...cmd,kind:'response',nonce:'select',button:1,row:1};await tick();assert.deepEqual(responses,[[1,1]]);
 show({DIALOG_TYPE:0,DIALOG_HEADER:'Unknown',DIALOG_TEXT:'Other'});await tick();assert.equal(responses.length,1);
 show({DIALOG_TYPE:0,DIALOG_HEADER:'Точное время',DIALOG_TEXT:'clock'});now+=600;await tick();
 cmd={...cmd,serial:state.serial,revision:state.revision,nonce:'close',button:1,row:-1};await tick();assert.equal(responses.length,2);
 for(const d of [{DIALOG_TYPE:1,DIALOG_HEADER:'Авторизация',DIALOG_TEXT:'SECRET'},
                  {DIALOG_TYPE:0,DIALOG_HEADER:'Пароль',DIALOG_TEXT:'SECRET'}]){
  show(d);await tick();assert(!state.dialog&&!state.capture&&!JSON.stringify(state).includes('SECRET'));
 }
 console.log('PASS: captured CEF fixtures, local hide without server response, bound selection, replacement and auth exclusions');
})().catch(e=>{console.error(e);process.exit(1)});
