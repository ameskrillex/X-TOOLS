from pathlib import Path
import sys,unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'tools/deps'))
from lupa.luajit21 import LuaRuntime
CODE=(ROOT/'X-TOOL.lua').read_text('utf8')
class OnlineAccounts(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime()
  self.lua.execute('''
   now=0;checks=0;players={[0]='Local_Admin',[7]='Test_Player'};PLAYER_PED=1
   os.clock=function()return now end
   function getGameTimer()return now*1000 end
   function sampGetGamestate()return 3 end
   function normalize_identity(s)return tostring(s or ''):lower()end
   function strip_color_tags(s)return s end
   function cp1251_to_utf8(s)return s end
   function sampGetPlayerIdByCharHandle()return true,0 end
   function sampGetPlayerNickname(id)return players[id]end
   function sampIsPlayerConnected(id)checks=checks+1;return players[id]~=nil end
  ''')
  a=CODE.index('local online_accounts =');z=CODE.index('\nlocal function pump_query_queue',a)
  self.lua.execute(CODE[a:z])
 def test_status_cache_and_reused_id(self):
  self.lua.execute('''
   assert(get_online_player_id_for_account('test_PLAYER')==7)
   assert(get_online_player_id_for_account('Local_Admin')==0)
   local n=checks
   for i=1,100 do assert(get_online_player_id_for_account('Test_Player')==7)end
   assert(checks-n==100,'Rescanned full online list for every row')
   players[7]='Other_Player';assert(get_online_player_id_for_account('Test_Player')==nil)
   now=1.1;assert(get_online_player_id_for_account('Other_Player')==7)
   players[7]=nil;assert(get_online_player_id_for_account('Other_Player')==nil)
   players[8]='New_Player';now=2.2;assert(get_online_player_id_for_account('New_Player')==8)
  ''')
 def test_all_account_tables_use_green_id_without_changing_action_target(self):
  self.lua.execute('''
   View={};function get_account_offst_lookup()end
   function get_account_ban_lookup()return {is_banned=true,days_left='3',admin='Admin',reason='reason'}end
   function View.rowActions(account)actionTarget=account;return {}end
   function View.openPreview(kind,account)selected=account end
   function View.ui()return {table=function(id,title,cols,rows)result=rows end}end
  ''')
  a=CODE.index('function View.accountTable(');z=CODE.index('\nfunction View.logTable',a)
  self.lua.execute(CODE[a:z])
  self.lua.execute('''
   for _,saved in ipairs({false,true})do
    View.accountTable({'Test_Player'},'test','title',{{account='Test_Player',ip='192.0.2.1'}},saved)
    assert(result[1][1].text=='Test_Player [ID: 7]' and result[1][1].tone=='good')
    result[1][1].click();assert(selected=='Test_Player' and actionTarget=='Test_Player')
   end
   players[7]=nil
   View.accountTable({'Test_Player'},'test','title',{},false)
   assert(result[1][1].text=='Test_Player' and result[1][1].tone=='alert')
  ''')
if __name__=='__main__':unittest.main()
