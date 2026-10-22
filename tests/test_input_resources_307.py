from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
for path in (ROOT.parent/'.test-deps',ROOT.parent/'tools/deps'):
    sys.path.insert(0,str(path))
from lupa.luajit21 import LuaRuntime
CODE=(ROOT/'X-TOOL.lua').read_text('utf8')
def source(name):
    marker='    sources["'+name+'"] = function()\n'
    a=CODE.index(marker)+len(marker)
    return CODE[a:CODE.index('\n    end\n    sources[',a)]
class InputResources(unittest.TestCase):
    def test_layout_preserves_arguments_and_supports_native_bytes(self):
        lua=LuaRuntime(encoding=None)
        module=lua.execute(source('command_layout.lua').encode())
        convert=module[b'convert']
        for before,after in [('/фты','/ans'),('/ФТЫ','/ans'),('/рудз','/help'),('/РЁ','/h`')]:
            for enc,utf8 in [('cp1251',False),('utf8',True)]:
                tail=' 7 Ник_Игрока Причина /ФТЫ'
                self.assertEqual(convert((before+tail).encode(enc),utf8),(after+tail).encode(enc))
        for raw in ['/ans 7 фты','/','hello /фты']:
            self.assertEqual(convert(raw.encode('cp1251')),raw.encode('cp1251'))
    def test_font_selection_never_appends_to_live_atlas(self):
        lua=LuaRuntime()
        lua.globals().T=lua.execute(source('typography.lua'))
        lua.execute("""
            local added,rebuilt=0,0
            local atlas={GetGlyphRangesCyrillic=function()return {}end,
                AddFontFromFileTTF=function()added=added+1;return {}end}
            local gui={GetIO=function()return {Fonts=atlas}end,
                ImFontAtlasGlyphRangesBuilder=function()return {AddRanges=function()end,AddText=function()end,BuildRanges=function()return {}end}end,
                RebuildFonts=function()rebuilt=rebuilt+1 end}
            local face=T.new('x',{doesFileExist=function()return true end,getFolderPath=function()return 'fonts'end})
            assert(face:load(gui));local initial=face:get(16)
            for n=1,200 do face.preference=n%11+1;assert(face:load(gui))end
            assert(added==22 and rebuilt==1 and initial==face:get(16))
        """)
    def test_theme_and_font_pending_until_next_launch(self):
        lua=LuaRuntime();lua.globals().P=lua.execute(source('preferences.lua'))
        lua.execute("""
            local data={main={font=1,themeStyle=4}}
            local storage={path=function()return 'test'end,loadIni=function()return data end,saveIni=function()return true end}
            local p=P.new(storage);p.data.main.pendingThemeStyle=0;p.data.main.pendingFont=3;p:save()
            assert(p.data.main.themeStyle==4 and p.data.main.font==1)
            local next=P.new(storage)
            assert(next.data.main.themeStyle==0 and next.data.main.font==3)
        """)
if __name__=='__main__':unittest.main()
