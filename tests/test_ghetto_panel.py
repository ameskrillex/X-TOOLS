from pathlib import Path
import sys,unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'.test-deps'))
from lupa.luajit21 import LuaRuntime
CODE=(ROOT/'X-TOOL.lua').read_text('utf-8')
def module(name):
 s=CODE.index('    sources["'+name+'"] = function()\n')
 s=CODE.index('\n',s)+1
 return CODE[s:CODE.index('\n    end\n    sources[',s)]
class GhettoPanel(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.execute('''
   local original=require
   u8=setmetatable({decode=function(_,s)return s end},{__call=function(_,s)return s end})
   events={};sent={};enabled=true;level=3;connected=true;tick=0;keys={};saved=0
   function require(n)
    if n=='bit'then return original(n)end
    if n=='encoding'then return {UTF8=u8}end
    if n:find('events',1,true)then return events end
    return {}
   end
   integration={storage={path=function()return 'cfg'end,loadIni=function(_,d)
    if d.features then d.features.enabled=enabled else d.main.enabled=enabled end;return d end,
    saveIni=function()saved=saved+1;return true end},
    access={require=function(_,n)return level>=n end,can=function(_,n)return level>=n end},
    commandMinimum=function(s)return s:find('/jail',1,true)and 2 or 3 end,
    featureAllowed=function()return enabled end,windowOpen=function()return false end,
    preferences={data={main={medkitMode='ghetto'}}},message=function()end,
    keys={register=function()end,down=function(_,k)return keys[k]or false end,name=function(_,k)return k end}}
   function getWorkingDirectory()return ''end
   function sampIsPlayerConnected()return connected end
   function sampGetPlayerNickname()return 'Test_Player'end
   function sampGetPlayerColor()return -16738048 end
   function sampAddChatMessage()end
   function sampProcessChatInput(s)sent[#sent+1]=s end
   sampSendChat=sampProcessChatInput
   function getGameTimer()return tick end
   function isSampAvailable()return true end
   function sampGetGamestate()return 3 end
   function sampGetCharHandleBySampPlayerId()return true,123 end
   function doesCharExist()return true end
   function isCharInAnyCar()return false end
   function isCharDead()return false end
   function sampIsChatInputActive()return false end
   sampIsDialogActive=isCharDead;isPauseMenuActive=isCharDead;sampIsScoreboardOpen=isCharDead
   isSampfuncsConsoleActive=isCharDead;sampIsCursorActive=isCharDead
  ''')
 def test_gang_commands_and_permissions(self):
  self.lua.globals().gang=self.lua.execute(module('modules/gang.lua')+'\nreturn {jail=handle_gj_command,warn=handle_gw_command,ban=handle_gb_command}')
  self.lua.execute('''
   gang.jail('5 30');assert(sent[1]=='/jail 5 30 Нарушение правил /capture [GROVE]')
   gang.warn('5');assert(sent[2]=='/warn 5 Нарушение правил /capture [GROVE]')
   gang.ban('5 3');assert(sent[3]=='/ban 5 3 Использование читов [GROVE]')
   level=1;gang.jail('5 30');assert(sent[4]:sub(1,9)=='/a /jail ')
   connected=false;gang.warn('5');assert(#sent==4)
   gang.ban('5 0');gang.jail('invalid');assert(#sent==4)
  ''')
 def test_gang_disabled(self):
  self.lua.execute('enabled=false')
  self.lua.globals().gang=self.lua.execute(module('modules/gang.lua')+'\nreturn handle_gw_command')
  self.lua.execute("gang('5');assert(#sent==0)")
 def test_medkit_detection_follow_and_warn(self):
  self.lua.globals().medkit=self.lua.execute(module('modules/stopsbiv.lua')+'\nreturn {step=step}')
  self.lua.execute('''
   events.onPlayerChatBubble(5,-1721303041,20,2000,'+30 HP')
   tick=1200;assert(events.onPlayerSync(5,{animationId=0})==nil);assert(#sent==0)
   keys.medkit_follow=true;medkit.step();assert(sent[1]=='/sp 5')
   keys.medkit_warn=true;medkit.step();assert(#sent==1)
   keys.medkit_warn=false;medkit.step();events.onSpectatePlayer(5)
   keys.medkit_warn=true;medkit.step();assert(#sent==2 and sent[2]:match('^/warn 5 '))
   medkit.step();assert(#sent==2)
   events.onPlayerQuit(5);keys.medkit_follow=false;medkit.step();keys.medkit_follow=true;medkit.step();assert(#sent==2)
  ''')
 def test_medkit_complete_animation_and_disabled(self):
  self.lua.globals().medkit=self.lua.execute(module('modules/stopsbiv.lua')+'\nreturn {step=step}')
  self.lua.execute('''
   events.onPlayerChatBubble(5,-1721303041,20,2000,'+30 HP')
   events.onPlayerSync(5,{animationId=1157});tick=5100
   events.onPlayerSync(5,{animationId=0});keys.medkit_follow=true;medkit.step();assert(#sent==0)
   enabled=false;events.onPlayerChatBubble(5,-1721303041,20,2000,'+30 HP')
   tick=7000;events.onPlayerSync(5,{animationId=0});medkit.step();assert(#sent==0)
  ''')
 def test_top_preview_does_not_change_real_stats(self):
  s=CODE.index('function buildCaptureTopOverlayEntries()');e=CODE.index('\nfunction drawCaptureTopOverlayHud()',s)
  self.lua.execute('STATE={capture={active=false}};DATA={overlayTestActive=false,captureTopOverlayEntries={{kills=99}}}')
  self.lua.execute(CODE[s:e])
  self.lua.execute('''
   assert(#buildCaptureTopOverlayEntries()==0);DATA.overlayTestActive=true
   assert(#buildCaptureTopOverlayEntries()==6);assert(DATA.captureTopOverlayEntries[1].kills==99)
   STATE.capture.active=true;assert(buildCaptureTopOverlayEntries()==DATA.captureTopOverlayEntries)
  ''')
if __name__=='__main__':unittest.main()
