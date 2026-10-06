const fs=require('fs'),vm=require('vm'),assert=require('assert');
let tick,output=[];
const context={window:{},Date,JSON,Number,String,Array,Error,AbortController,
 setInterval:f=>(tick=f,1),clearInterval:()=>{},setTimeout:()=>1,clearTimeout:()=>{},
 fetch:async(url,options)=>{output.push(...options.body.split('\n').map(JSON.parse));return {ok:true};}};
vm.runInNewContext(fs.readFileSync(__dirname+'/cef-probe.js','utf8'),context);
const emit=context.window.__xtCefProbe;
emit('cef:dialog',[JSON.stringify({DIALOG_TYPE:0,DIALOG_HEADER:'Stats',DIALOG_TEXT:'Account data',DIALOG_INPUT:'SECRET'})]);
emit('cef:dialogtext',[' more']);
emit('cef:dialogResponse',[1,2,'SECRET']);
emit('cef:dialog',[JSON.stringify({DIALOG_TYPE:3,DIALOG_HEADER:'Password',DIALOG_TEXT:'SECRET'})]);
emit('cef:dialogtext',['SECRET']);
emit('cef:loginResponse',['SECRET']);
tick();
assert(output.some(r=>r.event==='probe_ready'));
assert(output.some(r=>r.event==='dialog'&&r.data.DIALOG_TEXT==='Account data'));
assert(output.some(r=>r.event==='dialog_append'));
assert(output.some(r=>r.event==='dialog_redacted'));
assert(!JSON.stringify(output).includes('SECRET'));
assert.equal(output.filter(r=>r.event==='dialog_response').length,1);
console.log('PASS: CEF parsing, appended text, response metadata, auth/input redaction');
