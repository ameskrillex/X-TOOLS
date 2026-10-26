from pathlib import Path
import sys,unittest,re
ROOT=Path(__file__).resolve().parents[1]
for p in (ROOT.parent/'tools/deps',ROOT.parent/'.test-deps'):sys.path.insert(0,str(p))
from lupa.luajit21 import LuaRuntime
CODE=(ROOT/'X-TOOL.lua').read_text('utf8')
def module(name):
 marker='    sources["'+name+'"] = function()\n';a=CODE.index(marker)+len(marker)
 return CODE[a:CODE.index('\n    end\n    sources[',a)]
class SkinIds(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime();self.lua.globals().Skin=self.lua.execute(module('automatic_skin.lua'))
 def test_future_ids_and_invalid_values(self):
  self.lua.execute('''
   for _,id in ipairs({0,74,230,311,15400,15452,15453,15462,15463,15467,99999,2147483648})do assert(Skin.validId(id))end
   for _,id in ipairs({-1,1.5,math.huge,-math.huge,0/0,'15400',false})do assert(not Skin.validId(id))end
   assert(not Skin.validId(nil))
  ''')
 def test_automatic_issue_preserves_ids(self):
  self.lua.execute('''
   local selected=15467;local now=0;sent={}
   local rt={api={PLAYER_PED=1,sampGetGamestate=function()return 3 end,sampIsLocalPlayerSpawned=function()return true end,
    doesCharExist=function()return true end,isCharDead=function()return false end,getCharModel=function()return 230 end,
    getGameTimer=function()return now end,sampGetPlayerIdByCharHandle=function()return true,7 end},modules={},access={can=function()return true end},
    send=function(_,owner,method,command)sent[#sent+1]=command end}
   local auto=Skin.new(rt,function()return true,selected end)
   for _,id in ipairs({15400,15452,15453,15462,15463,15467,99999,2147483648})do
    selected=id;now=now+3001;auto:update();assert(sent[#sent]=='/skin 7 '..string.format('%.0f',id))
   end
   local n=#sent;selected=-1;now=now+3001;auto:update();assert(#sent==n)
  ''')
 def test_radius_commands_accept_launcher_ids_and_reject_malformed(self):
  prefix='''
   local singleSkinBatchActive=false;local alternatingSkinBatchActive=false
   integrationRuntime={service=function()return Skin end}
   function currentAdminLevel()return 5 end
   function cp1251(s)return s end
   function message(s)lastMessage=s end
   function sampGetMaxPlayerId()return 7 end
  '''
  funcs='\n'.join(re.search(r'^function '+name+r'\([^\n]*\n.*?^end\n',CODE,re.M|re.S).group() for name in ('rskin','rskins'))
  self.lua.execute(prefix+funcs+'''
   rskin('15467 15');assert(singleSkinBatchActive and rskin_skin==15467)
   rskin('');assert(not singleSkinBatchActive)
   for _,args in ipairs({'-1 15','1.5 15','15467 15 junk'})do rskin(args);assert(not singleSkinBatchActive)end
   rskins('15400 99999 15');assert(alternatingSkinBatchActive and rskin_skin==15400 and rskin_skin2==99999)
   rskins('');assert(not alternatingSkinBatchActive)
   rskins('15467 -1 15');assert(not alternatingSkinBatchActive)
  ''')
 def test_apply_uses_shared_validator(self):
  a=CODE.index('local appliedSkinDigits =');b=CODE.index('sampTextdrawIsExists(420)',a)
  block=CODE[a:b]
  self.assertIn(".validId(appliedSkinId)",block)
  self.assertNotIn('311',block)
  self.assertIn('"/skin %i %.0f"',block)
if __name__=='__main__':unittest.main()

