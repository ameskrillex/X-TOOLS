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

    def test_theme_textures_survive_idle_and_reopening(self):
        self.lua.execute('''
            local old=art:get('theme-ruby-background')
            now=10000;local active=art:get('theme-jade-background')
            now=3600000
            assert(alive[old.texture] and alive[active.texture] and freed==0)
            local reloaded=art:get('theme-ruby-background')
            assert(reloaded==old and created==2)
            assert(art:get('theme-jade-background')==active and created==2)
        ''')

    def test_get_never_releases_draw_list_texture(self):
        self.lua.execute('''
            local first=art:get('hero');now=20000
            art:get('theme-jade-logo');assert(freed==0 and alive[first.texture])
            assert(art:get('hero')==first and freed==0 and created==2)
        ''')

    def test_shutdown_covers_separate_module_caches_once(self):
        self.lua.execute('''
            local other=Art.new(g,'resources',api)
            art:get('hero');other:get('observation')
            now=15000;assert(freed==0)
            Art.shutdownAll();assert(freed==2 and next(alive)==nil)
            Art.shutdownAll();art:shutdown();other:shutdown();assert(freed==2)
        ''')

    def test_timer_no_longer_controls_texture_lifetime(self):
        self.lua.execute('''
            now=100000;local item=art:get('hero')
            now=0;assert(art:get('hero')==item and freed==0)
            assert(Art.collect==nil)
        ''')
        self.assertNotIn("service('art.lua').collect", module('runtime.lua'))



if __name__ == '__main__':
    unittest.main(verbosity=2)
