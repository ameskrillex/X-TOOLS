from pathlib import Path
import sys,unittest
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT.parent/'tools/deps'))
from lupa.luajit21 import LuaRuntime
code=(ROOT/'X-TOOL.lua').read_text('utf8');marker='    sources["radius_spawn.lua"] = function()\n';a=code.index(marker)+len(marker);body=code[a:code.index('\n    end\n    sources[',a)]
class Spawn(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime();self.l.globals().M=self.l.execute(body)
  self.l.execute('''names={[0]='Self',[1]='One',[2]='Two'};nearby={[0]=true,[1]=true,[2]=true};sent={};delays={};messages={};rev=1;allowed=true;connected=true
  c=M.new({allowed=function()return allowed end,revision=function()return rev end,connected=function()return connected end,selfId=function()return 0 end,maxId=function()return 2 end,nickname=function(id)return names[id]end,near=function(id)return nearby[id]end,message=function(s)table.insert(messages,s)end,send=function(s)table.insert(sent,s)end,wait=function(ms)table.insert(delays,ms);coroutine.yield()end,thread=function(fn)co=coroutine.create(fn);assert(coroutine.resume(co))end})
  function step()assert(coroutine.resume(co))end''')
 def test_queue(self):self.l.execute("c:command(' 25 ');assert(sent[1]=='/spawn 1');step();assert(sent[2]=='/spawn 2');step();assert(not c.active and #sent==2 and delays[1]==3000)")
 def test_cancel(self):self.l.execute("c:command('25');c:command('');step();assert(#sent==1 and not c.active)")
 def test_reused_id(self):self.l.execute("c:command('25');names[2]='Replacement';step();assert(#sent==1 and not c.active)")
 def test_left_radius(self):self.l.execute("c:command('25');nearby[2]=false;step();assert(#sent==1)")
 def test_session(self):self.l.execute("c:command('25');rev=2;step();assert(#sent==1 and not c.active)")
 def test_permission(self):self.l.execute("c:command('25');allowed=false;step();assert(#sent==1 and not c.active)")
 def test_disconnected(self):self.l.execute("c:command('25');connected=false;step();assert(#sent==1 and not c.active)")
 def test_invalid(self):self.l.execute("for _,s in ipairs({'','2','81','nan','3.5','25 x'})do c:command(s)end;assert(#sent==0 and not c.active)")
 def test_compile(self):self.l.execute('assert(loadstring(...))',code)
if __name__=='__main__':unittest.main()
