"""Build the admin-request reply fix from the immutable 3.5.303 release."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'update/current/versions/3.5.303'
code = (BASE / 'X-TOOL.lua').read_text('utf-8')


def replace(old, new):
    global code
    assert code.count(old) == 1, (code.count(old), old[:100])
    code = code.replace(old, new)


marker = '    sources["modules/aegis.lua"] = function()'
helper = (ROOT / 'libraries/aegis_responses.lua').read_text('utf-8')
replace(marker, '    sources["aegis_responses.lua"] = function()\n' + helper + '\n    end\n' + marker)
replace('local function parse_admin_chat_request(admin_name, admin_id, command_text)\n\tlocal request = parse_supported_command(admin_name, admin_id, command_text)', '''local function parse_admin_chat_request(admin_name, admin_id, command_text)
    local normalized, nicknamePunishment=integration.service('aegis_responses.lua').normalize(command_text)
    command_text=normalized
    local request = parse_supported_command(admin_name, admin_id, command_text)
    if request and nicknamePunishment then request.force_offline=true end''')
replace('local function build_local_online_switch_result(request, command_text)\n', '''local function build_local_online_switch_result(request, command_text)
    if request and request.force_offline then return nil end
''')
replace('''		and request.target_id == nil
		and is_punish_command(request.kind)
end''', '''        and ((request.target_id == nil and is_punish_command(request.kind))
            or request.kind == '/warn' or request.kind == '/unwarn' or request.kind == '/unban')
end''')
replace('''	if response_context ~= nil then
		state.awaiting_database_lookup_context = response_context
	end''', '''    if response_context ~= nil then
        -- Start the response window after sending, not while waiting for confirmation.
        response_context.created_at=os.clock()
        response_context.sent_at=response_context.created_at
        state.awaiting_database_lookup_context=response_context
    end''')
start = code.index('\tif state.awaiting_database_lookup_context ~= nil and text:find("Такого игрока нет в базе данных"')
end = code.index('    for _,queued in ipairs(state.request_queue)do', start)
code = code[:start] + '''    local response_context=state.awaiting_database_lookup_context
    local _,local_name=get_local_identity()
    local response=integration.service('aegis_responses.lua').reply(response_context,text,os.clock(),local_name)
    if response then
        -- Consume first: repeated announcements must not enqueue duplicate replies.
        state.awaiting_database_lookup_context=nil
        local batch=response_context.batch_id
        if state.awaiting_online_offline_switch_context and state.awaiting_online_offline_switch_context.batch_id==batch then
            state.awaiting_online_offline_switch_context=nil
        end
        if state.awaiting_punishment_guard_context and state.awaiting_punishment_guard_context.batch_id==batch then
            state.awaiting_punishment_guard_context=nil
        end
        enqueue_admin_chat_status(response,'request-server-result')
        append_log('Ответ инициатору: '..response)
        return
    end

''' + code[end:]
replace('''function sampev.onSendCommand(command)
	touch_user_activity()

	if state.bypass_outgoing_hook > 0 then
		return
	end''', '''function sampev.onSendCommand(command)
	touch_user_activity()

	if state.bypass_outgoing_hook > 0 then
		return
	end
    -- An unrelated manual command makes a subsequent unlabelled error ambiguous.
    state.awaiting_database_lookup_context=nil''')
replace('''function integration.stop()
	do
		release_request_overlay_fonts()''', '''function integration.stop()
    clear_afk_sensitive_contexts()
	do
		release_request_overlay_fonts()''')

code = code.replace('3.5.303', '3.5.304').encode('utf-8')
manifest = json.loads((BASE / 'manifest.json').read_text('utf-8'))
manifest.update(version='3.5.304', packagePath='versions/3.5.304/')
manifest['script'].update(bytes=len(code), sha256=hashlib.sha256(code).hexdigest())
for directory in (ROOT / 'update/current', ROOT / 'update/current/versions/3.5.304'):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'X-TOOL.lua').write_bytes(code)
    (directory / 'manifest.json').write_bytes((json.dumps(manifest, ensure_ascii=False, indent=2)+'\n').encode('utf-8'))
    shutil.copyfile(BASE / 'assets.pack', directory / 'assets.pack')
(ROOT / 'X-TOOL.lua').write_bytes(code)
print(json.dumps(manifest['script']))
