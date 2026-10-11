from pathlib import Path
import sys,unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'.test-deps'))
from lupa.luajit21 import LuaRuntime
CODE=(ROOT/'X-TOOL.lua').read_text('utf-8')
def module(name):
 start=CODE.index('    sources["'+name+'"] = function()\n')
 start=CODE.index('\n',start)+1
 return CODE[start:CODE.index('\n    end\n    sources[',start)]
class QueueFamily(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.globals().confirmation=self.lua.execute(module('queue_confirmation.lua'))
 def test_confirmation(self):
  self.lua.execute('''
   local actor,target='Admin_Test','Player_Test'
   local cases={
    {'/fj Player_Test 120 reason','посадил в тюрьму игрока Player_Test[5] на 120 минут. Причина: reason [Family]'},
    {'/fj Player_Test 120 reason','посадил оффлайн игрока Player_Test на 120 минут. Причина: reason [Family]'},
    {'/fw Player_Test reason','выдал предупреждение игроку Player_Test[5]. Причина: reason [Family]'},
    {'/fb Player_Test 3 reason','забанил игрока Player_Test[5] на 3 дня. Причина: reason [Family]'}}
   for _,c in ipairs(cases)do
    local text='[A] Admin_Test[1] '..c[2]
    assert(confirmation.match(c[1],text,target,actor),c[1])
    assert(not confirmation.match(c[1],text,'Other_Player',actor))
    assert(not confirmation.match(c[1],text,target,'Other_Admin'))
    assert(not confirmation.match(c[1],text:gsub('reason','different'),target,actor))
    assert(not confirmation.match(c[1],'[A] Admin_Test[1]: '..c[2],target,actor))
   end
   assert(not confirmation.match('/fj Player_Test 20 reason','[A] Admin_Test[1] '..cases[1][2],target,actor))
   assert(not confirmation.match('/jail Player_Test 120 reason','[A] Admin_Test[1] '..cases[1][2],target,actor))
  ''')
 def queue(self,command,rejected=False):
  self.lua.globals().input_command=command;self.lua.globals().rejected=rejected
  self.lua.execute('''
   files={queue=input_command};calls={};tick=0;events={}
   local u=setmetatable({decode=function(_,s)return s end},{__call=function(_,s)return s end})
   function require(n)if n=='encoding'then return {UTF8=u}elseif n=='samp.events'then return events else return {}end end
   io={open=function(path,mode)
    if mode=='rb'then if files[path]==nil then return end;return {read=function()return files[path]end,close=function()return true end}end
    return {write=function(_,s)files[path]=s;return true end,close=function()return true end}
   end}
   integration={root='root',storage={path=function()return 'queue'end,loadIni=function()return {main={interval=1}}end},
    access={revision=function()return 1 end,can=function()return true end,require=function()return true end},
    message=function()end,cancelPending=function()end,queryBusy=function()return false end,
    guardResult=function()end,service=function()return confirmation end}
   function getWorkingDirectory()return 'root'end
   function isSampAvailable()return true end
   function sampGetGamestate()return 3 end
   function getGameTimer()return tick end
   function wait(ms)tick=tick+ms end
   function sampIsPlayerConnected()return true end
   function sampGetPlayerNickname()return 'Admin_Test'end
   function sampGetPlayerIdByCharHandle()return true,1 end
   lua_thread={create=function(fn)fn()end}
   function sampSendChat(cmd)calls[#calls+1]='server:'..cmd;return not rejected end
   function sampProcessChatInput(cmd)
    calls[#calls+1]='local:'..cmd
    if rejected then return false end
    events.onServerMessage(0,'[A] Admin_Test[1] посадил в тюрьму игрока Player_Test[5] на 120 минут. Причина: reason [Family]')
   end
  ''')
  self.lua.execute(module('modules/queue.lua'))
  self.lua.execute('integration.startQueue()')
 def test_family_local_dispatch_and_no_repeat(self):
  self.queue('/fj Player_Test 120 reason')
  self.lua.execute("assert(#calls==1 and calls[1]=='local:'..input_command);assert(files.queue:find('Результат:',1,true));integration.startQueue();assert(#calls==1)")
 def test_server_command_stays_server(self):
  self.queue('/jail Player_Test 120 reason')
  self.lua.execute("assert(#calls==1 and calls[1]=='server:'..input_command);assert(files.queue:find('ответ не подтверждён',1,true))")
 def test_rejected_dispatch_stops(self):
  self.queue('/fj Player_Test 120 reason\n/fj Other_Player 120 reason',True)
  self.lua.execute("assert(#calls==1);assert(files.queue:find('ошибка отправки',1,true))")
if __name__=='__main__':unittest.main()
