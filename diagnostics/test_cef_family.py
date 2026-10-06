from pathlib import Path
import sys,json
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root.parent/'.test-deps'))
from lupa.luajit21 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().bridge=lua.execute((root/'libraries/cef_family_bridge.lua').read_text('utf-8'))
lua.execute('''
assert(bridge.text('A<br>B<tbl>C&emsp;D&amp;E')=='A\nB\tC D&E')
local d=bridge.decode({DIALOG_TYPE=4,DIALOG_HEADER='{FFCD00}Семья',DIALOG_KEYS={'Закрыть','Далее'},DIALOG_TEXT='A<br>B'})
assert(d.owner=='family_registry' and d.button1=='Далее' and d.button2=='Закрыть')
assert(not bridge.decode({DIALOG_TYPE=1,DIALOG_HEADER='Password'}))
tick=1000;epoch=100;revision=7;written=nil;calls=0
snapshot={session='s',serial=1,revision=0,active=true,ready=true,time=100,
 dialog={DIALOG_TYPE=0,DIALOG_HEADER='Оффлайн статистика игрока',DIALOG_TEXT='Имя: Test_User<br>Семья: Test',DIALOG_KEYS={'','Закрыть'}}}
local api={os={time=function()return epoch end},io={open=function(path,mode)
 if mode=='rb'then return {read=function()return ''end,close=function()end}end
 return {write=function(_,s)written=s;return true end,close=function()end}
end},decodeJson=function()return snapshot end,encodeJson=function(d)return d end,
 getGameTimer=function()return tick end,sampGetGamestate=function()return 3 end,
 require=function()return {UTF8={decode=function(_,s)return s end}}end}
rt={api=api,access={canUseTools=function()return true end,revision=function()return revision end},
 modules={familia={events={onShowDialog=function()end}}},featureAllowed=function()return true end,
 call=function(_,m,fn,id,style,title,b1,b2,body)calls=calls+1;assert(id==0);assert(body:find('Семья: Test',1,true));return false end}
b=bridge.new(rt,'test');b:poll();assert(calls==1);tick=1200;b:poll();assert(calls==1)
assert(written.kind=='hide');written=nil
assert(not b:active('familia'));assert(b:active('family_registry'));assert(b:active())
snapshot.revision=1;assert(b:active('familia'));snapshot.revision=0
snapshot.serial=2;local handled,ok=b:respond('familia',0,0,0,'');assert(handled and not ok and not written)
tick=1400;b:poll();handled,ok=b:respond('familia',0,0,0,'');assert(handled and ok and written.serial==2)
written=nil;handled,ok=b:respond('familia',0,0,0,'');assert(handled and not ok and not written)
snapshot.serial=3;tick=1600;b:poll();revision=8;handled,ok=b:respond('familia',0,0,0,'');assert(handled and not ok)
snapshot.serial=4;tick=1800;b:poll();snapshot.active=false;handled,ok=b:respond('familia',0,0,0,'');assert(handled and not ok)
epoch=200;assert(not b:active())
assert(not b:respond('aegis',55,1,0,''))
epoch=100;snapshot.time=100;snapshot.active=false;snapshot.ready=false
sent=0;rt.send=function(_,owner,api,command)sent=sent+1;assert(command=='/offst Test_User')end
assert(b:prepare('familia','sampSendChat','/offst Test_User'))
local nonce=b.queued.intent.nonce
tick=2000;b:poll();assert(sent==0)
snapshot.intentAck=nonce;tick=2200;b:poll();assert(sent==1)
tick=2400;b:poll();assert(sent==1)
assert(not b:prepare('core','sampSendChat','/offst Test_User'))
'''.replace("=='A\nB\tC D&E'","=='A\\nB\\tC D&E'"))
code=(root/'artifacts/cef-family-dev/X-TOOL.lua').read_text('utf-8')
lua.execute('assert(loadstring(...))',code)
start=code.index("function events.onSendCommand(command)\n    if internal or integration.commandOwner()=='familia'")
end=code.index('function events.onPlayerQuit',start)
lua.execute("events={};internal=false;pending={};owner='familia';integration={commandOwner=function()return owner end};say=function()end\n"+code[start:end])
lua.execute("assert(events.onSendCommand('/offst Test_User')==nil);owner=nil;assert(events.onSendCommand('/offst Test_User')==false);owner='lookup';assert(events.onSendCommand('/offst Test_User')==false)")
print('PASS: deferred familia command allowed; manual and unrelated duplicate commands blocked')
start=code.index('    sources["family_roster.lua"] = function()\n')+len('    sources["family_roster.lua"] = function()\n')
lua.globals().roster=lua.execute(code[start:code.index('\n    end\n    sources[',start)])
lua.execute('''
clock=0;responses={};saved=false
scan=roster.new({now=function()return clock end,ready=function()return true end,
 dialogOpen=function()return false end,send=function()return true end,
 respond=function(id,b,r)table.insert(responses,{id,b,r})end,
 commit=function()saved=true;return true end})
assert(scan:start({{name='Test',key='test'}},true))
clock=1000;scan:tick()
assert(scan:dialog(32001,4,'Семья','Выбрать','Закрыть','Участники семьи')==false)
clock=1600;scan:tick()
assert(scan:dialog(32001,5,'Список игроков в семье','Выбрать','Назад','Ник\\tРанг\\nTest_User\\t1')==false)
clock=2200;scan:tick();assert(saved and scan.stage=='cef_return')
clock=3300;scan:tick();assert(scan.active and scan.stage=='cef_return')
assert(scan:dialog(32001,4,'Семья','Выбрать','Закрыть','Участники семьи')==false)
clock=3900;scan:tick();assert(responses[#responses][2]==0 and scan.stage=='advance')
clock=4000;scan:tick();assert(not scan.active)
''')
print('PASS: delayed CEF return menu is closed before completing the roster scan')
print('PASS: markup, reversed buttons, exact routing, stale window/session rights, one-shot responses, bundle compile')
