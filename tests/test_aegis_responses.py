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


class AegisResponsesTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().responses = self.lua.execute(module('aegis_responses.lua'))
        self.lua.globals().targets = self.lua.execute(module('punishment_target.lua'))
        self.lua.execute('''
            now=10;sent={};sampev={};state={bypass_outgoing_hook=0};SETTINGS={}
            function trim(s)return tostring(s or ''):match('^%s*(.-)%s*$')end
            function lower(s)return tostring(s or ''):lower()end
            function cp1251_to_utf8(s)return s end
            function utf8_to_cp1251(s)return s end
            function get_online_target_label(id)return 'without_estate['..id..']','without_estate' end
            function get_local_identity()return 231,'Demetrio_Rossi' end
            function is_debug_candidate()return false end
            function is_user_afk_protected()return false end
            function is_afk_exit_suppressed()return false end
            function parse_punishment_info_for_request()end
            function handle_existing_term_stack()return false end
            function handle_online_offline_switch_hint()return false end
            function append_log()end
            function debug_message()end
            function enqueue_admin_chat_status(s)table.insert(sent,'/a '..s)end
            os.clock=function()return now end
            integration={service=function(name)
                if name=='aegis_responses.lua' then return responses end
                if name=='punishment_target.lua' then return targets end
                error(name)
            end,access={require=function()return true end},commandAllowed=function()return true end}
        ''')
        aegis = module('modules/aegis.lua')
        start = aegis.index('local function build_request(')
        end = aegis.index('local parse_supported_command', start)
        parser = aegis[aegis.index('parse_supported_command = function('):aegis.index('local function parse_manual_outgoing_request')]
        entry = aegis[aegis.index('local function parse_admin_chat_request('):aegis.index('parse_supported_command = function(')]
        self.lua.execute(aegis[start:end] + '\nlocal parse_supported_command\n' + parser + entry + '\nparseRequest=parse_admin_chat_request')
        handler = aegis[aegis.index('function sampev.onServerMessage('):aegis.index('    for _,queued in ipairs(state.request_queue)do')]
        self.lua.execute(handler + '\nend')
        send = aegis[aegis.index('local function send_outgoing_command_internal('):aegis.index('local function process_outgoing_queue(')]
        self.lua.execute(send + '\nsendCommand=send_outgoing_command_internal')

    def context(self, kind='/offwarn', name='without_estate', **extra):
        values = dict(kind=kind, target_name=name, admin_name='Lalo_Ingrosso', sent_at=10, created_at=10, batch_id=7)
        values.update(extra)
        ctx = self.lua.table_from(values)
        self.lua.globals().state.awaiting_database_lookup_context = ctx
        return ctx

    def message(self, text):
        self.lua.globals().sampev.onServerMessage(0, text)
        return list(self.lua.globals().sent.values())

    def test_nickname_commands_use_offline_and_preserve_reason_days(self):
        for source, expected in [('/warn Rachik_McFloud пров на ск grove', '/offwarn Rachik_McFloud пров на ск grove'),
                                 ('/ban Rachik_McFloud 30 причина из нескольких слов', '/offban Rachik_McFloud 30 причина из нескольких слов')]:
            request = self.lua.globals().parseRequest('Lalo_Ingrosso', 54, source)
            self.assertEqual(request.command_text, expected)
            self.assertTrue(request.force_offline)
            self.assertIsNone(request.target_id)
            self.assertEqual(request.admin_name, 'Lalo_Ingrosso')

    def test_numeric_online_commands_and_existing_offline_unchanged(self):
        for command in ['/warn 158 причина', '/ban 158 30 причина', '/offwarn Rachik_McFloud причина', '/unwarn 158', '/unban maximiliano_luccheze']:
            request = self.lua.globals().parseRequest('Lalo_Ingrosso', 54, command)
            self.assertEqual(request.command_text, command)

    def test_warn_banned_and_missing_database_exact_logs(self):
        for kind, text, answer in [('/warn', '[22.04.2026 13:53:04] Этот игрок забанен. Выдать предупреждение забаненному игроку нельзя', 'этот игрок заблокирован.'),
                                   ('/offwarn', 'Такого игрока нет в базе данных', 'такого игрока нет в базе данных.'),
                                   ('/unban', 'Такого игрока нет в базе данных', 'такого игрока нет в базе данных.'),
                                   ('/unwarn', '[20.05.2026 23:04:02] У этого игрока нет предупреждений', 'у этого игрока нет предупреждений.')]:
            with self.subTest(kind=kind, text=text):
                self.lua.execute('sent={}')
                self.context(kind)
                self.assertEqual(self.message(text), ['/a Lalo, ' + answer])
                self.assertIsNone(self.lua.globals().state.awaiting_database_lookup_context)
                self.assertEqual(self.message(text), ['/a Lalo, ' + answer])

    def test_unban_actual_colored_announcement(self):
        self.context('/unban', 'maximiliano_luccheze')
        self.assertEqual(self.message('[16.05.2026 20:00:37] [A] Demetrio_Rossi[231] разбанил игрока {0099ff}maximiliano_luccheze {99cc00}(аккаунт 1844004)'),
                         ['/a Lalo, аккаунт maximiliano_luccheze разблокирован.'])

    def test_unwarn_actual_announcement_and_saved_nickname_for_id(self):
        self.lua.execute("get_local_identity=function()return 115,'Celestino_Adderio' end")
        self.context('/unwarn', 'without_estate', target_id=158)
        self.assertEqual(self.message('[16.05.2026 20:49:41] [A] Celestino_Adderio[115] снял 1 предупреждение игроку without_estate[158]'),
                         ['/a Lalo, предупреждение у without_estate снято.'])

    def test_no_false_success_from_other_admin_target_or_chat(self):
        self.context('/unban', 'maximiliano_luccheze')
        for text in ['[A] Other_Admin[231] разбанил игрока maximiliano_luccheze (аккаунт 1844004)',
                     '[A] Demetrio_Rossi[231] разбанил игрока different_player (аккаунт 1844004)',
                     '[A] User_Name[5]: Такого игрока нет в базе данных',
                     '[A] User_Name[5]: Аккаунт maximiliano_luccheze разблокирован.',
                     'У этого игрока нет предупреждений']:
            self.assertEqual(self.message(text), [])

    def test_no_response_without_request_or_after_timeout(self):
        self.assertEqual(self.message('Такого игрока нет в базе данных'), [])
        self.context(sent_at=1)
        self.assertEqual(self.message('Такого игрока нет в базе данных'), [])
        self.context(sent_at=11)
        self.assertEqual(self.message('Такого игрока нет в базе данных'), [])

    def test_send_starts_response_window_and_failure_does_not_arm(self):
        self.lua.execute("sampSendChat=function()return false end")
        ctx = self.context(created_at=0, sent_at=0)
        self.lua.globals().state.awaiting_database_lookup_context = None
        self.assertFalse(self.lua.globals().sendCommand('/offwarn without_estate reason', 'auto-confirm', ctx, None, None, None))
        self.assertIsNone(self.lua.globals().state.awaiting_database_lookup_context)
        self.lua.execute('sampSendChat=function()return true end')
        self.assertTrue(self.lua.globals().sendCommand('/offwarn without_estate reason', 'auto-confirm', ctx, None, None, None))
        self.assertEqual(ctx.sent_at, 10)
        self.assertEqual(ctx.created_at, 10)

    def test_packaged_helper_and_luajit_compilation(self):
        self.assertEqual(module('aegis_responses.lua').strip(), (ROOT/'libraries/aegis_responses.lua').read_text('utf-8').strip())
        self.lua.compile(CODE)

    def test_watch_includes_online_warn_and_both_revocations(self):
        aegis = module('modules/aegis.lua')
        body = aegis[aegis.index('local function should_watch_database_lookup_result('):aegis.index('local function should_watch_punishment_conflict(')]
        self.lua.execute("function is_punish_command(k)return k=='/offwarn' or k=='/offban' end\n" + body + '\nwatch=should_watch_database_lookup_result')
        for kind, target_id in [('/warn', 158), ('/offwarn', None), ('/offban', None), ('/unwarn', 158), ('/unwarn', None), ('/unban', None)]:
            ctx = self.context(kind, target_id=target_id)
            self.assertTrue(self.lua.globals().watch(ctx))
            ctx.admin_name = ''
            self.assertFalse(self.lua.globals().watch(ctx))

    def test_nickname_alias_does_not_get_locally_switched_back_to_id(self):
        aegis = module('modules/aegis.lua')
        body = aegis[aegis.index('local function build_local_online_switch_result('):aegis.index('local function queue_switched_command_from_context(')]
        self.lua.execute(body + '\nlocalSwitch=build_local_online_switch_result')
        request = self.lua.globals().parseRequest('Lalo_Ingrosso', 54, '/warn without_estate причина')
        self.assertIsNone(self.lua.globals().localSwitch(request, request.command_text))

    def test_manual_command_clears_ambiguous_response_but_internal_send_does_not(self):
        aegis = module('modules/aegis.lua')
        body = aegis[aegis.index('function sampev.onSendCommand('):aegis.index('\tlocal command_text = trim(cp1251_to_utf8(command or ""))')]
        self.lua.execute('function touch_user_activity()end\n' + body + '\nend')
        self.context()
        self.lua.globals().state.bypass_outgoing_hook = 1
        self.lua.globals().sampev.onSendCommand('/offwarn without_estate reason')
        self.assertIsNotNone(self.lua.globals().state.awaiting_database_lookup_context)
        self.lua.globals().state.bypass_outgoing_hook = 0
        self.lua.globals().sampev.onSendCommand('/offwarn somebody_else reason')
        self.assertIsNone(self.lua.globals().state.awaiting_database_lookup_context)

    def test_terminal_response_clears_only_its_batch(self):
        self.context()
        self.lua.execute('state.awaiting_online_offline_switch_context={batch_id=7};state.awaiting_punishment_guard_context={batch_id=99}')
        self.message('Такого игрока нет в базе данных')
        self.assertIsNone(self.lua.globals().state.awaiting_online_offline_switch_context)
        self.assertEqual(self.lua.globals().state.awaiting_punishment_guard_context.batch_id, 99)


if __name__ == '__main__':
    unittest.main(verbosity=2)
