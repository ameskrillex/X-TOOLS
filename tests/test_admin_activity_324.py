from pathlib import Path
import sys,unittest
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT.parent/'tools/deps'))
from lupa.luajit21 import LuaRuntime
code=(ROOT/'X-TOOL.lua').read_text('utf8');m='    sources["admin_activity.lua"] = function()\n';a=code.index(m)+len(m);body=code[a:code.index('\n    end\n    sources[',a)]
class Activity(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime();self.l.globals().M=self.l.execute(body)
  self.l.execute("now=0;enabled=true;ready=true;sent=0;api={getGameTimer=function()return now end,sampGetGamestate=function()return 3 end};o=M.new(api,function(s)assert(s=='/admins');sent=sent+1;o:manual(s)end,function()return enabled end,function()return ready end)")
 def test_cadence_auto_and_unrelated_chat(self):
  self.l.execute("o:update();assert(sent==0);now=15000;o:update();assert(sent==1);assert(o:observe('Админы онлайн:')==false);assert(o:observe('Admin_Name[7] (4 lvl) Voice > /sp 253')==false);assert(o:label('Admin_Name',7)=='{9299A6}| {68CFFF}sp -> [253]');assert(o:observe('[A] Other[2]: hello')==nil);assert(o:observe('Гл. администратор Voice')==false);now=29999;o:update();assert(sent==1);now=30000;o:update();assert(sent==2)")
 def test_manual_visible_and_statuses(self):
  self.l.execute("now=15000;o:update();o:manual('/admins');assert(o:observe('Админы онлайн:')==nil);assert(o:observe('Admin_Name[7] (4 lvl) Voice AFK')==nil);assert(o:label('admin_name',7)=='{FF5964}[AFK]');o:observe('Admin_Name[7] (4 lvl) (невидимка)');assert(o:label('Admin_Name',7)=='{C69CFF}[INV]');assert(o:label('Admin_Name',8)==nil)")
 def test_expiry_disable_and_timeout(self):
  self.l.execute("o:observe('Admin_Name[7] (4 lvl) Voice');now=36000;assert(o:label('Admin_Name',7)==nil);enabled=false;o:update();assert(sent==0);enabled=true;now=51000;o:update();assert(sent==1);now=57000;assert(o:observe('Админы онлайн:')==nil);o:reset();assert(o:label('Admin_Name',7)==nil)")
 def test_poll_sender_does_not_touch_chat_input(self):
  a=code.index("adminActivity=integration.service('admin_activity.lua').new")
  z=code.index('integration.update=function()',a)
  self.l.execute("chatOpen=true;draft='unfinished message';sent=0;config={checker={admin_activity_poll=true}};function sampProcessChatInput()error('chat input must not be used')end;function sampSendChat(s)assert(s=='/admins');sent=sent+1 end;function utf8_to_cp1251(s)return s end;function sampIsLocalPlayerSpawned()return true end;function isPauseMenuActive()return false end;integration={service=function()return {new=function(_,send)send('/admins');return {}end}end}")
  self.l.execute(code[a:z])
  self.l.execute("assert(sent==1 and chatOpen and draft=='unfinished message')")
 def test_target_name_and_reused_id(self):
  self.l.execute("players={[253]='Target_Name'};api.sampIsPlayerConnected=function(id)return players[id]~=nil end;api.sampGetPlayerNickname=function(id)return players[id]end;o:observe('Admin_Name[7] (4 lvl) > /sp 253');assert(o:label('Admin_Name',7)=='{9299A6}| {68CFFF}sp -> Target_Name [253]');players[253]='Other_Name';assert(o:label('Admin_Name',7)=='{9299A6}| {68CFFF}sp -> [253]')")
 def test_no_online_and_compact_badges(self):
  self.l.execute("o:observe('Admin_Name[7] (4 lvl) Voice');assert(o:label('Admin_Name',7)=='');o:observe('Admin_Name[7] (4 lvl) AFK (невидимка) > /sp 253');assert(o:label('Admin_Name',7)=='{FF5964}[AFK] {C69CFF}[INV] {9299A6}| {68CFFF}sp -> [253]')")
 def test_head_admin_before_players_from_chatlog(self):
  self.l.execute("now=15000;o:update();assert(o:observe('Админы онлайн:')==false);assert(o:observe('Гл. администратор{FF0000} AFK')==false);assert(o:observe('Stan_Lamare[65] (4 lvl) {9999ff}Voice{FF0000} AFK')==false);assert(o:observe('Barbara_Cassini[184] (4 lvl) {9999ff}Voice{00CC33} > /sp 281')==false);assert(o:observe('Mia_Granados[261] (3 lvl)')==false);assert(o:label('Stan_Lamare',65)=='{FF5964}[AFK]');assert(o:observe('[A] Other_Admin[5]: hello')==nil);now=17000;o:update();assert(o.pending==nil);o:manual('/admins');assert(o:observe('Админы онлайн:')==nil);assert(o:observe('Гл. администратор AFK')==nil);assert(o:observe('Mia_Granados[261] (3 lvl)')==nil)")
 def test_compile(self):
  self.l.execute('assert(loadstring(...))',code)
if __name__=='__main__':unittest.main()
