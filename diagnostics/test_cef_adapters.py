"""Replay local captures without copying account data into repository fixtures."""
from pathlib import Path
import json, sys
from collections import Counter
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root.parent/'.test-deps'))
from lupa.luajit21 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
code=(root/'artifacts/cef-family-dev/X-TOOL.lua').read_text('utf-8')
lua.execute('assert(loadstring(...))',code)
def source(name):
    start=code.index(f'    sources["{name}"] = function()\n')+len(f'    sources["{name}"] = function()\n')
    return lua.execute(code[start:code.index('\n    end\n    sources[',start)])
bridge=source('cef_family_bridge.lua')
skills=source('weapon_skills.lua')
org=source('organization_find.lua')
square=source('square_report.lua')
online=source('online_stats.lua')
leader=source('leader_online.lua')
def table(value):
    if isinstance(value,dict): return lua.table_from({k:table(v)for k,v in value.items()})
    if isinstance(value,list): return lua.table_from([table(v)for v in value])
    return value
config=json.loads((root/'diagnostics/cef-family-local.json').read_text('utf-8'))
rows=[json.loads(x)for x in (Path(config['directory'])/'dossier-capture.jsonl').read_text('utf-8').splitlines()]
counts=Counter()
for capture in rows:
    row=bridge.decode(table(capture['dialog']))
    if row is None: continue
    kind=row['kind']or 'family'
    counts[kind]+=1
    if kind=='skills':
        parsed=skills.parse(row['body'],True)
        assert not isinstance(parsed,tuple),parsed
        assert len(parsed)==1 and len(parsed[1])==11
        plan=skills.plan(parsed,0)
        assert all(plan[n]['group']==1 for n in range(1,len(plan)+1))
        assert isinstance(skills.parse(row['body'],False),tuple),'Native strict parsing retained'
    elif kind=='find':
        parsed=org.parse(63,row['style'],row['title'],row['body'],-1)
        assert parsed and parsed['total']==140 and parsed['rawOnline']==11
        assert len(list(parsed['players'].items()))==11
    elif kind=='season':
        assert square.seasonChoice(row['body'])[0]==1
    elif kind=='square':
        assert len(square.rows(row['body'],False))==2
    elif kind=='time':
        parsed=online.parse(row['body'])
        assert parsed and not isinstance(parsed,tuple),parsed
    elif kind=='account':
        parsed=leader.parse(row['title'],row['body'],row['title'])
        assert parsed and not isinstance(parsed,tuple),parsed
