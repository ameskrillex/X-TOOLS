from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'.test-deps'))
from lupa.luajit21 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
events={};captured={};commands={};tick=100
function script_name()end;function script_author()end;function script_version()end
function require(name)
 if name=='lib.samp.events'then return events end
 if name=='encoding'then return {UTF8=function(s)return s end}end
 return {}
end
function getGameTimer()return tick end
function getWorkingDirectory()return 'test' end
function doesDirectoryExist()return true end
function doesFileExist()return false end
function sampAddChatMessage()end
function isSampAvailable()return true end
function sampRegisterChatCommand(name,fn)commands[name]=fn end
function wait()coroutine.yield()end
function encodeJson(row)table.insert(captured,row);return '{}' end
io.open=function()return {write=function()return true end,close=function()end}end
''')
lua.execute(Path(__file__).with_name('XT-Dialog-Probe.lua').read_text('utf-8'))
lua.execute('''
worker=coroutine.create(main);assert(coroutine.resume(worker));assert(coroutine.resume(worker))
commands.xtprobe('start')
assert(events.onShowDialog(0,0,'Stats','OK','','Name: Test_User')==nil)
assert(events.onShowDialog(1,1,'Authorization','OK','','SECRET')==nil)
assert(events.onSendDialogResponse(1,1,-1,'PASSWORD')==nil)
events.onSendCommand('/offst Test_User')
events.onSendCommand('/login SECRET')
commands.xtprobe('stop')
local normal,redacted,response,command=0,0,0,0
for _,r in ipairs(captured)do
 if r.event=='dialog'then normal=normal+1;assert(r.data.body=='Name: Test_User')end
 if r.event=='dialog_redacted'then redacted=redacted+1;assert(r.data.body==nil)end
 if r.event=='dialog_response'then response=response+1;assert(r.data.input=='[omitted]')end
 if r.event=='command'then command=command+1;assert(r.data.verb=='offst' and r.data.args=='[omitted]')end
end
assert(normal==1 and redacted==1 and response==1 and command==1)
before=#captured;events.onShowDialog(0,0,'Stats','','','after stop');commands.xtprobe('stop')
assert(#captured==before)
''')
print('PASS: LuaJIT compile, passive handlers, auth redaction, omitted inputs/arguments, stop')
