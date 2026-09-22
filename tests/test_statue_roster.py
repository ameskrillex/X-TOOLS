"""Verify retained roles against the previous release's real statue layout."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / '.test-deps'))
from lupa.luajit21 import LuaRuntime


def layout(path):
    code = path.read_text(encoding='utf-8')
    marker = '    sources["modules/crimelegends.lua"] = function()\n'
    start = code.index(marker) + len(marker)
    end = code.index("local Scene=require 'crimelegends.scene'", start)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("integration={service=function()return {allowed=function()return true end}end}")
    lua.execute(code[start:end])
    # Factories are locals: return the actual generated scene from the same chunk.
    entries, signs = lua.execute(code[start:end] + "\nreturn require('crimelegends.scene').layout(require('crimelegends.roster'))")
    return {e.id: {'id': e.id, 'section': e.section, 'context': e.context,
                   'nick': e.person.nick, 'x': e.x, 'y': e.y, 'z': e.z,
                   'heading': e.heading, 'skin': e.person.skin} for e in entries.values()}


class StatueRosterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old = layout(ROOT / 'update/live/versions/3.5.209/X-TOOL.lua')
        cls.new = layout(ROOT / 'X-TOOL.lua')

    def test_only_requested_admin_roles_remain(self):
        expected = {key for key, e in self.old.items() if e['context'] != 'ADMINZONE'
                    or e['section'] in ('staff_heads', 'staff_deputies')
                    or e['section'].endswith('_chief')}
        self.assertEqual(set(self.new), expected)
        self.assertEqual(len(self.old) - len(self.new), 260)
        self.assertEqual(sum(e['context'] == 'ADMINZONE' for e in self.new.values()), 110)

    def test_retained_statues_keep_identity_skin_and_placement(self):
        for key, entry in self.new.items():
            with self.subTest(placement=key):
                self.assertEqual(entry, self.old[key])

    def test_multiple_roles_do_not_remove_retained_chief(self):
        old_roles = {key for key, e in self.old.items() if e['nick'] == 'Raidon_Tokosa'}
        new_roles = {key for key, e in self.new.items() if e['nick'] == 'Raidon_Tokosa'}
        self.assertGreater(len(old_roles), len(new_roles))
        self.assertEqual({self.new[key]['section'] for key in new_roles}, {'staff_mafia_chief'})


if __name__ == '__main__':
    unittest.main(verbosity=2)
