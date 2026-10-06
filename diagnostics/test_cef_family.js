const fs=require('fs'),vm=require('vm'),assert=require('assert');
let now=10000,timer,state,cmd=null,sends=[];
const context={window:{__xtCefDialogRespond:(b,r,guard)=>{if(guard())sends.push([b,r]);}},
 Date:{now:()=>now},Math,JSON,String,Number,Array,AbortController,
 setInterval:f=>(timer=f,1),clearInterval:()=>{},setTimeout:()=>1,clearTimeout:()=>{},
 fetch:async(url,options)=>{state=JSON.parse(options.body);return {ok:true,json:async()=>cmd}}};
vm.runInNewContext(fs.readFileSync(__dirname+'/cef-family-bridge.js','utf8'),context);
const event=context.window.__xtCefProbe;
const settle=()=>new Promise(resolve=>setImmediate(resolve));
(async()=>{
 event('cef:dialog',[JSON.stringify({DIALOG_TYPE:4,DIALOG_HEADER:'Семья',DIALOG_KEYS:['Назад','Выбрать'],DIALOG_TEXT:'A<br>B'})]);
 timer();await settle();assert(!state.ready);
 event('cef:dialogtext',['<br>C']);now+=600;timer();await settle();assert(state.ready&&state.dialog.DIALOG_TEXT.endsWith('C'));
 cmd={session:state.session,serial:state.serial,revision:state.revision,button:1,row:2,expires:30,nonce:'one'};
 timer();await settle();assert.deepEqual(sends,[[1,2]]);
 timer();await settle();assert.equal(sends.length,1);
 cmd={...cmd,nonce:'two',serial:99};timer();await settle();assert.equal(sends.length,1);
 event('cef:dialogResponse',[0,0]);cmd={...cmd,nonce:'three',serial:1};timer();await settle();assert.equal(sends.length,1);
 event('cef:dialog',[JSON.stringify({DIALOG_TYPE:1,DIALOG_HEADER:'Password',DIALOG_TEXT:'SECRET'})]);now+=600;timer();await settle();assert(!state.dialog&&!JSON.stringify(state).includes('SECRET'));
 console.log('PASS: chunk settling, original row, one-shot, stale/manual-close rejection, unrelated/auth exclusion');
})().catch(e=>{console.error(e);process.exit(1)});
