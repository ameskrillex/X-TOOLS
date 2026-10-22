from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
for p in (ROOT.parent/'.test-deps',ROOT.parent/'tools/deps'):sys.path.insert(0,str(p))
from lupa.luajit21 import LuaRuntime
CODE=(ROOT/'X-TOOL.lua').read_text('utf8')
def module(name):
    marker='    sources["'+name+'"] = function()\n';a=CODE.index(marker)+len(marker)
    return CODE[a:CODE.index('\n    end\n    sources[',a)]
class Contexts(unittest.TestCase):
    def test_mode_matrix(self):
        l=LuaRuntime();l.globals().K=l.execute(module('keybinds.lua'))
        l.execute("""
            local pairs={{'airbreak_forward','observation_up_ws'}, {'airbreak_ground','airbreak_car_down'},
                {'matrix_jump','speed_boost'},{'matrix_jump','airbreak_up'},{'previous','observation_left'}}
            for _,p in ipairs(pairs)do assert(not K.overlaps({},p[1],p[2]));assert(not K.overlaps({},p[2],p[1]))end
            assert(K.overlaps({},'airbreak_forward','airbreak_back'))
            assert(K.overlaps({},'menu','airbreak_forward'))
            assert(K.overlaps({},'clickwarp','observation_left'))
        """)
    def test_dot_prefix(self):
        l=LuaRuntime();c=l.execute(module('command_layout.lua'))
        self.assertEqual(c.convert('.фты 7 Текст',True),'/ans 7 Текст')
        self.assertEqual(c.convert('.ans 7 test'),'/ans 7 test')
        for raw in ['...','..hello','.5','./path','text.hello']:self.assertEqual(c.convert(raw),raw)
