"""Exercise texture lifetime and the actual legend scene with tracked resources."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / '.test-deps'))
from lupa.luajit21 import LuaRuntime
CODE = (ROOT / 'X-TOOL.lua').read_text(encoding='utf-8')


def module(name):
    marker = '    sources["' + name + '"] = function()\n'
    start = CODE.index(marker) + len(marker)
    return CODE[start:CODE.index('\n    end\n    sources[', start)]


class ArtworkTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.globals().Art = self.lua.execute(module('art.lua'))
        self.lua.execute('''
            now=0;created=0;freed=0;alive={};fail=false
            g={CreateTextureFromMemory=function()
                created=created+1;alive[created]=true;return created end,
                ReleaseTexture=function(id)
                    if fail then return false end
                    assert(alive[id],'double release');alive[id]=nil;freed=freed+1
                end}
            api={getGameTimer=function()return now end,require=require,
                io={open=function()return {read=function()return 'png fixture' end,close=function()end}end}}
            art=Art.new(g,'resources',api)
        ''')

    def test_old_theme_freed_active_texture_kept_and_expired_reloads(self):
        self.lua.execute('''
            local old=art:get('theme-ruby-background')
            now=10000;local active=art:get('theme-jade-background')
            now=15000;Art.collect(now)
            assert(not alive[old.texture] and alive[active.texture] and freed==1)
            local reloaded=art:get('theme-ruby-background')
            assert(reloaded.texture~=old.texture and created==3)
            assert(art:get('theme-jade-background')==active and created==3)
        ''')

    def test_get_never_releases_draw_list_texture(self):
        self.lua.execute('''
            local first=art:get('hero');now=20000
            art:get('theme-jade-logo');assert(freed==0 and alive[first.texture])
            Art.collect(now);assert(freed==1)
        ''')

    def test_idle_cleanup_covers_separate_module_caches(self):
        self.lua.execute('''
            local other=Art.new(g,'resources',api)
            art:get('hero');other:get('observation')
            now=15000;Art.collect(now);assert(freed==2 and next(alive)==nil)
            art:get('hero');other:get('observation')
            Art.shutdownAll();assert(freed==4 and next(alive)==nil)
            art:shutdown();other:shutdown();assert(freed==4)
        ''')

    def test_clock_wrap_and_failed_release_preserve_tracking(self):
        self.lua.execute('''
            now=100000;local item=art:get('hero')
            now=0;Art.collect(now);assert(freed==0)
            now=15000;fail=true;Art.collect(now);assert(alive[item.texture])
            fail=false;Art.collect(now);assert(freed==1)
        ''')


class LegendBudgetTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.execute("integration={service=function()return {allowed=function()return true end}end}")
        body = module('modules/crimelegends.lua')
        self.lua.execute(body[:body.index("local Scene=require 'crimelegends.scene'")] + '''
            Scene=require 'crimelegends.scene';roster=require 'crimelegends.roster'
            live={};requests=0;releases=0;created=0;removed=0;loaded=true
            api={exists=function(id)return live[id]end,
                remove=function(id)assert(live[id]);live[id]=nil;removed=removed+1 end,
                request=function()requests=requests+1 end,
                release=function()releases=releases+1 end,
                loaded=function()return loaded end,
                spawn=function()created=created+1;live[created]=true;return created end,
                settle=function()return true end}
            scene=Scene.new(roster,api)
        ''')

    def test_twenty_nearest_statues_without_stationary_churn(self):
        self.lua.execute('''
            for i=1,600 do scene:update(i*.11,-750,500,1372,100,'ADMINZONE') end
            assert(scene.count==20 and created==20 and removed==0)
            assert(requests==releases and scene.pending==nil)
            scene:update(70,0,0,0,100,'OUTSIDE')
            assert(scene.count==0 and removed==20 and next(live)==nil)
        ''')

    def test_distant_statues_no_longer_preloaded(self):
        self.lua.execute('''
            local e=scene.entries[1];scene.entries={e}
            scene:update(1,e.x+200,e.y,e.z,100,e.context)
            assert(requests==0 and created==0)
            scene:update(2,e.x+100,e.y,e.z,100,e.context)
            assert(created==1)
            scene:update(3,e.x+200,e.y,e.z,100,e.context)
            assert(removed==1 and scene.count==0)
        ''')

    def test_leaving_with_pending_model_releases_request(self):
        self.lua.execute('''
            loaded=false;local e=scene.entries[1];scene.entries={e}
            scene:update(1,e.x,e.y,e.z,100,e.context)
            assert(requests==1 and scene.pending)
            scene:clear();scene:clear()
            assert(releases==1 and scene.pending==nil and next(live)==nil)
        ''')


if __name__ == '__main__':
    unittest.main(verbosity=2)
