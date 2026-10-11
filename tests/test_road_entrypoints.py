from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'.test-deps'))
from lupa.luajit21 import LuaRuntime
CODE=(ROOT/'X-TOOL.lua').read_text('utf-8')

def module(name):
    marker='    sources["'+name+'"] = function()\n'
    start=CODE.index(marker)+len(marker)
    return CODE[start:CODE.index('\n    end\n    sources[',start)]

class RoadEntrypoints(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            local ffi=require 'ffi'
            ffi.cdef('struct PlayerSyncData { struct {float x,y,z;} position; };')
            local original=require
            function require(name)
                if name=='lib.sampfuncs'then return {PACKET_PLAYER_SYNC=207,HIGH_PRIORITY=1,UNRELIABLE_SEQUENCED=7}end
                if name=='samp.synchronization'then return {}end
                if name=='samp.events'then return events end
                return original(name)
            end
            events={};observed={id=42};calls={};jobs={};owner=nil;connected=true;nickname='Target_Test';PLAYER_PED=1
            integration={access={require=function()return true end,can=function()return true end},
                preferences={data={main={roadFollowup=true}}},message=function()end,
                observation=function()return observed end,releaseSpectateInput=function()end,commandOwner=function()return owner end}
            function sampRegisterChatCommand(_,fn)tr=fn end
            function isSampAvailable()return true end
            function sampGetGamestate()return 3 end
            function sampGetPlayerIdByCharHandle()return true,1 end
            function sampIsPlayerConnected()return connected end
            function sampGetPlayerNickname()return nickname end
            function sampGetCharHandleBySampPlayerId()return true,2 end
            function getActiveInterior()return 0 end
            function getCharCoordinates()return 10,20,30 end
            function getClosestStraightRoad()return 100,200,5 end
            function sampStorePlayerOnfootData()end
            function raknetNewBitStream()return 1 end
            function raknetBitStreamWriteInt8(_,id)assert(id==207)end
            function raknetBitStreamWriteBuffer(_,pointer)
                local p=ffi.cast('struct PlayerSyncData*',pointer)
                assert(p.position.x==100 and p.position.y==200)
            end
            function raknetSendBitStreamEx(_,priority,reliability,channel)
                assert(reliability==7 and channel==1);table.insert(calls,'position');return true
            end
            function raknetDeleteBitStream()end
            function sampSendChat(cmd)table.insert(calls,cmd)end
            lua_thread={create=function(fn)table.insert(jobs,fn)end}
            function wait(ms)assert(ms==350)end
            function drain()while #jobs>0 do table.remove(jobs,1)()end end
        ''')
        self.lua.execute(module('modules/road.lua'))

    def test_typed_command_only_moves_even_when_followup_enabled(self):
        self.lua.execute("tr('42');assert(#jobs==0);assert(#calls==2 and calls[1]=='position' and calls[2]=='/gethere 42 1')")

    def test_menu_dispatch_preserves_owner_and_followup(self):
        start=CODE.index('        invoke = function(name, args)')
        end=CODE.index('        squareWarningsEnabled',start)
        self.lua.execute('''
            function pack(...)return {n=select('#',...),...}end
            local self={invoke=function(_,name,args)assert(name=='tr');return tr(args)end}
            local m={id='menu'}
            integration.commandOwner=function()return self.outboundOwner end
            local bridge={
        '''+CODE[start:end]+'''}
            integration.invoke=bridge.invoke
            function release_input_capture()released=true end
            target_id=42
        ''')
        start=CODE.index("    elseif action == 'pull_from_water' then")
        start=CODE.index('\n',start)+1
        end=CODE.index("    elseif action == 'gethere' then",start)
        self.lua.execute(CODE[start:end])
        self.lua.execute("assert(released and #jobs==1);assert(integration.commandOwner()==nil);drain();assert(#calls==4 and calls[3]=='/slap 42' and calls[4]=='/sp 42')")

    def test_aegis_does_not_double_followup(self):
        self.lua.execute("owner='aegis';tr('42');assert(#jobs==0 and #calls==2)")

    def test_menu_setting_off(self):
        self.lua.execute("owner='menu';integration.preferences.data.main.roadFollowup=false;tr('42');assert(#jobs==0 and #calls==2)")

    def test_menu_followup_cancels_if_target_changes(self):
        self.lua.execute("owner='menu';tr('42');nickname='Other_Test';drain();assert(#calls==2)")

    def test_exit_or_switch_cancels_followup(self):
        for event in ["events.onSendCommand('/sp')", "events.onSendCommand('/sp 99')", "events.onTogglePlayerSpectating(false)", "events.onSpectatePlayer(42)", "events.onSpectateVehicle(10)", "observed=nil", "observed={id=99}"]:
            self.setUp()
            self.lua.execute("owner='menu';tr('42');"+event+";drain();assert(#calls==2)")

    def test_exit_between_slap_and_refresh(self):
        self.lua.execute("owner='menu';tr('42');local n=0;function wait()n=n+1;if n==2 then events.onSendCommand('/sp')end end;drain();assert(#calls==3 and calls[3]=='/slap 42')")

    def test_bundle_compiles(self):
        self.assertTrue(self.lua.eval('function(s)local f,e=loadstring(s);assert(f,e);return true end')(CODE))

if __name__=='__main__':unittest.main()
