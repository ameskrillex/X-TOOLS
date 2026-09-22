"""Regression tests for family requests, using the real bundled Lua modules."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / '.test-deps'))
from lupa.luajit21 import LuaRuntime

CODE = (ROOT / 'X-TOOL.lua').read_text(encoding='utf-8')


def module(name, code=CODE):
    marker = '    sources["' + name + '"] = function()\n'
    start = code.index(marker) + len(marker)
    return code[start:code.index('\n    end\n    sources[', start)]


class FamilyQuestionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.parser = self.lua.execute(module('family_question.lua'))

    def test_requests_with_explicit_id(self):
        requests = {
            '144 id family?': '144', '513 id family?': '513',
            'id 144 family?': '144', 'ID 144 FAMILY?': '144',
            '144 ID family': '144', '144 ид фама?': '144',
            'ИД 144 ФАМА?': '144', 'айди 144 в какой семье?': '144',
            '144 айди какая семья': '144', 'id: 144 family': '144',
            'id #144 family': '144', '0 id family': '0',
            '  144   id   family?! ': '144',
            '{FFFFFF}144 {FFCD00}id family?': '144',
        }
        for question, target in requests.items():
            with self.subTest(question=question):
                self.assertEqual(self.parser.parse(question), target)

    def test_existing_id_and_nickname_forms(self):
        requests = {
            '196 family': '196', '394 фама?': '394',
            '144 в какой фаме': '144', 'Player_Name family': 'Player_Name',
            'Player Name family?': 'Player_Name',
            'Player_Name[144] family': 'Player_Name',
            'Player Name (144) семья': 'Player_Name',
            '144_id family': '144_id', 'Id_Player family': 'Id_Player',
            'Player Id family': 'Player_Id', 'Id144 family': 'Id144',
            'id family': 'id', '144 id 196 family': '144_id_196',
        }
        for question, target in requests.items():
            with self.subTest(question=question):
                self.assertEqual(self.parser.parse(question), target)

    def test_custom_keywords_use_same_target_resolution(self):
        words = self.lua.table_from(['fama', 'вне кв'])
        self.assertEqual(self.parser.parse('144 id fama?', words), '144')
        self.assertEqual(self.parser.parse('id 144 вне кв', words), '144')

    def test_unrelated_reports_are_not_family_requests(self):
        for question in ('144 вне кв', '144 id dm', 'family', '144family',
                         '144 идите family',
                         'какая семья у игрока', '/ban 144 family'):
            with self.subTest(question=question):
                self.assertIsNone(self.parser.parse(question))

    def test_baseline_reproduces_synthetic_nickname(self):
        baseline = (ROOT / 'update/live/versions/3.5.206/X-TOOL.lua').read_text(encoding='utf-8')
        old = self.lua.execute(module('family_question.lua', baseline))
        self.assertEqual(old.parse('144 id family?'), '144_id')
        self.assertEqual(old.parse('id 144 family?'), 'id_144')

    def start_family_module(self):
        self.lua.globals().questionParser = self.parser
        self.lua.globals().reportReader = self.lua.execute(module('report_reader.lua'))
        self.lua.execute('''
            clock=0; sent={}; messages={}; commands={}; events={}; threads={}
            players={[42]='Report_Author',[43]='Second_Author',[144]='Target_Player',
                     [196]='Other_Player',[999]='Admin_Player'}
            local u8=setmetatable({decode=function(_,text)return text end},
                {__call=function(_,text)return text end})
            local access={revision=function()return 1 end,can=function()return true end,
                require=function()return true end}
            integration={
                featureAllowed=function()return true end,access=access,
                storage={path=function(_,_,file)return file end,exists=function()return true end,
                    loadIni=function(_,defaults,path)
                        if path=='family-replies.ini' then defaults.main.enabled=true end
                        return defaults
                    end},
                service=function(name)
                    if name=='family_question.lua' then return questionParser end
                    if name=='report_reader.lua' then return reportReader end
                    error('Unexpected service '..name)
                end,
                queryBusy=function()return false end
            }
            function require(name)
                if name=='encoding' then return {UTF8=u8} end
                if name=='lib.samp.events' then return events end
                if name=='lib.moonloader' then return {} end
                error('Unexpected require '..name)
            end
            function getGameTimer()return clock end
            function isGameWindowForeground()return true end
            function isPauseMenuActive()return false end
            function isGamePaused()return false end
            function isSampAvailable()return true end
            function sampIsDialogActive()return false end
            function sampIsPlayerConnected(id)return players[id]~=nil end
            function sampGetPlayerNickname(id)return players[id]end
            function sampGetPlayerIdByCharHandle()return true,999 end
            function sampAddChatMessage(text)messages[#messages+1]=text end
            function sampSendChat(text)sent[#sent+1]=text;return true end
            function sampRegisterChatCommand(name,fn)commands[name]=fn end
            function sampSendDialogResponse()end
            function wait()coroutine.yield()end
            lua_thread={create=function(fn)threads[#threads+1]=fn end}
            function tick(ms)
                clock=clock+(ms or 0)
                local ok,err=coroutine.resume(main);assert(ok,err)
            end
            function report(text)
                events.onServerMessage(1724645631,text)
            end
            function result(name,family)
                return events.onShowDialog(0,0,'Оффлайн статистика игрока','Закрыть','',
                    'Имя: '..name..'\\nСемья: '..family)
            end
        ''')
        self.lua.execute(module('modules/familia.lua'))
        self.lua.execute('main=coroutine.create(integration.start);tick();tick()')

    def test_report_to_offst_to_answer_then_next_request(self):
        self.start_family_module()
        self.lua.execute('''
            report('[S] Report_Author[42] : {FFCD00}144 id family?')
            tick(2001)
            assert(sent[1]=='/offst Target_Player',tostring(sent[1]))
            report('[S] Second_Author[43] : {FFCD00}196 family')
            assert(result('TARGET_PLAYER','Example Family')==false)
            tick(50)
            assert(sent[2]=='/ans 42 Игрок Target Player состоит в семье Example Family.',tostring(sent[2]))
            tick(2001)
            assert(sent[3]=='/offst Other_Player',tostring(sent[3]))
            assert(result('Other_Player','Нет')==false)
            tick(50)
            assert(sent[4]=='/ans 43 Игрок Other Player не состоит в семье.')
            assert(#messages==0 and #sent==4)
            assert(clock<8000,'Queue waited for the erroneous request timeout')
        ''')

    def test_manual_fama_supports_both_id_orders(self):
        for target in ('144 id', 'id 144', '144'):
            with self.subTest(target=target):
                self.start_family_module()
                self.lua.globals().commands.fama('42 '+target)
                self.lua.execute("tick();assert(sent[1]=='/offst Target_Player')")

    def test_offline_id_and_reused_recipient_do_not_receive_answer(self):
        self.start_family_module()
        self.lua.execute('''
            report('[S] Report_Author[42] : 145 id family?')
            tick(2001);assert(#sent==0)
            report('[S] Report_Author[42] : 144 id family?')
            tick(2001);assert(sent[1]=='/offst Target_Player')
            players[42]='Different_Person'
            result('Target_Player','Example Family');tick()
            assert(#sent==1,'Reused recipient ID must not receive the answer')
        ''')

    def test_unrelated_dialog_does_not_supply_family(self):
        self.start_family_module()
        self.lua.execute('''
            report('[S] Report_Author[42] : id 144 family?');tick(2001)
            assert(result('Other_Player','Other Family')==nil)
            tick();assert(#sent==1)
            result('Target_Player','Correct Family');tick()
            assert(sent[2]=='/ans 42 Игрок Target Player состоит в семье Correct Family.')
        ''')

    def test_full_bundle_compiles(self):
        self.lua.compile(CODE)


if __name__ == '__main__':
    unittest.main(verbosity=2)