assert all(counts[k] for k in ['account','offst','baninfo','ip','log','history','leaders','admins','family','square','season','top','time','skills','lego','find','find_menu']),dict(counts)
print('PASS: recorded dialog decoding and actual skills/organization/square parsers; counts:',dict(counts))
lua.globals().bridge=bridge
lua.globals().orgParser=org
lua.execute('''
local clock,epoch,revision=1000,100,7
local output,calls={},{}
local state={session='s',serial=1,revision=0,active=true,ready=true,time=100}
local api={getGameTimer=function()return clock end,os={time=function()return epoch end},
 sampGetGamestate=function()return 3 end,sampGetPlayerIdByCharHandle=function()return true,1 end,
 decodeJson=function()return state end,encodeJson=function(d)return d end,
 require=function()return {UTF8={decode=function(_,s)return s end}}end,
 io={open=function(_,mode)return {read=function()return ''end,close=function()end,
 write=function(_,v)output[#output+1]=v;return true end}end}}
local rt={api=api,modules={},access={canUseTools=function()return true end,revision=function()return revision end},
 featureAllowed=function()return true end,service=function()return orgParser end,
 call=function(_,m,fn,...)return fn(...)end}
local b=bridge.new(rt,'test')
local function show(title,style,body,keys)
 clock=clock+200;state.serial=state.serial+1
 state.dialog={DIALOG_HEADER=title,DIALOG_TYPE=style,DIALOG_TEXT=body,DIALOG_KEYS=keys or {'','Закрыть'}}
 b:poll()
end
rt.modules.adm={events={onShowDialog=function()calls[#calls+1]='adm' end}}
rt.modules.lookup={events={onShowDialog=function(id)calls[#calls+1]='lookup';return false end}}
show('Test_User',0,'Номер аккаунта: 123')
assert(calls[1]=='adm'and calls[2]=='lookup'and output[#output].kind=='response')
local n=#output
-- Unknown windows never reach the permissive /log consumer.
show('Random',0,'Unknown body');assert(#calls==2 and #output==n)
-- History pagination is emitted inside its handler: it must not be overwritten by hide/close.
rt.modules.lookup.events.onShowDialog=function(id) b:respond('lookup',id,1,0,'');return false end
show('Прошлые имена Test_User',4,'old name',{'Закрыть','Стр.2 >>'})
assert(output[#output].button==1 and #output==n+1)
-- Native dialog responses pass through when no CEF claim exists.
b:nativeDialog();assert(not b:respond('lookup',0,0,0,''))
-- Only the organization sweep may navigate /find menus.
n=#output
show('Что Вы хотите просмотреть?',2,'1. Список членов организации (подразделения) онлайн')
assert(#output==n)
rt.organizationFindWaiting=true
show('Что Вы хотите просмотреть?',2,'1. Список членов организации (подразделения) онлайн')
assert(output[#output].button==1 and output[#output].row==0)
show('Выберите подразделение',2,'1. Все подразделения<br>2. ФБР')
assert(output[#output].button==1 and output[#output].row==0)
show('В подразделении 4 чел. (онлайн 2)',5,'Имя<tbl>Статус<br>1. Test_User[1]<tbl>Онлайн<br>2. Other_User[2]<tbl>На паузе')
assert(rt.organizationFindReply.online==1 and rt.organizationFindReply.paused==1)
-- Scheduled replies are rejected after another CEF window replaces their owner.
rt.modules.family_registry={events={onShowDialog=function()return false end}}
show('Сезоны',2,'1. Top')
n=#output
show('Unknown',0,'Other')
local handled,ok=b:respond('family_registry',32001,1,0,'1. Top')
assert(handled and not ok and #output==n)
-- Native non-empty input is never blocked by the CEF adapter.
b:nativeDialog();assert(not b:respond('lookup',7,1,0,'search'))
-- The ban guard gets its own matching response before the dossier consumer.
local guarded=0
rt.offban={pending={},observe=function(_,event,id,style,title)
 assert(event=='onShowDialog'and title=='Test_User');guarded=guarded+1;return false end}
show('Test_User',0,'Номер аккаунта: 1<br>Ник забаненного: Test_User<br>Дней до конца бана: 2')
assert(guarded==1 and b.claims.cef_offban and output[#output].kind=='hide')
assert(b:respond('cef_offban',32002,0,0,''))
''')
print('PASS: consumer ownership, history navigation, native fallback, unrelated windows, find menus and stale responses')

# Run the actual LEGO module against all four captured pages, not a mirror parser.
lua.execute('''
legoReplies={};legoDeferred={};events={};integration={preferences={data={main={legoReplace=true}}},
 access={can=function()return true end,require=function()return true end},
 open=function()end,message=function()end,commandOwner=function()return 'lego'end,
 cefDialogOwned=function()return true end}
local g={ImBuffer=function(v)return {v=v}end,ImInt=function(v)return {v=v}end}
local u8=setmetatable({decode=function(_,s)return s end},{__call=function(_,s)return s end})
require=function(name)if name=='imgui'then return g elseif name=='encoding'then return {UTF8=u8}else return events end end
getGameTimer=function()return 1000 end;sampGetGamestate=function()return 3 end
sampRegisterChatCommand=function(_,fn)legoOpen=fn end;sampSendChat=function()return true end
sampSendDialogResponse=function(id,b,r)legoReplies[#legoReplies+1]={id,b,r}end
lua_thread={create=function(fn)legoDeferred[#legoDeferred+1]=fn end};wait=function()end
''')
source('modules/lego.lua')
lua.execute("legoOpen('')")
pages=[bridge.decode(table(x['dialog']))for x in rows if x['dialog']['DIALOG_HEADER'].find('LEGO-локации')>=0]
for page in pages[:4]:
    assert lua.globals().events.onShowDialog(688,5,page['title'],page['button1'],page['button2'],page['body']) is False
    lua.execute('while #legoDeferred>0 do table.remove(legoDeferred,1)()end')
lua.execute('''
local i=1;local state
while true do local k,v=debug.getupvalue(integration.draw,i);if not k then break end;if k=='state'then state=v;break end;i=i+1 end
assert(state and state.ready and state.mode=='idle'and #state.pages==4 and #state.locations>10)
assert(#legoReplies==4)
for _,r in ipairs(legoReplies)do assert(r[1]==688 and r[2]==0 and r[3]==0)end
''')
print('PASS: actual LEGO module collects four pages and closes the final CEF list')
