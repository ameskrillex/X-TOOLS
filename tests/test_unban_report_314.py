from pathlib import Path
import sys,unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'tools/deps'))
from lupa.luajit21 import LuaRuntime
CODE=(ROOT/'X-TOOL.lua').read_text('utf8')
def module(name):
 a=CODE.index('    sources["'+name+'"] = function()\n')+len('    sources["'+name+'"] = function()\n')
 return CODE[a:CODE.index('\n    end\n    sources[',a)]
class UnbanReport(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime()
  self.lua.globals().responses=self.lua.execute(module('aegis_responses.lua'))
  self.lua.globals().Report=self.lua.execute(module('unban_report.lua'))
  self.lua.execute('''
   now=0;sent={};messages={};allowed=true
   u8=setmetatable({decode=function(_,s)return s end},{__call=function(_,s)return s end})
   rt={preferences={data={main={unbanReport=true}}},api={getGameTimer=function()return now*1000 end,
    require=function()return {UTF8=u8}end,PLAYER_PED=1,sampGetPlayerIdByCharHandle=function()return true,0 end,
    sampGetPlayerNickname=function()return 'Local_Admin'end}}
   function rt:service()return responses end
   function rt:canServerCommand()return allowed end
   function rt:message(s)table.insert(messages,s)end
   function rt:send(_,_,s)table.insert(sent,s);return true end
   r=Report.new(rt)
   function start()assert(r:enqueue('/UNBAN Test_Player'));r:update();assert(sent[1]=='/baninfo Test_Player')end
   function info()
    assert(r:observe('onShowDialog',1,0,'Test_Player','','','Ник забаненного: Test_Player\\nДата бана: 10.11.2026 12:30:00\\nДней до конца бана: 17')==false)
    r:update();assert(sent[2]=='/UNBAN Test_Player')
   end
  ''')
 def test_success_once_and_only_matching_account(self):
  self.lua.execute('''start();info();assert(#sent==2)
   r:observe('onServerMessage',0,'Аккаунт Other_Player разблокирован.');r:update();assert(#sent==2)
   r:observe('onServerMessage',0,'[A] Other_Admin[2] разбанил игрока Test_Player.');r:update();assert(#sent==2)
   r:observe('onServerMessage',0,'[A] Local_Admin[0] разбанил игрока Test_Player.');r:update()
   assert(sent[3]=='/a Мной разблокирован аккаунт Test_Player. Бан: 10.11.2026; оставалось 17 дн.')
   r:observe('onServerMessage',0,'Аккаунт Test_Player разблокирован.');r:update();assert(#sent==3)
  ''')
 def test_disabled_and_unavailable(self):
  self.lua.execute("rt.preferences.data.main.unbanReport=false;assert(not r:enqueue('/unban Test_Player'));r:update();assert(#sent==0);rt.preferences.data.main.unbanReport=true;allowed=false;assert(not r:enqueue('/unban Test_Player'));assert(#sent==0)")
 def test_timeout_and_failure_never_report_success(self):
  self.lua.execute("start();now=6;r:update();r:update();assert(sent[2]=='/UNBAN Test_Player');r:observe('onServerMessage',0,'Аккаунт Test_Player разблокирован.');r:update();assert(#sent==2)")
  self.setUp()
  self.lua.execute("start();info();r:observe('onServerMessage',0,'Такого игрока нет в базе данных.');r:update();assert(#sent==2 and r.pending==nil)")
 def test_disconnect_and_unrelated_dialog(self):
  self.lua.execute("start();assert(r:observe('onShowDialog',1,0,'Other_Player','','','Дней до конца бана: 3')==nil);r:observe('onConnectionLost');r:update();assert(#sent==1)")
 def test_confirmation_timeout(self):
  self.lua.execute("start();info();now=9;r:update();assert(r.pending==nil and #sent==2)")
 def test_script_compiles_and_manual_hook_only(self):
  self.lua.execute('assert(loadstring(...))',CODE)
  start=CODE.index("if name=='onSendCommand' and not self.outboundOwner and not self.offban.releasing then")
  self.assertIn('self.unbanReport:enqueue(text)',CODE[start:start+500])
if __name__=='__main__':unittest.main()
