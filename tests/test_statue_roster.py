"""The retired valley must not create NPCs or register navigation."""
from pathlib import Path
import unittest
CODE=(Path(__file__).resolve().parents[1]/'X-TOOL.lua').read_text('utf-8')
class LegendRemovalTests(unittest.TestCase):
    def test_no_statue_factories_or_runtime_modules(self):
        for symbol in ('crimelegends','legends_browser','legendsDirectory','teleportLegend','visitLegend'):
            self.assertNotIn(symbol,CODE)
    def test_adminzone_and_checker_remain(self):
        self.assertIn("self:load('adminzone','adminzone.lua')",CODE)
        self.assertIn('sources["modules/adm.lua"]',CODE)
        self.assertIn('integration.enter=function() return move(true) end',CODE)
if __name__=='__main__':unittest.main(verbosity=2)
