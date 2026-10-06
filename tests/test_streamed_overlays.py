from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / '.test-deps'))
from lupa.luajit21 import LuaRuntime

CODE = (ROOT / 'X-TOOL.lua').read_text('utf-8')

def module(name):
    marker = '    sources["' + name + '"] = function()\n'
    start = CODE.index(marker) + len(marker)
    return CODE[start:CODE.index('\n    end\n    sources[', start)]

class StreamedOverlayTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().stream = self.lua.execute(module('streamed_players.lua'))
        self.lua.execute('''
            now=0;pool={10,20,90};scans=0;connected={[0]=true,[2]=true,[9]=true,[999]=true}
            function getGameTimer()return now end
            function getAllChars()scans=scans+1;return pool end
            function doesCharExist(p)return p~=0 end
            function sampGetPlayerIdByCharHandle(p)return true,({[10]=0,[20]=2,[90]=9})[p]end
            function sampIsPlayerConnected(id)return connected[id]==true end
            function sampGetMaxPlayerId()error('Full server traversal is forbidden')end
            integration={service=function()return stream end};sampev={}
        ''')
        capture = module('modules/capture.lua')
        start = capture.index('local APP = {session = 0}')
        end = capture.index('function APP.isDiscordWebhook', start)
        self.lua.execute(capture[start:end]+'\n_G.APP=APP')
        self.capture = capture

    def test_pool_bootstrap_order_and_no_per_frame_scan(self):
        self.lua.execute('''
            assert(table.concat(APP.renderPlayerIds(),',')=='0,2,9')
            for i=1,120 do APP.renderPlayerIds()end
            assert(scans==1)
            now=1000;pool={10,90}
            assert(table.concat(APP.renderPlayerIds(),',')=='0,9')
            assert(scans==2)
        ''')

    def test_early_stream_in_out_quit_and_reused_id(self):
        self.lua.execute('''
            APP.renderPlayerIds();APP.streamedPlayers:add(7)
            now=1000;assert(APP.streamedPlayers:list()[7])
            APP.streamedPlayers:remove(7);assert(not APP.streamedPlayers:list()[7])
            APP.streamedPlayers:add(7);assert(APP.streamedPlayers:list()[7])
            now=2100;assert(not APP.streamedPlayers:list()[7])
            APP.streamedPlayers:remove(2);assert(not APP.streamedPlayers:list()[2])
            APP.streamedPlayers:reset();pool={90}
            assert(table.concat(APP.renderPlayerIds(),',')=='9')
            now=1;pool={20};assert(table.concat(APP.renderPlayerIds(),',')=='2')
        ''')

    def test_nametags_keep_local_exclusion_order_and_guards(self):
        self.lua.execute('''
            safe=true;enabled=true;spawned=true;drawn={};PLAYER_PED=10
            DATA={customNametags={font=true}}
            function isSafeGameRenderState()return safe end
            function sampGetGamestate()return 3 end
            function sampIsLocalPlayerSpawned()return spawned end
            function getCharCoordinates()return 1,2,3 end
            APP.isCustomNametagsEnabled=function()return enabled end
            APP.ensureCustomNametagRuntimePatches=function()end
            APP.renderSingleCustomNametag=function(id)table.insert(drawn,id)end
        ''')
        start=self.capture.index('function APP.renderCustomNametagsFrame()')
        end=self.capture.index('function APP.setCustomNametagsState', start)
        self.lua.execute(self.capture[start:end])
        self.lua.execute('''
            APP.renderCustomNametagsFrame();assert(table.concat(drawn,',')=='2,9')
            drawn={};safe=false;APP.renderCustomNametagsFrame();assert(#drawn==0)
            safe=true;enabled=false;APP.renderCustomNametagsFrame();assert(#drawn==0)
            enabled=true;spawned=false;APP.renderCustomNametagsFrame();assert(#drawn==0)
        ''')

    def test_skeleton_family_priority_and_missing_ped(self):
        self.lua.execute('''
            bit=require('bit');drawn={};imgui={};visual={style=5,priority=0}
            integration.hudActive=function()return true end
            APP.skeletonVisual=function()return visual end
            integration.service=function()return {
                frame=function(g,w,h,fn)fn({})end,
                draw=function(g,points)table.insert(drawn,points.id)end}end
            function getScreenResolution()return 800,600 end
            function sampGetPlayerNickname(id)return id end
            integration.familyHighlight=function(id)return id==2 end
            function sampGetCharHandleBySampPlayerId(id)return id~=0,id end
            integration.familyBones=function(ped)return {id=ped}end
            function sampGetPlayerColor()return 0xFFFFFFFF end
        ''')
        start=self.capture.index('integration.drawHud=function()')
        self.lua.execute(self.capture[start:])
        self.lua.execute('''
            integration.drawHud();assert(table.concat(drawn,',')=='9')
            drawn={};visual.priority=1;integration.drawHud()
            assert(table.concat(drawn,',')=='2,9')
            drawn={};connected[9]=false;integration.drawHud()
            assert(table.concat(drawn,',')=='2')
        ''')

    def test_bundle_compiles(self):
        self.lua.execute('assert(loadstring(...))', CODE)

if __name__ == '__main__':
    unittest.main()
