-- X-TOOLS | Project and integration: Casual_Alvarez | Module: modules/aegis.lua
-- Original third-party credits, where present, are retained below.
-- CasualAT module. Author: Casual Alvarez. Original source: integration/sources.
local BRAND_NAME = "Наказания"
local BRAND_CHAT_TAG = "X-Tools"


require("lib.sampfuncs")
require("lib.moonloader")

local encoding = require("encoding")
local sampev = require("lib.samp.events")
local vkeys = require("vkeys")

local has_imgui, imgui = pcall(require, "admintools.ui")
local has_ffi, ffi = pcall(require, "ffi")
local winmm = nil

encoding.default = "CP1251"
u8 = encoding.UTF8

if has_ffi then
	pcall(function()
		ffi.cdef([[
			int PlaySoundA(const char *pszSound, void *hmod, unsigned int fdwSound);
		]])
	end)

	local ok_winmm, loaded_winmm = pcall(ffi.load, "winmm")
	if ok_winmm then
		winmm = loaded_winmm
	end
end

function cp1251_to_utf8(str)
	return tostring(u8(str or ""))
end

function utf8_to_cp1251(str)
	return u8:decode(tostring(str or ""))
end

local rules = integration.service("aegis_rules.lua")
local storage = integration.storage
local ROOT_DIR = getWorkingDirectory()
local DATA_DIR = storage:directory('data', 'punishments')
local function stored(kind, name, legacy)
    return storage:path(kind, name, {ROOT_DIR .. '/Aegis Suite/' .. legacy,
        ROOT_DIR .. '/AdminChatPunishHotkey/' .. legacy})
end
local SETTINGS_FILE = stored('settings', 'punishments.lua', 'settings.lua')
local LOG_FILE = stored('logs', 'punishments/issued_commands.log', 'issued_commands.log')
local REQUEST_LOG_FILE = stored('logs', 'punishments/request_log.txt', 'request_log.txt')
local DEBUG_LOG_FILE = stored('logs', 'punishments/debug.log', 'debug.log')
local LOCAL_ADMINS_FILE = stored('data', 'punishments/admins.txt', 'admins.txt')
local NOTIFY_SOUND_FILE = stored('cache', 'punishments/notify_click.wav', 'notify_click.wav')
ADM_CHECKER_DIR = storage:directory('data', 'checker')
ADM_CHECKER_ADMINS_TXT_FILE = storage:path('data', 'checker/admins.txt', {
    ROOT_DIR .. '/ADM/checker/admins.txt', ROOT_DIR .. '/ADM/checker/admins',
    ROOT_DIR .. '/AdminTools/checker/admins.txt'})
ADM_CHECKER_ADMINS_FILE = ADM_CHECKER_ADMINS_TXT_FILE
ADM_CHECKER_LEADERS_TXT_FILE = storage:path('data', 'checker/leaders.txt', {
    ROOT_DIR .. '/ADM/checker/leaders.txt', ROOT_DIR .. '/ADM/checker/leaders',
    ROOT_DIR .. '/AdminTools/checker/leaders.txt'})
ADM_CHECKER_LEADERS_FILE = ADM_CHECKER_LEADERS_TXT_FILE
local LEGACY_ADMINS_FILE = ADM_CHECKER_ADMINS_TXT_FILE
local REQUEST_OVERLAY_SUBTITLE = "запрос на выдачу"
local CHAT_PREFIX = "{5DA9FF}[" .. BRAND_CHAT_TAG .. "] {E8E8E8}"
local CHAT_COLOR = 15263976
REQUEST_OVERLAY_SUBTITLE = "ожидает подтверждения"
CHAT_PREFIX = "{8CB8FF}[" .. BRAND_CHAT_TAG .. "] {EAF1FF}"
local DEFAULT_PRE_PUNISH_NOTICE_LINE_1 = "Перед выходом из игры обязательно сделайте скриншот (F8)."
local DEFAULT_PRE_PUNISH_NOTICE_LINE_2 = "Он потребуется при подаче жалобы на форуме."
local DEFAULT_PRE_PUNISH_NOTICE_LINE_3 = "Форум: forum.adv-rp.com"
local DEFAULT_FORUM_NOTICE_COMMANDS_TEXT = table.concat({
	"/jail",
	"/mute",
	"/kick",
	"/skick",
	"/sban",
	"/warn",
	"/ban"
}, "\n")
local DEFAULT_NO_NOTICE_COMMANDS_TEXT = table.concat({
	"/unjail",
	"/unmute",
	"/unwarn",
	"/unban",
	"/offban",
	"/offwarn",
	"/offmute",
	"/offjail",
	"/msg"
}, "\n")
local DEFAULT_ADMIN_CHAT_COMMANDS_TEXT = table.concat({
	"/jail",
	"/unjail",
	"/mute",
	"/unmute",
	"/kick",
	"/skick",
	"/sban",
	"/warn",
	"/unwarn",
	"/ban",
	"/unban",
	"/offban",
	"/offwarn",
	"/offmute",
	"/offjail",
	"/msg"
}, "\n")
local DEFAULT_REPORT_COMMANDS_TEXT = table.concat({
	"/hp | {admin}, здоровье игрока {target} пополнено до {arg2}.",
	"/skin | {admin}, игроку {target} выдан временный скин {arg2}.",
	"/msg | {admin}, сообщение игроку {target} отправлено.",
	"/spawn | {admin}, игрок {target} был заспавнен."
}, "\n")
local OUTGOING_QUEUE_INTERVAL = 0.225
STACK_TERM_REISSUE_DELAY = 3.0
STACK_TERM_RESPONSE_TIMEOUT = 20.0
AFK_EXIT_SUPPRESS_SECONDS = 3.0
local SIGNATURE_VARIANT_LABELS = {
	"by Имя Фамилия",
	"by ИФ",
	"by И.Ф.",
	"by Имя",
	"| Имя",
	"| Имя Фамилия",
	"by Фамилия",
	"| фамилия",
	"фамилия",
	"имя",
	"Имя",
	"Фамилия",
	"ИФ",
	"иф",
	"Рандом", "Без подписи", "Свой шаблон"
}
local RANDOM_SIGNATURE_MODE = 15
local COMMAND_GROUPS = {
	forum_notice = {
		setting_key = "forum_notice_commands_text",
		ui_key = "forum_notice_commands_text",
		title = "С уведомлением о форуме",
		hint = "Сначала отправить игроку уведомление /ans, затем выполнить команду."
	},
	no_notice = {
		setting_key = "no_notice_commands_text",
		ui_key = "no_notice_commands_text",
		title = "Без уведомления о форуме",
		hint = "Выполнить команду без предварительного уведомления игрока."
	},
	admin_chat = {
		setting_key = "admin_chat_commands_text",
		ui_key = "admin_chat_commands_text",
		title = "Из админ-чата",
		hint = "Показывать запросы из /a для ручного подтверждения."
	},
	report = {
		setting_key = "report_commands_text",
		ui_key = "report_commands_text",
		title = "С отчётом в /a",
		hint = "После команды отправить отчёт в чат администраторов."
	}
}

local DEFAULT_SETTINGS = {
	enabled = true,
    stack_jail_enabled = true,
    stack_mute_enabled = true,
    stack_notice_enabled = true,
    stack_notice_template = "Ранее назначенные наказания объединены в один срок.",
    custom_signature = "by {first} {last}",
    command_chains = "/tr | 0 | /sp {id}\n/tr | 5 | /tr {id}\n/tr | 0 | /slap {id}\n/tr | 3 | /sp",
    queue_limit = 20,
    queue_max_age = 120,
	show_chat_messages = true,
	request_timeout = 10,
	admin_chat_color = -1714683649,
	confirm_key = vkeys.VK_DELETE,
	cancel_key = vkeys.VK_END,
	block_known_admin_targets = true,
	auto_cancel_on_activity = true,
	log_captured_requests = true,
	debug_enabled = true,
	sound_notify_enabled = true,
	show_final_command_message = true,
	show_request_overlay = true,
	signature_mode = 1,
	pre_punish_notice_enabled = true,
	auto_switch_online_offline = false,
	track_other_admin_punishments = true,
	forum_notice_line_1 = DEFAULT_PRE_PUNISH_NOTICE_LINE_1,
	forum_notice_line_2 = DEFAULT_PRE_PUNISH_NOTICE_LINE_2,
	forum_notice_line_3 = DEFAULT_PRE_PUNISH_NOTICE_LINE_3,
	forum_notice_commands_text = DEFAULT_FORUM_NOTICE_COMMANDS_TEXT,
	no_notice_commands_text = DEFAULT_NO_NOTICE_COMMANDS_TEXT,
	admin_chat_commands_text = DEFAULT_ADMIN_CHAT_COMMANDS_TEXT,
	report_commands_text = DEFAULT_REPORT_COMMANDS_TEXT
}

DEFAULT_SETTINGS.show_chat_messages = false
DEFAULT_SETTINGS.debug_enabled = false
DEFAULT_SETTINGS.signature_mode = 14
DEFAULT_SETTINGS.auto_switch_online_offline = true
DEFAULT_SETTINGS.track_other_admin_punishments = false
DEFAULT_SETTINGS.forum_notice_line_2 = "Форум: forum.adv-rp.com"
DEFAULT_SETTINGS.forum_notice_line_3 = ""
DEFAULT_SETTINGS.report_commands_text = table.concat({
	"/hp | {admin}, здоровье игрока {target} пополнено до {arg2}.",
	"/skin | {admin}, игроку {target} выдан временный скин {arg2}.",
	"/msg | {admin}, сообщение отправлено.",
	"/spawn | {admin}, игрок {target} был заспавнен.",
	"/tr | {admin}, игрок {target} был спасен.",
	"/freeeze | {admin}, игрок {target} был отморожен.",
	"/slap | {admin}, игрок {target} получил поджоп."
}, "\n")

local ACTIVITY_COLORS = {
	[-11521793] = true,
	[-1717986817] = true,
	[-825307393] = true
}

local SETTINGS = {}
local state = {
	pending_request = nil,
    request_queue = {},
	status_line = "Готово к работе.",
	known_admins = {},
	known_admin_count = 0,
	known_admin_only_count = 0,
	known_leader_count = 0,
	key_capture = nil,
	key_capture_started_at = 0,
	forum_notice_commands = {},
	no_notice_commands = {},
	admin_chat_commands = {},
	report_commands = {},
	report_command_templates = {},
	outgoing_queue = {},
	next_outgoing_at = 0,
	bypass_outgoing_hook = 0,
	awaiting_database_lookup_context = nil,
	awaiting_punishment_guard_context = nil,
	awaiting_online_offline_switch_context = nil,
	awaiting_stack_term_context = nil,
	next_outgoing_batch_id = 0,
	afk_suppress_until = 0,
	last_user_activity_at = os.clock(),
	next_activity_poll_at = 0,
	afk_guard_active = false,
}

local ui = nil
local command_editor = nil
local draft_keys = nil
local chain_editor = nil
if has_imgui and has_ffi then
	ui = {
		window = imgui.new.bool(false),
        stack_jail_enabled = imgui.new.bool(true),
        stack_mute_enabled = imgui.new.bool(true),
        stack_notice_enabled = imgui.new.bool(true),
        stack_notice_template = imgui.new.char[512](),
        custom_signature = imgui.new.char[256](),
        command_chains = imgui.new.char[4096](),
        queue_limit = imgui.new.int(20),
        queue_max_age = imgui.new.int(120),
		enabled = imgui.new.bool(DEFAULT_SETTINGS.enabled),
		show_chat_messages = imgui.new.bool(DEFAULT_SETTINGS.show_chat_messages),
		request_timeout = imgui.new.int(DEFAULT_SETTINGS.request_timeout),
		admin_chat_color = imgui.new.int(DEFAULT_SETTINGS.admin_chat_color),
		block_known_admin_targets = imgui.new.bool(DEFAULT_SETTINGS.block_known_admin_targets),
		auto_cancel_on_activity = imgui.new.bool(DEFAULT_SETTINGS.auto_cancel_on_activity),
		log_captured_requests = imgui.new.bool(DEFAULT_SETTINGS.log_captured_requests),
		debug_enabled = imgui.new.bool(DEFAULT_SETTINGS.debug_enabled),
		sound_notify_enabled = imgui.new.bool(DEFAULT_SETTINGS.sound_notify_enabled),
		show_final_command_message = imgui.new.bool(DEFAULT_SETTINGS.show_final_command_message),
		show_request_overlay = imgui.new.bool(DEFAULT_SETTINGS.show_request_overlay),
		signature_mode = imgui.new.int(DEFAULT_SETTINGS.signature_mode),
		pre_punish_notice_enabled = imgui.new.bool(DEFAULT_SETTINGS.pre_punish_notice_enabled),
		auto_switch_online_offline = imgui.new.bool(DEFAULT_SETTINGS.auto_switch_online_offline),
		track_other_admin_punishments = imgui.new.bool(DEFAULT_SETTINGS.track_other_admin_punishments),
		forum_notice_line_1 = imgui.new.char[256](),
		forum_notice_line_2 = imgui.new.char[256](),
		forum_notice_line_3 = imgui.new.char[256](),
		forum_notice_commands_text = imgui.new.char[2048](),
		no_notice_commands_text = imgui.new.char[2048](),
		admin_chat_commands_text = imgui.new.char[2048](),
		report_commands_text = imgui.new.char[4096]()
	}

	command_editor = {
		window = imgui.new.bool(false),
		group_key = nil,
		rows = {}
	}
end

local request_overlay_main_font = nil
local request_overlay_sub_font = nil
local request_overlay_font_screen_w = 0
local request_overlay_font_screen_h = 0
local request_overlay_main_size = 0
local request_overlay_sub_size = 0

local function trim(text)
	return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(text)
	return string.lower(trim(text))
end

local function set_imgui_buffer(buffer, text)
	if not has_ffi or buffer == nil then
		return
	end

	text = tostring(text or "")
	local buffer_size = ffi.sizeof(buffer)

	ffi.fill(buffer, buffer_size, 0)

	if #text > 0 then
		ffi.copy(buffer, text:sub(1, buffer_size - 1))
	end
end

local function get_imgui_buffer_text(buffer)
	if not has_ffi or buffer == nil then
		return ""
	end

	return tostring(ffi.string(buffer))
end

local function normalize_command_name(command_name)
	local normalized = lower(command_name)

	if normalized == "" or normalized:match("^%s*;") then
		return nil
	end

	normalized = normalized:match("^(%S+)") or normalized

	if normalized:sub(1, 1) ~= "/" then
		normalized = "/" .. normalized
	end

	return normalized
end

local function get_command_name_from_text(command_text)
	command_text = trim(command_text)

	if command_text == "" then
		return nil
	end

	if command_text:sub(1, 1) ~= "/" then
		command_text = "/" .. command_text
	end

	return normalize_command_name(command_text:match("^(%S+)") or "")
end

local function rebuild_command_group(raw_text)
	local commands = {}

	for line in tostring(raw_text or ""):gmatch("[^\r\n]+") do
		local normalized = normalize_command_name(line)

		if normalized ~= nil then
			commands[normalized] = true
		end
	end

	return commands
end

local function split_report_command_line(line)
	local command_part, template_part = tostring(line or ""):match("^%s*(.-)%s*|%s*(.-)%s*$")

	if command_part == nil then
		command_part = line
		template_part = nil
	end

	local command_name = normalize_command_name(command_part)

	if command_name == nil then
		return nil, nil
	end

	return command_name, trim(template_part or "")
end

local function rebuild_report_command_group(raw_text)
	local commands = {}
	local templates = {}

	for line in tostring(raw_text or ""):gmatch("[^\r\n]+") do
		local command_name, template = split_report_command_line(line)

		if command_name ~= nil then
			commands[command_name] = true

			if template ~= "" then
				templates[command_name] = template
			end
		end
	end

	return commands, templates
end

local function rebuild_command_groups()
	state.forum_notice_commands = rebuild_command_group(SETTINGS.forum_notice_commands_text)
	state.no_notice_commands = rebuild_command_group(SETTINGS.no_notice_commands_text)
	state.admin_chat_commands = rebuild_command_group(SETTINGS.admin_chat_commands_text)
	state.report_commands, state.report_command_templates = rebuild_report_command_group(SETTINGS.report_commands_text)
end

local function is_forum_notice_command(command_name)
	local normalized = normalize_command_name(command_name)

	return normalized ~= nil and state.forum_notice_commands[normalized] == true
end

local function is_no_notice_command(command_name)
	local normalized = normalize_command_name(command_name)

	return normalized ~= nil and state.no_notice_commands[normalized] == true
end

local function is_admin_chat_command(command_name)
	local normalized = normalize_command_name(command_name)

	return normalized ~= nil and state.admin_chat_commands[normalized] == true
end

local function is_report_command(command_name)
	local normalized = normalize_command_name(command_name)

	return normalized ~= nil and state.report_commands[normalized] == true
end

local function get_default_report_template(command_name)
	command_name = normalize_command_name(command_name)

	if command_name == "/hp" then
		return "{admin}, здоровье игрока {target} пополнено до {arg2}."
	elseif command_name == "/skin" then
		return "{admin}, игроку {target} выдан временный скин {arg2}."
	elseif command_name == "/msg" then
		return "{admin}, сообщение игроку {target} отправлено."
	elseif command_name == "/tr" then
		return "{admin}, игрок {target} был успешно спасен."
	elseif command_name == "/spawn" then
		return "{admin}, игрок {target} был заспавнен."
	end

	return "{admin}, команда {cmd} для {target} выполнена."
end

local function get_report_template(command_name)
	command_name = normalize_command_name(command_name)

	if command_name == nil then
		return nil
	end

	local template = state.report_command_templates and state.report_command_templates[command_name] or nil

	if template == nil or trim(template) == "" then
		template = get_default_report_template(command_name)
	end

	return template
end

local function is_manual_command_tracked(command_name)
	return is_forum_notice_command(command_name) or is_no_notice_command(command_name)
end

local function is_reactive_command(command_name)
	return is_admin_chat_command(command_name) or is_report_command(command_name)
end

local function count_command_group(commands)
	local total = 0

	for _ in pairs(commands or {}) do
		total = total + 1
	end

	return total
end

local function set_status_line(text)
	state.status_line = trim(text)
end

local function play_request_notification_sound()
	if SETTINGS.sound_notify_enabled ~= true then
		return
	end

	if winmm == nil or not doesFileExist(NOTIFY_SOUND_FILE) then
		return
	end

	pcall(function()
		winmm.PlaySoundA(NOTIFY_SOUND_FILE, nil, 0x00020000 + 0x00000001 + 0x00000002)
	end)
end

local clear_afk_sensitive_contexts

local function is_pause_afk_mode()
    return state.window_inactive == true
        or (type(isGameWindowForeground) == "function" and not isGameWindowForeground())
        or (type(isPauseMenuActive) == "function" and isPauseMenuActive()) or isGamePaused()
end

-- Observe transitions before processing a server message, not only on the next tick.
local function poll_user_activity()
    if is_pause_afk_mode() then
        if not state.afk_guard_active then
            state.afk_guard_active = true
            clear_afk_sensitive_contexts()
        end
    elseif state.afk_guard_active then
        state.afk_guard_active = false
        state.afk_suppress_until = os.clock() + AFK_EXIT_SUPPRESS_SECONDS
    end
end

local function touch_user_activity()
    poll_user_activity()
end

local function is_user_afk_protected()
    poll_user_activity()
    return state.afk_guard_active
end

local function is_afk_exit_suppressed()
    return os.clock() < (state.afk_suppress_until or 0)
end

-- Capture Alt+Tab even when the game loop stops running in the background.
function integration.onWindowMessage(msg, value)
    if msg == 0x8 or (msg == 0x1C and value == 0) then
        state.window_inactive = true
        poll_user_activity()
    elseif msg == 0x7 or (msg == 0x1C and value ~= 0) then
        state.window_inactive = false
        poll_user_activity()
    end
end

local function release_request_overlay_fonts()
	if request_overlay_main_font and renderReleaseFont then
		pcall(renderReleaseFont, request_overlay_main_font)
	end

	if request_overlay_sub_font and renderReleaseFont then
		pcall(renderReleaseFont, request_overlay_sub_font)
	end

	request_overlay_main_font = nil
	request_overlay_sub_font = nil
	request_overlay_font_screen_w = 0
	request_overlay_font_screen_h = 0
	request_overlay_main_size = 0
	request_overlay_sub_size = 0
end

local function ensure_request_overlay_fonts(main_size, sub_size)
	if type(renderCreateFont) ~= "function" or type(getScreenResolution) ~= "function" then
		return false
	end

	local screen_w, screen_h = getScreenResolution()
	main_size = math.max(18, math.floor(tonumber(main_size) or 28))
	sub_size = math.max(10, math.floor(tonumber(sub_size) or 12))

	if request_overlay_main_font ~= nil and request_overlay_main_font ~= 0
		and request_overlay_sub_font ~= nil and request_overlay_sub_font ~= 0
		and request_overlay_font_screen_w == screen_w
		and request_overlay_font_screen_h == screen_h
		and request_overlay_main_size == main_size
		and request_overlay_sub_size == sub_size then
		return true
	end

	release_request_overlay_fonts()

	request_overlay_main_font = renderCreateFont("Arial", main_size, 5)
	request_overlay_sub_font = renderCreateFont("Tahoma", sub_size, 5)
	request_overlay_font_screen_w = screen_w
	request_overlay_font_screen_h = screen_h
	request_overlay_main_size = main_size
	request_overlay_sub_size = sub_size

	return request_overlay_main_font ~= nil and request_overlay_main_font ~= 0 and request_overlay_sub_font ~= nil and request_overlay_sub_font ~= 0
end

local function draw_request_overlay_text(font, text, x, y, color)
	if not font or text == nil or text == "" then
		return
	end

	local encoded = utf8_to_cp1251(text)

	renderFontDrawText(font, encoded, x - 1, y, 0xCC000000)
	renderFontDrawText(font, encoded, x + 1, y, 0xCC000000)
	renderFontDrawText(font, encoded, x, y - 1, 0xCC000000)
	renderFontDrawText(font, encoded, x, y + 1, 0xCC000000)
	renderFontDrawText(font, encoded, x + 1, y + 1, 0x99000000)
	renderFontDrawText(font, encoded, x, y, color)
end

local function format_request_overlay_admin_name(admin_name)
	admin_name = trim(tostring(admin_name or ""))

	if admin_name == "" then
		return "Администратор не определён"
	end

	admin_name = admin_name:gsub("_", " ")
	admin_name = trim(admin_name:gsub("%s+", " "))
	return admin_name
end

local function draw_pending_request_overlay()
	if SETTINGS.show_request_overlay ~= true or state.pending_request == nil then
		return
	end

	if isGamePaused() or isPauseMenuActive() then
		return
	end

	local screen_w, screen_h = getScreenResolution()
	local base_main_size = math.max(18, math.floor(screen_h * 0.026))
	local base_sub_size = math.max(10, math.floor(screen_h * 0.014))

	if not ensure_request_overlay_fonts(base_main_size, base_sub_size) then
		return
	end

	local admin_name = format_request_overlay_admin_name(state.pending_request.admin_name)
	local subtitle = REQUEST_OVERLAY_SUBTITLE .. (#state.request_queue>0 and (' · В очереди: '..#state.request_queue) or '')
	local main_encoded = utf8_to_cp1251(admin_name)
	local main_width = renderGetFontDrawTextLength(request_overlay_main_font, main_encoded)
	local subtitle_encoded = utf8_to_cp1251(subtitle)
	local subtitle_width = renderGetFontDrawTextLength(request_overlay_sub_font, subtitle_encoded)
	local margin_right = math.max(26, math.floor(screen_w * 0.024))
	local margin_bottom = math.max(86, math.floor(screen_h * 0.12))
	local line_gap = math.max(7, math.floor(screen_h * 0.008))
	local total_height = request_overlay_main_size + request_overlay_sub_size + line_gap
	local base_y = screen_h - margin_bottom - total_height
	local main_x = screen_w - margin_right - main_width
	local subtitle_x = screen_w - margin_right - subtitle_width
	local subtitle_y = base_y + request_overlay_main_size + line_gap

	draw_request_overlay_text(request_overlay_main_font, admin_name, main_x, base_y, 0xFF6A79FF)
	draw_request_overlay_text(request_overlay_sub_font, subtitle, subtitle_x, subtitle_y, 0xFFF4D778)
end

local request_overlay_fault,request_overlay_drawing=nil,false
local function safe_draw_pending_request_overlay()
    if SETTINGS.show_request_overlay~=true then request_overlay_fault=nil;return end
    if request_overlay_fault or request_overlay_drawing then return end
    request_overlay_drawing=true
    local ok,err=pcall(draw_pending_request_overlay)
    request_overlay_drawing=false
    if not ok then
        request_overlay_fault=tostring(err)
        pcall(release_request_overlay_fonts)
        print('[Aegis HUD] Overlay suspended; command processing remains active: '..request_overlay_fault)
        pcall(sampAddChatMessage,utf8_to_cp1251('[Aegis] Ошибка плашки запроса. Обработка команд продолжается. Выключите и включите показ запроса, чтобы повторить.'),-1)
    end
end

local function message(text, force)
	set_status_line(text)

	if force == "settings" or force == "diagnostic" or force == "final" or force == "request" or SETTINGS.show_chat_messages then
		sampAddChatMessage(utf8_to_cp1251(CHAT_PREFIX .. text), CHAT_COLOR)
	end
end

local function append_log(text)
    if not SETTINGS.log_captured_requests then return end
	local file = io.open(LOG_FILE, "a")

	if file then
		file:write(string.format("[%s] %s\n", os.date("%d.%m.%Y %H:%M:%S"), text))
		file:close()
	end
end

local function clean_log_field(value)
	value = trim(tostring(value or ""))
	value = value:gsub("[\r\n]+", " ")

	if value == "" then
		return "-"
	end

	return value
end

local function append_request_log(status, request, details, issued_command)
    if not SETTINGS.log_captured_requests then return end
	local file = io.open(REQUEST_LOG_FILE, "a")

	if not file then
		return
	end

	local admin = "-"
	local target = "-"
	local command_text = "-"

	if request ~= nil then
		local admin_name = clean_log_field(request.admin_name)
		local admin_id = tonumber(request.admin_id)

		if admin_id ~= nil and admin_id > 0 then
			admin = string.format("%s[%d]", admin_name, admin_id)
		else
			admin = admin_name
		end

		target = clean_log_field(request.target_label or request.target_name)
		command_text = clean_log_field(request.command_text)
	end

	file:write(string.format(
		"[%s] %s | admin=%s | target=%s | request=%s | issued=%s | details=%s\n",
		os.date("%d.%m.%Y %H:%M:%S"),
		clean_log_field(status),
		admin,
		target,
		command_text,
		clean_log_field(issued_command),
		clean_log_field(details)
	))
	file:close()
end

local function append_debug_log(text)
	if SETTINGS.debug_enabled ~= true then
		return
	end

	local file = io.open(DEBUG_LOG_FILE, "a")

	if file then
		file:write(string.format("[%s] %s\n", os.date("%d.%m.%Y %H:%M:%S"), text))
		file:close()
	end
end

local function debug_message(text, show_in_chat)
	if SETTINGS.debug_enabled ~= true then
		return
	end

	append_debug_log(text)

	if show_in_chat then
		message("[Диагностика] " .. text, "diagnostic")
	end
end

local function is_debug_candidate(color, text)
	local normalized = lower(text)

	return color == SETTINGS.admin_chat_color
		or text:find("[A]", 1, true) ~= nil
		or text:find("]: /", 1, true) ~= nil
		or normalized:find("/jail", 1, true) ~= nil
		or normalized:find("/mute", 1, true) ~= nil
		or normalized:find("/kick", 1, true) ~= nil
		or normalized:find("/warn", 1, true) ~= nil
		or normalized:find("/ban", 1, true) ~= nil
end

local function get_signature_parts(admin_name)
	local full_name = trim(tostring(admin_name or ""):gsub("_", " "):gsub("%s+", " "))

	if full_name == "" then
		full_name = "Admin Name"
	end

	local first_name = full_name:match("^(%S+)") or full_name
	local last_name = full_name:match(".*%s+(%S+)$") or first_name
	local first_initial = string.upper(first_name:sub(1, 1))
	local last_initial = string.upper(last_name:sub(1, 1))

	return {
		full = full_name,
		first = first_name,
		last = last_name,
		first_lower = lower(first_name),
		last_lower = lower(last_name),
		initials = first_initial .. last_initial,
		initials_lower = lower(first_initial .. last_initial),
		initials_dotted = first_initial .. "." .. last_initial .. "."
	}
end

local function get_signature_text(admin_name, mode, custom)
	local parts = get_signature_parts(admin_name)
	mode = math.floor(tonumber(mode) or SETTINGS.signature_mode or DEFAULT_SETTINGS.signature_mode)

	if mode < 1 or mode > #SIGNATURE_VARIANT_LABELS then
		mode = DEFAULT_SETTINGS.signature_mode
	end

	if mode == 16 then return "" end
    if mode == 17 then
        return rules.render(custom or SETTINGS.custom_signature, {
            admin=admin_name,first=parts.first,last=parts.last,initials=parts.initials})
    end
    if mode == RANDOM_SIGNATURE_MODE then
		return "случайный формат"
	end

	if mode == 1 then
		return "by " .. parts.full
	elseif mode == 2 then
		return "by " .. parts.initials
	elseif mode == 3 then
		return "by " .. parts.initials_dotted
	elseif mode == 4 then
		return "by " .. parts.first
	elseif mode == 5 then
		return "| " .. parts.first
	elseif mode == 6 then
		return "| " .. parts.full
	elseif mode == 7 then
		return "by " .. parts.last
	elseif mode == 8 then
		return "| " .. parts.last_lower
	elseif mode == 9 then
		return parts.last_lower
	elseif mode == 10 then
		return parts.first_lower
	elseif mode == 11 then
		return parts.first
	elseif mode == 12 then
		return parts.last
	elseif mode == 13 then
		return parts.initials
	elseif mode == 14 then
		return parts.initials_lower
	end

	return parts.last
end

local function get_signature_label(mode)
	mode = math.floor(tonumber(mode) or SETTINGS.signature_mode or DEFAULT_SETTINGS.signature_mode)

	if mode < 1 or mode > #SIGNATURE_VARIANT_LABELS then
		mode = DEFAULT_SETTINGS.signature_mode
	end

	return SIGNATURE_VARIANT_LABELS[mode]
end

local function resolve_signature_mode(mode)
	mode = math.floor(tonumber(mode) or SETTINGS.signature_mode or DEFAULT_SETTINGS.signature_mode)

	if mode < 1 or mode > #SIGNATURE_VARIANT_LABELS then
		mode = DEFAULT_SETTINGS.signature_mode
	end

	if mode == RANDOM_SIGNATURE_MODE then
		return math.random(1, RANDOM_SIGNATURE_MODE - 1)
	end

	return mode
end

local function get_signature_preview_text(admin_name, mode, request)
	if request and request.signature_mode_used then
		return get_signature_text(admin_name, request.signature_mode_used)
	end

	if math.floor(tonumber(mode) or DEFAULT_SETTINGS.signature_mode) == RANDOM_SIGNATURE_MODE then
		return "случайный формат из списка"
	end

	return get_signature_text(admin_name, mode)
end

local function command_supports_signature(request)
	if request == nil then
		return false
	end

	if request.kind == "/jail"
		or request.kind == "/kick"
		or request.kind == "/sban"
		or request.kind == "/warn"
		or request.kind == "/ban"
		or request.kind == "/msg"
		or request.kind == "/offban"
		or request.kind == "/offwarn"
		or request.kind == "/offmute"
		or request.kind == "/offjail" then
		return true
	end

	if request.kind == "/mute" then
		return request.command_text:match("^/mute%s+%d+%s+%d+%s+.+$") ~= nil
	end

	return false
end

local function build_issued_command(request)
	local command_text = trim(request and request.command_text or "")

	if request == nil or command_text == "" or not command_supports_signature(request) then
		return command_text
	end

	local signature_text = trim(get_signature_text(request.admin_name, request.signature_mode_used or SETTINGS.signature_mode))

	if signature_text == "" then
		return command_text
	end

	local normalized_command = lower(command_text)
	local normalized_signature = lower(signature_text)

	if #normalized_signature > 0 and normalized_command:sub(-#normalized_signature) == normalized_signature then
		return command_text
	end

	return command_text .. " " .. signature_text
end

local function is_online_punish_command(kind)
	return kind == "/jail"
		or kind == "/mute"
		or kind == "/kick"
		or kind == "/skick"
		or kind == "/sban"
		or kind == "/warn"
		or kind == "/ban"
end

local function is_online_notice_command(kind)
	return kind == "/jail"
		or kind == "/mute"
		or kind == "/kick"
		or kind == "/skick"
		or kind == "/sban"
		or kind == "/warn"
		or kind == "/ban"
end

local function is_online_offline_switch_command(kind)
	return kind == "/warn"
		or kind == "/offwarn"
		or kind == "/unwarn"
		or kind == "/ban"
		or kind == "/offban"
		or kind == "/jail"
		or kind == "/offjail"
		or kind == "/unmute"
		or kind == "/unjail"
		or kind == "/mute"
		or kind == "/offmute"
		or kind == "/sban"
end

local function is_online_switch_target_kind(kind)
	return kind == "/warn"
		or kind == "/unwarn"
		or kind == "/ban"
		or kind == "/jail"
		or kind == "/unmute"
		or kind == "/unjail"
		or kind == "/mute"
		or kind == "/sban"
end

local function is_offline_switch_target_kind(kind)
	return kind == "/offwarn"
		or kind == "/offban"
		or kind == "/offjail"
		or kind == "/offmute"
		or kind == "/sban"
end

local function get_switch_target_name(target_name, target_label)
	target_name = trim(tostring(target_name or ""))

	if target_name ~= "" then
		return target_name
	end

	target_label = trim(tostring(target_label or ""))

	if target_label == "" then
		return ""
	end

	if target_label:match("^ID%s+%d+$") then
		return ""
	end

	return trim((target_label:gsub("%[%d+%]$", "")))
end

local function build_online_offline_switch_context(request, command_text, batch_id)
	if SETTINGS.auto_switch_online_offline ~= true or request == nil or not is_online_offline_switch_command(request.kind) then
		return nil
	end

	local target_name = get_switch_target_name(request.target_name, request.target_label)

	if (request.kind == "/warn" or request.kind == "/ban" or request.kind == "/jail" or request.kind == "/mute" or request.kind == "/sban") and target_name == "" then
		return nil
	end

	return {
		batch_id = batch_id,
		admin_name = tostring(request.admin_name or ""),
		target_name = tostring(target_name),
		target_label = tostring(request.target_label or ""),
		target_id = request.target_id,
		kind = tostring(request.kind or ""),
		command_text = trim(tostring(command_text or request.command_text or "")),
		created_at = os.clock()
	}
end

local function is_target_id_online(target_id)
	if target_id == nil then
		return false
	end

	local has_local_id, local_id = sampGetPlayerIdByCharHandle(PLAYER_PED)

	if not has_local_id then
		local_id = nil
	end

	if local_id ~= nil and tonumber(target_id) == tonumber(local_id) then
		return true
	end

	return sampIsPlayerConnected(target_id)
end

local function is_request_target_online(request)
	return request ~= nil
		and request.target_id ~= nil
		and is_target_id_online(request.target_id)
end

local is_punish_command

local function should_send_pre_punish_notice(request)
	return request ~= nil
		and SETTINGS.pre_punish_notice_enabled == true
		and is_request_target_online(request)
		and is_forum_notice_command(request.kind)
end

local function should_watch_database_lookup_result(request)
	return request ~= nil
		and request.admin_name ~= nil
		and request.admin_name ~= ""
        and ((request.target_id == nil and is_punish_command(request.kind))
            or request.kind == '/warn' or request.kind == '/unwarn' or request.kind == '/unban')
end

local function should_watch_punishment_conflict(request)
	return request ~= nil
		and request.target_name ~= nil
		and trim(request.target_name) ~= ""
		and is_punish_command(request.kind)
end

local function get_pre_punish_notice_lines()
	local lines = {}
	local source_lines = {
		SETTINGS.forum_notice_line_1,
		SETTINGS.forum_notice_line_2,
		SETTINGS.forum_notice_line_3
	}

	for _, line in ipairs(source_lines) do
		line = trim(tostring(line or ""))

		if line ~= "" then
			table.insert(lines, line)
		end
	end

	return lines
end

function get_stackable_term_context(request, command_text, batch_id)
	if request == nil then
		return nil
	end

	command_text = trim(command_text or request.command_text or "")
	local command_name = get_command_name_from_text(command_text)
	local target_token, minutes, reason
	local action_kind

	if command_name == "/jail" then
		target_token, minutes, reason = command_text:match("^/jail%s+(%S+)%s+(%d+)%s+(.+)$")
		action_kind = "jail"
	elseif command_name == "/offjail" then
		target_token, minutes, reason = command_text:match("^/offjail%s+(%S+)%s+(%d+)%s+(.+)$")
		action_kind = "jail"
	elseif command_name == "/mute" then
		target_token, minutes, reason = command_text:match("^/mute%s+(%S+)%s+(%d+)%s+(.+)$")
		action_kind = "mute"
	elseif command_name == "/offmute" then
		target_token, minutes, reason = command_text:match("^/offmute%s+(%S+)%s+(%d+)%s+(.+)$")
		action_kind = "mute"
	end

	if (action_kind == "jail" and not SETTINGS.stack_jail_enabled) or (action_kind == "mute" and not SETTINGS.stack_mute_enabled) then return nil end
	if target_token == nil or minutes == nil or reason == nil then
		return nil
	end

	return {
		batch_id = batch_id,
		action_kind = action_kind,
		command_name = command_name,
		command_text = command_text,
		target_token = target_token,
		target_id = request.target_id,
		target_name = get_switch_target_name(request.target_name, request.target_label),
		new_minutes = tonumber(minutes) or 0,
		reason = trim(reason),
		created_at = os.clock()
	}
end

local function enqueue_outgoing_command(command_text, source, response_context, batch_id, is_punishment_command, switch_context, stack_term_context, delay_seconds, ban_requester)
	if not integration.access:require(2, function(reason) message(reason, true) end) or not integration.commandAllowed(command_text) then return end
	command_text = trim(command_text)

	if command_text == "" then
		return
	end

	delay_seconds = tonumber(delay_seconds) or 0

	table.insert(state.outgoing_queue, {
		accessRevision = integration.access:revision(),
		command_text = command_text,
		source = source or "queue",
		response_context = response_context,
        ban_requester = ban_requester,
		batch_id = batch_id,
		is_punishment_command = is_punishment_command == true,
		switch_context = switch_context,
		stack_term_context = stack_term_context,
		ready_at = delay_seconds > 0 and (os.clock() + delay_seconds) or nil
	})
end

local function remove_outgoing_batch_items(batch_id)
	if batch_id == nil then
		return 0
	end

	local kept = {}
	local removed = 0

	for _, item in ipairs(state.outgoing_queue) do
		if item.batch_id ~= batch_id then
			table.insert(kept, item)
		else
			removed = removed + 1
		end
	end

	state.outgoing_queue = kept
	return removed
end

local function queue_pre_punish_bundle(request, punishment_command, source)
	if not integration.commandAllowed(punishment_command) then return end
	state.next_outgoing_batch_id = (tonumber(state.next_outgoing_batch_id) or 0) + 1
	local batch_id = state.next_outgoing_batch_id

	if should_send_pre_punish_notice(request) then
		for _, notice_line in ipairs(get_pre_punish_notice_lines()) do
			enqueue_outgoing_command(string.format("/ans %d %s", request.target_id, notice_line), source, nil, batch_id, false)
		end
	end

	local response_context = nil

	if should_watch_database_lookup_result(request) then
		response_context = {
			batch_id = batch_id,
			admin_name = tostring(request.admin_name or ""),
			target_name = tostring(request.target_name or ""),
			kind = tostring(request.kind or ""),
			created_at = os.clock()
		}
	end

	if should_watch_punishment_conflict(request) then
		state.awaiting_punishment_guard_context = {
			batch_id = batch_id,
			admin_name = tostring(request.admin_name or ""),
			target_name = tostring(request.target_name or ""),
			target_label = tostring(request.target_label or ""),
			target_id = request.target_id,
			kind = tostring(request.kind or ""),
			created_at = os.clock()
		}
	end

	enqueue_outgoing_command(
		punishment_command,
		source,
		response_context,
		batch_id,
		true,
		build_online_offline_switch_context(request, punishment_command, batch_id),
		get_stackable_term_context(request, punishment_command, batch_id),
        nil, source=='auto-confirm' and request.admin_name or nil
	)
end

local function send_outgoing_command_internal(command_text, source, response_context, switch_context, stack_term_context, ban_requester)
	if not integration.access:require(2, function(reason) message(reason, true) end) or not integration.commandAllowed(command_text) then return false end
	state.bypass_outgoing_hook = state.bypass_outgoing_hook + 1

	local ok, err

	if source == "script-tr-command" then
		local target=command_text:match("^/tr%s+(%d+)")
		ok, err = pcall(integration.invoke, "tr", target or "")
	else
		if command_text:match('^/offban%s') or command_text:match('^/ban%s') or command_text:match('^/sban%s') then
            ok,err=pcall(integration.sendBan,command_text,ban_requester)
        else ok, err = pcall(sampSendChat, utf8_to_cp1251(command_text)) end
	end

	state.bypass_outgoing_hook = math.max(0, state.bypass_outgoing_hook - 1)

	if not ok or err == false then
		append_log(string.format("Ошибка отправки команды (%s): %s", source or "internal", tostring(err)))
		debug_message(string.format("Ошибка отправки команды (%s): %s", source or "internal", tostring(err)), true)
		return false
	end

    if response_context ~= nil then
        -- Start the response window after sending, not while waiting for confirmation.
        response_context.created_at=os.clock()
        response_context.sent_at=response_context.created_at
        state.awaiting_database_lookup_context=response_context
    end

	if switch_context ~= nil then
		state.awaiting_online_offline_switch_context = switch_context
	end

	if stack_term_context ~= nil then
		state.awaiting_stack_term_context = stack_term_context
	end

	return true
end

local function process_outgoing_queue()
	if #state.outgoing_queue == 0 then
		return
	end
	if not integration.access:require(2, function(reason) message(reason, true) end)
		or state.outgoing_queue[1].accessRevision ~= integration.access:revision() then
		integration.onDisconnect()
		return
	end

	if os.clock() < state.next_outgoing_at then
		return
	end

	local first_item = state.outgoing_queue[1]

	if first_item ~= nil and first_item.ready_at ~= nil and os.clock() < first_item.ready_at then
		return
	end

    if first_item and first_item.chain_request then
        local request=first_item.chain_request
        if request.target_id and (not sampIsPlayerConnected(request.target_id)
            or lower(sampGetPlayerNickname(request.target_id))~=lower(request.target_name)) then
            remove_outgoing_batch_items(first_item.batch_id)
            message('Цепочка отменена: игрок вышел или ID сменил владельца.',true);return
        end
    end
	local item = table.remove(state.outgoing_queue, 1)

	if item == nil then
		return
	end

	if state.awaiting_punishment_guard_context ~= nil
		and item.is_punishment_command
		and item.batch_id == state.awaiting_punishment_guard_context.batch_id then
		state.awaiting_punishment_guard_context = nil
	end

	debug_message(string.format("Очередь отправки (%s): %s", item.source or "queue", item.command_text), false)
    local sent=send_outgoing_command_internal(item.command_text, item.source or "queue", item.response_context, item.switch_context, item.stack_term_context, item.ban_requester)
    if not sent and item.chain then remove_outgoing_batch_items(item.batch_id) end
	state.next_outgoing_at = os.clock() + OUTGOING_QUEUE_INTERVAL
    local nextItem=state.outgoing_queue[1]
    if item.chain and nextItem and nextItem.chain and item.batch_id==nextItem.batch_id then
        nextItem.ready_at=os.clock()+(nextItem.chain_delay or 0)
    end
end

ensure_data_dir = nil

local function write_all(path, content)
	local file = assert(io.open(path, "wb"))
	assert(file:write(content))
	assert(file:close())
end

local function pack_u16_le(value)
	value = math.floor(tonumber(value) or 0) % 65536
	return string.char(value % 256, math.floor(value / 256) % 256)
end

local function pack_u32_le(value)
	value = math.floor(tonumber(value) or 0)
	return string.char(
		value % 256,
		math.floor(value / 256) % 256,
		math.floor(value / 65536) % 256,
		math.floor(value / 16777216) % 256
	)
end

local function pack_s16_le(value)
	value = math.floor(tonumber(value) or 0)

	if value < 0 then
		value = 65536 + value
	end

	return pack_u16_le(value)
end

local function build_notify_sound_wav()
	local sample_rate = 22050
	local duration = 0.075
	local total_samples = math.floor(sample_rate * duration)
	local samples = {}

	for index = 0, total_samples - 1 do
		local time = index / sample_rate
		local decay = math.exp(-42 * time)
		local body = math.sin(2 * math.pi * 1450 * time) * 0.18
		local edge = math.sin(2 * math.pi * 2300 * time) * 0.10
		local snap = math.sin(2 * math.pi * 3100 * time) * 0.06
		local pulse = math.sin(2 * math.pi * 92 * time) * 0.05
		local noise_seed = math.sin((index + 1) * 12.9898) * 43758.5453
		local noise = ((noise_seed - math.floor(noise_seed)) * 2 - 1) * 0.08
		local transient = math.exp(-160 * time)
		local value = (body + edge + snap + pulse) * decay + noise * transient

		value = math.max(-0.42, math.min(0.42, value))
		samples[#samples + 1] = pack_s16_le(math.floor(value * 32767))
	end

	local pcm_data = table.concat(samples)
	local byte_rate = sample_rate * 2
	local block_align = 2
	local header = table.concat({
		"RIFF",
		pack_u32_le(36 + #pcm_data),
		"WAVE",
		"fmt ",
		pack_u32_le(16),
		pack_u16_le(1),
		pack_u16_le(1),
		pack_u32_le(sample_rate),
		pack_u32_le(byte_rate),
		pack_u16_le(block_align),
		pack_u16_le(16),
		"data",
		pack_u32_le(#pcm_data)
	})

	return header .. pcm_data
end

local function ensure_notify_sound_file()
	if doesFileExist(NOTIFY_SOUND_FILE) then
		return
	end

	write_all(NOTIFY_SOUND_FILE, build_notify_sound_wav())
end

ensure_data_dir = function()
	if not doesDirectoryExist(DATA_DIR) then
		createDirectory(DATA_DIR)
	end
end

local function ensure_files()
	ensure_data_dir()

	if not doesFileExist(LOG_FILE) then
		write_all(LOG_FILE, "")
	end

	if not doesFileExist(REQUEST_LOG_FILE) then
		write_all(REQUEST_LOG_FILE, "")
	end

	if not doesFileExist(DEBUG_LOG_FILE) then
		write_all(DEBUG_LOG_FILE, "")
	end

	if not doesFileExist(LOCAL_ADMINS_FILE) then
		write_all(LOCAL_ADMINS_FILE, "# один ник с новой строки\n")
	end

	ensure_notify_sound_file()
end

local function copy_defaults()
	for key, value in pairs(DEFAULT_SETTINGS) do
		SETTINGS[key] = value
	end
end

local function clamp_number(value, min_value, max_value, fallback)
	value = tonumber(value) or fallback

	if value < min_value then
		value = min_value
	elseif value > max_value then
		value = max_value
	end

	return math.floor(value)
end

local function sanitize_settings()
    for _,key in ipairs({'stack_jail_enabled','stack_mute_enabled','stack_notice_enabled'})do SETTINGS[key]=SETTINGS[key]~=false end
    SETTINGS.queue_limit=math.floor(clamp_number(SETTINGS.queue_limit,1,100,20))
    SETTINGS.queue_max_age=clamp_number(SETTINGS.queue_max_age,10,600,120)
    for _,key in ipairs({'stack_notice_template','custom_signature','command_chains'})do SETTINGS[key]=tostring(SETTINGS[key] or DEFAULT_SETTINGS[key]) end
    state.command_chains=rules.chains(SETTINGS.command_chains) or {}

	SETTINGS.enabled = SETTINGS.enabled ~= false
	SETTINGS.show_chat_messages = SETTINGS.show_chat_messages ~= false
	SETTINGS.request_timeout = clamp_number(SETTINGS.request_timeout, 1, 60, DEFAULT_SETTINGS.request_timeout)
	SETTINGS.admin_chat_color = math.floor(tonumber(SETTINGS.admin_chat_color) or DEFAULT_SETTINGS.admin_chat_color)
	SETTINGS.confirm_key = clamp_number(SETTINGS.confirm_key, 1, 255, DEFAULT_SETTINGS.confirm_key)
	SETTINGS.cancel_key = clamp_number(SETTINGS.cancel_key, 1, 255, DEFAULT_SETTINGS.cancel_key)
	SETTINGS.block_known_admin_targets = SETTINGS.block_known_admin_targets ~= false
	SETTINGS.auto_cancel_on_activity = SETTINGS.auto_cancel_on_activity ~= false
	SETTINGS.log_captured_requests = SETTINGS.log_captured_requests ~= false
	SETTINGS.debug_enabled = SETTINGS.debug_enabled ~= false
	SETTINGS.sound_notify_enabled = SETTINGS.sound_notify_enabled ~= false
	SETTINGS.show_final_command_message = SETTINGS.show_final_command_message ~= false
	SETTINGS.show_request_overlay = SETTINGS.show_request_overlay ~= false
	SETTINGS.signature_mode = clamp_number(SETTINGS.signature_mode, 1, #SIGNATURE_VARIANT_LABELS, DEFAULT_SETTINGS.signature_mode)
	SETTINGS.pre_punish_notice_enabled = SETTINGS.pre_punish_notice_enabled ~= false
	SETTINGS.auto_switch_online_offline = SETTINGS.auto_switch_online_offline == true
	SETTINGS.track_other_admin_punishments = SETTINGS.track_other_admin_punishments ~= false
	SETTINGS.forum_notice_line_1 = tostring(SETTINGS.forum_notice_line_1 or DEFAULT_PRE_PUNISH_NOTICE_LINE_1)
	SETTINGS.forum_notice_line_2 = tostring(SETTINGS.forum_notice_line_2 or DEFAULT_PRE_PUNISH_NOTICE_LINE_2)
	SETTINGS.forum_notice_line_3 = tostring(SETTINGS.forum_notice_line_3 or DEFAULT_PRE_PUNISH_NOTICE_LINE_3)
	SETTINGS.forum_notice_commands_text = tostring(SETTINGS.forum_notice_commands_text or DEFAULT_FORUM_NOTICE_COMMANDS_TEXT)
	SETTINGS.no_notice_commands_text = tostring(SETTINGS.no_notice_commands_text or DEFAULT_NO_NOTICE_COMMANDS_TEXT)
	SETTINGS.admin_chat_commands_text = tostring(SETTINGS.admin_chat_commands_text or DEFAULT_ADMIN_CHAT_COMMANDS_TEXT)
	SETTINGS.report_commands_text = tostring(SETTINGS.report_commands_text or DEFAULT_REPORT_COMMANDS_TEXT)
	rebuild_command_groups()
end

local function serialize_flat_table(table_value)
	local keys = {}

	for key in pairs(table_value) do
		table.insert(keys, key)
	end

	table.sort(keys)

	local lines = {
		"return {"
	}

	for _, key in ipairs(keys) do
		local value = table_value[key]
		local serialized

		if type(value) == "string" then
			serialized = string.format("%q", value)
		else
			serialized = tostring(value)
		end

		table.insert(lines, string.format("    %s = %s,", key, serialized))
	end

	table.insert(lines, "}")
	return table.concat(lines, "\n") .. "\n"
end

local function save_settings_file()
	ensure_data_dir()
	sanitize_settings()
	return storage:write(SETTINGS_FILE, serialize_flat_table(SETTINGS))
end

local function load_settings_file()
	copy_defaults()

	local loaded = storage:loadTable(SETTINGS_FILE)
	if loaded then
		for key, value in pairs(loaded) do
			if DEFAULT_SETTINGS[key] ~= nil then
				SETTINGS[key] = value
			end
		end

		if loaded.admin_chat_commands_text == nil and type(loaded.reactive_commands_text) == "string" and trim(loaded.reactive_commands_text) ~= "" then
			SETTINGS.admin_chat_commands_text = loaded.reactive_commands_text
		end
	end

	sanitize_settings()
end

local function get_key_name(key_code)
	if type(vkeys.id_to_name) == "function" then
		local ok, key_name = pcall(vkeys.id_to_name, key_code)

		if ok and key_name and key_name ~= "" then
			return key_name
		end
	end

	return tostring(key_code)
end

local function sync_ui_from_settings()
    chain_editor=nil
	if not ui then
		return
	end

	for _,key in ipairs({'stack_jail_enabled','stack_mute_enabled','stack_notice_enabled','queue_limit','queue_max_age'})do ui[key][0]=SETTINGS[key] end
    for _,key in ipairs({'stack_notice_template','custom_signature','command_chains'})do set_imgui_buffer(ui[key],SETTINGS[key]) end
    draft_keys=rules.keyDraft(integration.keys)
	ui.enabled[0] = SETTINGS.enabled
	ui.show_chat_messages[0] = SETTINGS.show_chat_messages
	ui.request_timeout[0] = SETTINGS.request_timeout
	ui.admin_chat_color[0] = SETTINGS.admin_chat_color
	ui.block_known_admin_targets[0] = SETTINGS.block_known_admin_targets
	ui.auto_cancel_on_activity[0] = SETTINGS.auto_cancel_on_activity
	ui.log_captured_requests[0] = SETTINGS.log_captured_requests
	ui.debug_enabled[0] = SETTINGS.debug_enabled
	ui.sound_notify_enabled[0] = SETTINGS.sound_notify_enabled
	ui.show_final_command_message[0] = SETTINGS.show_final_command_message
	ui.show_request_overlay[0] = SETTINGS.show_request_overlay
	ui.signature_mode[0] = SETTINGS.signature_mode
	ui.pre_punish_notice_enabled[0] = SETTINGS.pre_punish_notice_enabled
	ui.auto_switch_online_offline[0] = SETTINGS.auto_switch_online_offline
	ui.track_other_admin_punishments[0] = SETTINGS.track_other_admin_punishments
	set_imgui_buffer(ui.forum_notice_line_1, SETTINGS.forum_notice_line_1)
	set_imgui_buffer(ui.forum_notice_line_2, SETTINGS.forum_notice_line_2)
	set_imgui_buffer(ui.forum_notice_line_3, SETTINGS.forum_notice_line_3)
	set_imgui_buffer(ui.forum_notice_commands_text, SETTINGS.forum_notice_commands_text)
	set_imgui_buffer(ui.no_notice_commands_text, SETTINGS.no_notice_commands_text)
	set_imgui_buffer(ui.admin_chat_commands_text, SETTINGS.admin_chat_commands_text)
	set_imgui_buffer(ui.report_commands_text, SETTINGS.report_commands_text)
end

local function apply_ui_to_settings()
	if not ui then
		return
	end

	for _,key in ipairs({'stack_jail_enabled','stack_mute_enabled','stack_notice_enabled','queue_limit','queue_max_age'})do SETTINGS[key]=ui[key][0] end
    for _,key in ipairs({'stack_notice_template','custom_signature','command_chains'})do SETTINGS[key]=get_imgui_buffer_text(ui[key]) end
	SETTINGS.enabled = ui.enabled[0]
	SETTINGS.show_chat_messages = ui.show_chat_messages[0]
	SETTINGS.request_timeout = ui.request_timeout[0]
	SETTINGS.admin_chat_color = ui.admin_chat_color[0]
	SETTINGS.block_known_admin_targets = ui.block_known_admin_targets[0]
	SETTINGS.auto_cancel_on_activity = ui.auto_cancel_on_activity[0]
	SETTINGS.log_captured_requests = ui.log_captured_requests[0]
	SETTINGS.debug_enabled = ui.debug_enabled[0]
	SETTINGS.sound_notify_enabled = ui.sound_notify_enabled[0]
	SETTINGS.show_final_command_message = ui.show_final_command_message[0]
	SETTINGS.show_request_overlay = ui.show_request_overlay[0]
	SETTINGS.signature_mode = ui.signature_mode[0]
	SETTINGS.pre_punish_notice_enabled = ui.pre_punish_notice_enabled[0]
	SETTINGS.auto_switch_online_offline = ui.auto_switch_online_offline[0]
	SETTINGS.track_other_admin_punishments = ui.track_other_admin_punishments[0]
	SETTINGS.forum_notice_line_1 = get_imgui_buffer_text(ui.forum_notice_line_1)
	SETTINGS.forum_notice_line_2 = get_imgui_buffer_text(ui.forum_notice_line_2)
	SETTINGS.forum_notice_line_3 = get_imgui_buffer_text(ui.forum_notice_line_3)
	SETTINGS.forum_notice_commands_text = get_imgui_buffer_text(ui.forum_notice_commands_text)
	SETTINGS.no_notice_commands_text = get_imgui_buffer_text(ui.no_notice_commands_text)
	SETTINGS.admin_chat_commands_text = get_imgui_buffer_text(ui.admin_chat_commands_text)
	SETTINGS.report_commands_text = get_imgui_buffer_text(ui.report_commands_text)

	sanitize_settings()
end

local function split_command_lines(raw_text)
	local rows = {}

	for line in tostring(raw_text or ""):gmatch("[^\r\n]+") do
		local clean = trim(line)

		if clean ~= "" then
			table.insert(rows, clean)
		end
	end

	if #rows == 0 then
		table.insert(rows, "")
	end

	return rows
end

local function join_command_lines(rows, group_key)
	local result = {}

	for _, row in ipairs(rows or {}) do
        local disabled=tostring(row or ""):match("^%s*;")~=nil
        row=tostring(row or ""):gsub("^%s*;%s*", "")
		local clean = nil

		if group_key == "report" then
			local command_part, template_part = tostring(row or ""):match("^%s*(.-)%s*|%s*(.-)%s*$")
			local command_name = normalize_command_name(command_part or row)

			if command_name ~= nil then
				template_part = trim(template_part or "")

				if template_part ~= "" then
					clean = command_name .. " | " .. template_part
				else
					clean = command_name
				end
			end
		else
			clean = normalize_command_name(row)
		end

		if clean ~= nil and clean ~= "" then
			table.insert(result, (disabled and "; " or "") .. clean)
		end
	end

	return table.concat(result, "\n")
end

local function create_editor_row_buffer(text)
	local buffer = imgui.new.char[512]()
	set_imgui_buffer(buffer, text or "")
	return buffer
end

local function get_group_config(group_key)
	return COMMAND_GROUPS[group_key]
end

local function get_group_text_from_ui(group_key)
	local config = get_group_config(group_key)

	if not ui or not config then
		return ""
	end

	return get_imgui_buffer_text(ui[config.ui_key])
end

local function set_group_text_to_ui(group_key, raw_text)
	local config = get_group_config(group_key)

	if not ui or not config then
		return
	end

	set_imgui_buffer(ui[config.ui_key], raw_text)
end

local function open_command_editor(group_key)
	if not command_editor then
		return
	end

	local config = get_group_config(group_key)

	if not config then
		return
	end

	command_editor.group_key = group_key
	command_editor.rows = {}
    command_editor.disabled = {}

	for _, line in ipairs(split_command_lines(get_group_text_from_ui(group_key))) do
        local disabled=line:match("^%s*;")~=nil
        line=line:gsub("^%s*;%s*", "")
		if group_key == "report" then
			local command_name, template = split_report_command_line(line)

			if command_name ~= nil and (template == nil or template == "") then
				line = command_name .. " | " .. get_default_report_template(command_name)
			end
		end

		local buffer=create_editor_row_buffer(line)
        table.insert(command_editor.rows, buffer)
        command_editor.disabled[buffer]=disabled
	end

	command_editor.window[0] = true
end

local function close_command_editor()
	if not command_editor then
		return
	end

	command_editor.window[0] = false
	command_editor.group_key = nil
	command_editor.rows = {}
end

local function add_command_editor_row(text)
	if not command_editor then
		return
	end

	table.insert(command_editor.rows, create_editor_row_buffer(text or ""))
end

local function remove_command_editor_row(index)
	if not command_editor or not command_editor.rows[index] then
		return
	end

	table.remove(command_editor.rows, index)

	if #command_editor.rows == 0 then
		add_command_editor_row("")
	end
end

local function save_command_editor()
	if not command_editor or command_editor.group_key == nil then
		return
	end

	local rows = {}

	for _, row_buffer in ipairs(command_editor.rows) do
		table.insert(rows, (command_editor.disabled[row_buffer] and "; " or "") .. get_imgui_buffer_text(row_buffer))
	end

	set_group_text_to_ui(command_editor.group_key, join_command_lines(rows, command_editor.group_key))
    message("Список изменён. Нажмите «Сохранить» в настройках, чтобы применить изменения.", "settings")
	close_command_editor()
end

local function get_group_preview_lines(group_key, limit)
	local lines = {}
	local preview = {}
	limit = math.max(1, tonumber(limit) or 3)

	for line in tostring(get_group_text_from_ui(group_key) or ""):gmatch("[^\r\n]+") do
		local clean = normalize_command_name(line)

		if clean ~= nil and clean ~= "" then
			table.insert(lines, clean)
		end
	end

	for index = 1, math.min(#lines, limit) do
		table.insert(preview, lines[index])
	end

	return preview, #lines
end

local function load_known_admins()
	local files = {
		{ path = ADM_CHECKER_ADMINS_FILE, kind = "admin" },
		{ path = ADM_CHECKER_ADMINS_TXT_FILE, kind = "admin" },
		{ path = ADM_CHECKER_LEADERS_FILE, kind = "leader" },
		{ path = ADM_CHECKER_LEADERS_TXT_FILE, kind = "leader" }
	}
	local unique = {}
	local admins = {}
	local leaders = {}

	for _, source in ipairs(files) do
		local file = io.open(source.path, "r")

		if file then
			while true do
				local line = file:read("*l")

				if line == nil then
					break
				end

				local clean = trim(line)

				if clean ~= "" and clean:sub(1, 1) ~= "#" then
					local nickname = clean:match("^([^|%s]+)")

					if nickname and nickname:match("^[%w_%.%[%]%(%)$=@]+$") and not nickname:match("^%d+$") then
						unique[lower(nickname)] = nickname

						if source.kind == "leader" then
							leaders[lower(nickname)] = nickname
						else
							admins[lower(nickname)] = nickname
						end
					end
				end
			end

			file:close()
		end
	end

	state.known_admins = unique
	state.known_admin_count = 0
	state.known_admin_only_count = 0
	state.known_leader_count = 0

	for _ in pairs(unique) do
		state.known_admin_count = state.known_admin_count + 1
	end

	for _ in pairs(admins) do
		state.known_admin_only_count = state.known_admin_only_count + 1
	end

	for _ in pairs(leaders) do
		state.known_leader_count = state.known_leader_count + 1
	end

	debug_message(string.format("Загружен список администраторов и лидеров: админов %d, лидеров %d, всего %d.", state.known_admin_only_count, state.known_leader_count, state.known_admin_count), false)
end

local function get_local_identity()
	local has_id, local_id = sampGetPlayerIdByCharHandle(PLAYER_PED)

	if not has_id or local_id == nil then
		return nil, nil
	end

	if sampIsPlayerConnected(local_id) then
		return local_id, sampGetPlayerNickname(local_id)
	end

	return local_id, nil
end

local function is_known_admin(nickname)
	if nickname == nil or nickname == "" then
		return false
	end

    local current = integration.isKnownAdmin(nickname)
    if current ~= nil then return current end
    return state.known_admins[lower(nickname)] ~= nil
end

is_punish_command = function(kind)
	return kind == "/jail"
		or kind == "/mute"
		or kind == "/kick"
		or kind == "/skick"
		or kind == "/sban"
		or kind == "/warn"
		or kind == "/ban"
		or kind == "/offban"
		or kind == "/offwarn"
		or kind == "/offmute"
		or kind == "/offjail"
end

local function get_online_target_label(target_id)
	local local_id, local_name = get_local_identity()

	if local_id ~= nil and tonumber(target_id) == tonumber(local_id) and local_name and local_name ~= "" then
		return string.format("%s[%d]", local_name, target_id), local_name
	end

	if not sampIsPlayerConnected(target_id) then
		return nil
	end

	local target_name = sampGetPlayerNickname(target_id)
	return string.format("%s[%d]", target_name, target_id), target_name
end

local function get_notice_target_label(target_id)
	local local_id, local_name = get_local_identity()

	if local_id ~= nil and tonumber(target_id) == tonumber(local_id) and local_name and local_name ~= "" then
		return string.format("%s[%d]", local_name, target_id), local_name
	end

	if sampIsPlayerConnected(target_id) then
		local target_name = sampGetPlayerNickname(target_id)

		if target_name and target_name ~= "" then
			return string.format("%s[%d]", target_name, target_id), target_name
		end
	end

	return string.format("ID %d", target_id), nil
end

local function build_request(admin_name, admin_id, command_text, target_label, target_id, target_name)
	local kind = command_text:match("^(%S+)") or ""

	return {
		admin_name = admin_name,
		admin_id = tonumber(admin_id),
		command_text = command_text,
		target_label = target_label,
		target_id = target_id,
		target_name = target_name,
		kind = lower(kind),
		created_at = os.clock(),
		signature_mode_used = nil
	}
end

local parse_supported_command

local function get_msg_request_label(msg_mode)
	msg_mode = trim(tostring(msg_mode or ""))

	if msg_mode == "0" then
		return "сообщение для всех"
	end

	if msg_mode == "1" then
		return "важное сообщение для всех"
	end

	if msg_mode:match("^%d+$") then
		return "сообщение в радиусе " .. msg_mode
	end

	return "сообщение /msg"
end

local function parse_generic_admin_chat_command(admin_name, admin_id, command_text)
	command_text = trim(command_text)

	if command_text == "" then
		return nil
	end

	if command_text:sub(1, 1) ~= "/" then
		command_text = "/" .. command_text
	end

	local command_name, rest = command_text:match("^(%S+)%s*(.*)$")
	local target_token = trim((rest or ""):match("^(%S+)") or "")
	local normalized_command_name = lower(command_name or "")

	if not is_admin_chat_command(command_name) or target_token == "" then
		return nil
	end

	if normalized_command_name == "/msg" then
		local msg_mode, msg_text = command_text:match("^/msg%s+(%S+)%s+(.+)$")

		if msg_mode and trim(msg_text) ~= "" then
			return build_request(admin_name, admin_id, command_text, get_msg_request_label(msg_mode), nil, nil)
		end

		return nil
	end

	if target_token:match("^%d+$") then
		local target_id = tonumber(target_token)
		local target_label, target_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, target_name)
		end

		return false
	end

	return build_request(admin_name, admin_id, command_text, target_token, nil, target_token)
end

local function split_command_args(command_text)
	local args = {}
	local args_text = tostring(command_text or ""):match("^%S+%s+(.+)$") or ""

	for arg in args_text:gmatch("%S+") do
		table.insert(args, arg)
	end

	return args, args_text
end

local function render_report_template(template, context)
	local values = {
		admin = context.admin_name or "",
		admin_id = tostring(context.admin_id or ""),
		target = context.target_label or context.target_token or "",
		target_id = tostring(context.target_id or context.target_token or ""),
		target_name = context.target_name or context.target_token or "",
		command = context.command_text or "",
		cmd = context.command_name or "",
		args = context.args_text or "",
		text = context.rest_text or ""
	}

	for index, arg in ipairs(context.args or {}) do
		values["arg" .. tostring(index)] = arg
	end

	return tostring(template or ""):gsub("{([%w_]+)}", function(key)
		return values[key] or ""
	end)
end

local function parse_report_admin_chat_command(admin_name, admin_id, command_text)
	command_text = trim(command_text)

	if command_text ~= "" and command_text:sub(1, 1) ~= "/" then
		command_text = "/" .. command_text
	end

	local command_name = get_command_name_from_text(command_text)

	if not is_report_command(command_name) then
		return nil
	end

	local args, args_text = split_command_args(command_text)
	local target_token = args[1]

	if target_token == nil or target_token == "" then
		return nil
	end

	local target_id = nil
	local target_label = target_token
	local target_name = target_token

	if target_token:match("^%d+$") then
		target_id = tonumber(target_token)
		target_label, target_name = get_online_target_label(target_id)

		if target_label == nil then
			return false
		end
	end

	local request = build_request(admin_name, admin_id, command_text, target_label, target_id, target_name)
	local rest_text = args_text:match("^%S+%s+(.+)$") or ""

	request.report_status_text = render_report_template(get_report_template(command_name), {
		admin_name = admin_name,
		admin_id = admin_id,
		target_token = target_token,
		target_id = target_id,
		target_label = target_label,
		target_name = target_name,
		command_text = command_text,
		command_name = command_name,
		args = args,
		args_text = args_text,
		rest_text = rest_text
	})

	return request
end

local function parse_tr_admin_chat_command(admin_name, admin_id, command_text)
	command_text = trim(command_text)

	if command_text ~= "" and command_text:sub(1, 1) ~= "/" then
		command_text = "/" .. command_text
	end

	local target_id = command_text:match("^/tr%s+(%d+)%s*.*$")

	if target_id == nil then
		return nil
	end

	target_id = tonumber(target_id)
	local target_label, target_name = get_online_target_label(target_id)

	if target_label then
		local request = build_request(admin_name, admin_id, command_text, target_label, target_id, target_name)
		request.script_tr_command = true

		if is_report_command("/tr") then
			local args, args_text = split_command_args(command_text)

			request.report_status_text = render_report_template(get_report_template("/tr"), {
				admin_name = admin_name,
				admin_id = admin_id,
				target_token = tostring(target_id),
				target_id = target_id,
				target_label = target_label,
				target_name = target_name,
				command_text = command_text,
				command_name = "/tr",
				args = args,
				args_text = args_text,
				rest_text = ""
			})
		end

		return request
	end

	return false
end

local function parse_admin_chat_request(admin_name, admin_id, command_text)
    local normalized, nicknamePunishment=integration.service('aegis_responses.lua').normalize(command_text)
    command_text=normalized
    local request = parse_supported_command(admin_name, admin_id, command_text)
    if request and nicknamePunishment then request.force_offline=true end

	if request ~= nil then
		return request
	end

	request = parse_tr_admin_chat_command(admin_name, admin_id, command_text)

	if request ~= nil then
		return request
	end

	request = parse_report_admin_chat_command(admin_name, admin_id, command_text)

	if request ~= nil then
		return request
	end

	return parse_generic_admin_chat_command(admin_name, admin_id, command_text)
end

parse_supported_command = function(admin_name, admin_id, command_text)
	command_text = trim(command_text)

	if command_text ~= "" and command_text:sub(1, 1) ~= "/" then
		command_text = "/" .. command_text
	end
	command_text = command_text:gsub('^(/[%a]+)',string.lower)
	command_text = integration.service('punishment_target.lua').normalize(command_text)

	local target_id, amount, reason
	local target_name
	local target_label
	local online_name

	target_id, amount, reason = command_text:match("^/jail%s+(%d+)%s+(%d+)%s+(.+)$")

	if target_id then
		target_id = tonumber(target_id)
		target_label, online_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, online_name)
		end

		return false
	end

	target_id = command_text:match("^/unjail%s+(%d+)$")

	if target_id then
		target_id = tonumber(target_id)
		target_label, online_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, online_name)
		end

		return false
	end

	target_name = command_text:match("^/unjail%s+(%S+)$")

	if target_name and not target_name:match("^%d+$") then
		return build_request(admin_name, admin_id, command_text, target_name, nil, target_name)
	end

	target_id, amount, reason = command_text:match("^/mute%s+(%d+)%s+(%d+)%s+(.+)$")

	if target_id then
		target_id = tonumber(target_id)
		target_label, online_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, online_name)
		end

		return false
	end

	target_id, amount = command_text:match("^/mute%s+(%d+)%s+(%d+)$")

	if target_id then
		target_id = tonumber(target_id)
		target_label, online_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, online_name)
		end

		return false
	end

	target_id = command_text:match("^/unmute%s+(%d+)$")

	if target_id then
		target_id = tonumber(target_id)
		target_label, online_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, online_name)
		end

		return false
	end

	target_name = command_text:match("^/unmute%s+(%S+)$")

	if target_name and not target_name:match("^%d+$") then
		return build_request(admin_name, admin_id, command_text, target_name, nil, target_name)
	end

	target_id, reason = command_text:match("^/kick%s+(%d+)%s+(.+)$")

	if target_id then
		target_id = tonumber(target_id)
		target_label, online_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, online_name)
		end

		return false
	end

	target_id = command_text:match("^/skick%s+(%d+)$")

	if target_id then
		target_id = tonumber(target_id)
		target_label, online_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, online_name)
		end

		return false
	end

	target_id, reason = command_text:match("^/warn%s+(%d+)%s+(.+)$")

	if target_id then
		target_id = tonumber(target_id)
		target_label, online_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, online_name)
		end

		return false
	end

	target_id = command_text:match("^/unwarn%s+(%d+)$")

	if target_id then
		target_id = tonumber(target_id)
		target_label, online_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, online_name)
		end

		return false
	end

	target_name = command_text:match("^/unwarn%s+(%S+)$")

	if target_name and not target_name:match("^%d+$") then
		return build_request(admin_name, admin_id, command_text, target_name, nil, target_name)
	end

	target_id, amount, reason = command_text:match("^/ban%s+(%d+)%s+(%d+)%s+(.+)$")

	if target_id then
		target_id = tonumber(target_id)
		target_label, online_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, online_name)
		end

		return false
	end

	target_id, amount, reason = command_text:match("^/sban%s+(%d+)%s+(%d+)%s+(.+)$")

	if target_id then
		target_id = tonumber(target_id)
		target_label, online_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, online_name)
		end

		return false
	end

	target_id, reason = command_text:match("^/sban%s+(%d+)%s+(.+)$")

	if target_id then
		target_id = tonumber(target_id)
		target_label, online_name = get_online_target_label(target_id)

		if target_label then
			return build_request(admin_name, admin_id, command_text, target_label, target_id, online_name)
		end

		return false
	end

	target_name, amount, reason = command_text:match("^/sban%s+(%S+)%s+(%d+)%s+(.+)$")

	if target_name and not target_name:match("^%d+$") then
		return build_request(admin_name, admin_id, command_text, target_name, nil, target_name)
	end

	target_name, reason = command_text:match("^/sban%s+(%S+)%s+(.+)$")

	if target_name and not target_name:match("^%d+$") then
		return build_request(admin_name, admin_id, command_text, target_name, nil, target_name)
	end

	target_name, amount, reason = command_text:match("^/offban%s+(%S+)%s+(%d+)%s+(.+)$")

	if target_name then
		return build_request(admin_name, admin_id, command_text, target_name, nil, target_name)
	end

	target_name, reason = command_text:match("^/offwarn%s+(%S+)%s+(.+)$")

	if target_name then
		return build_request(admin_name, admin_id, command_text, target_name, nil, target_name)
	end

	target_name, amount, reason = command_text:match("^/offmute%s+(%S+)%s+(%d+)%s+(.+)$")

	if target_name then
		return build_request(admin_name, admin_id, command_text, target_name, nil, target_name)
	end

	target_name, amount, reason = command_text:match("^/offjail%s+(%S+)%s+(%d+)%s+(.+)$")

	if target_name then
		return build_request(admin_name, admin_id, command_text, target_name, nil, target_name)
	end

	target_name = command_text:match("^/unban%s+(%S+)$")

	if target_name then
		return build_request(admin_name, admin_id, command_text, target_name, nil, target_name)
	end

	return nil
end

local function parse_manual_outgoing_request(command_text)
	command_text = trim(command_text)

	if command_text == "" then
		return nil
	end

	if command_text:sub(1, 1) ~= "/" then
		command_text = "/" .. command_text
	end

	local supported_request = parse_supported_command("", 0, command_text)

	if supported_request ~= nil and supported_request ~= false then
		return supported_request
	end

	local command_name, rest = command_text:match("^(%S+)%s*(.*)$")
	command_name = lower(command_name or "")

	local target_id = trim((rest or ""):match("^(%S+)") or "")

	if target_id == "" or not target_id:match("^%d+$") then
		return nil
	end

	target_id = tonumber(target_id)

	local target_label, target_name = get_notice_target_label(target_id)

	return {
		admin_name = "",
		admin_id = 0,
		command_text = command_text,
		target_label = target_label,
		target_id = target_id,
		target_name = target_name,
		kind = command_name,
		created_at = os.clock(),
		signature_mode_used = nil
	}
end

local function extract_online_switch_hint(text)
	text = trim(tostring(text or ""))
	text = trim(text:gsub("{%x%x%x%x%x%x}", ""))

	if text == "" then
		return nil, nil
	end

	local command_name, target_id = text:match("Используй%s+.-(/[%a]+)%s+(%d+)")

	if command_name == nil or target_id == nil then
		command_name, target_id = text:match("(/[%a]+)%s+(%d+)")
	end

	command_name = normalize_command_name(command_name)

	if command_name == nil or target_id == nil or not is_online_switch_target_kind(command_name) then
		return nil, nil
	end

	return command_name, tonumber(target_id)
end

local function extract_offline_switch_hint(text)
	text = trim(tostring(text or ""))
	text = trim(text:gsub("{%x%x%x%x%x%x}", ""))

	if text == "" then
		return nil
	end

	local command_name = normalize_command_name(text:match("(/off[%a]+)") or text:match("(/sban)"))

	if not is_offline_switch_target_kind(command_name) then
		return nil
	end

	return command_name
end

local function build_switched_command_from_context(context, suggested_kind, suggested_target_id)
	local source_kind = normalize_command_name(context and context.kind or "")
	local source_command = trim(tostring(context and context.command_text or ""))
	local target_name = get_switch_target_name(context and context.target_name or "", context and context.target_label or "")

	if source_kind == "/offwarn" and suggested_kind == "/warn" and suggested_target_id ~= nil then
		local reason = source_command:match("^/offwarn%s+%S+%s+(.+)$")

		if reason then
			return string.format("/warn %d %s", suggested_target_id, reason), "/warn", suggested_target_id, target_name
		end
	elseif source_kind == "/unwarn" and suggested_kind == "/unwarn" and suggested_target_id ~= nil then
		return string.format("/unwarn %d", suggested_target_id), "/unwarn", suggested_target_id, target_name
	elseif source_kind == "/offban" and suggested_kind == "/ban" and suggested_target_id ~= nil then
		local days, reason = source_command:match("^/offban%s+%S+%s+(%d+)%s+(.+)$")

		if days and reason then
			return string.format("/ban %d %s %s", suggested_target_id, days, reason), "/ban", suggested_target_id, target_name
		end
	elseif source_kind == "/offjail" and suggested_kind == "/jail" and suggested_target_id ~= nil then
		local minutes, reason = source_command:match("^/offjail%s+%S+%s+(%d+)%s+(.+)$")

		if minutes and reason then
			return string.format("/jail %d %s %s", suggested_target_id, minutes, reason), "/jail", suggested_target_id, target_name
		end
	elseif source_kind == "/offmute" and suggested_kind == "/mute" and suggested_target_id ~= nil then
		local minutes, reason = source_command:match("^/offmute%s+%S+%s+(%d+)%s+(.+)$")

		if minutes and reason then
			return string.format("/mute %d %s %s", suggested_target_id, minutes, reason), "/mute", suggested_target_id, target_name
		end
	elseif source_kind == "/sban" and suggested_kind == "/sban" and suggested_target_id ~= nil then
		local days, reason = source_command:match("^/sban%s+%S+%s+(%d+)%s+(.+)$")

		if days and reason then
			return string.format("/sban %d %s %s", suggested_target_id, days, reason), "/sban", suggested_target_id, target_name
		end

		reason = source_command:match("^/sban%s+%S+%s+(.+)$")

		if reason then
			return string.format("/sban %d %s", suggested_target_id, reason), "/sban", suggested_target_id, target_name
		end
	elseif source_kind == "/unmute" and suggested_kind == "/unmute" and suggested_target_id ~= nil then
		return string.format("/unmute %d", suggested_target_id), "/unmute", suggested_target_id, target_name
	elseif source_kind == "/unjail" and suggested_kind == "/unjail" and suggested_target_id ~= nil then
		return string.format("/unjail %d", suggested_target_id), "/unjail", suggested_target_id, target_name
	elseif source_kind == "/warn" and suggested_kind == "/offwarn" and target_name ~= "" then
		local reason = source_command:match("^/warn%s+%d+%s+(.+)$")

		if reason then
			return string.format("/offwarn %s %s", target_name, reason), "/offwarn", nil, target_name
		end
	elseif source_kind == "/ban" and suggested_kind == "/offban" and target_name ~= "" then
		local days, reason = source_command:match("^/ban%s+%d+%s+(%d+)%s+(.+)$")

		if days and reason then
			return string.format("/offban %s %s %s", target_name, days, reason), "/offban", nil, target_name
		end
	elseif source_kind == "/jail" and suggested_kind == "/offjail" and target_name ~= "" then
		local minutes, reason = source_command:match("^/jail%s+%d+%s+(%d+)%s+(.+)$")

		if minutes and reason then
			return string.format("/offjail %s %s %s", target_name, minutes, reason), "/offjail", nil, target_name
		end
	elseif source_kind == "/mute" and suggested_kind == "/offmute" and target_name ~= "" then
		local minutes, reason = source_command:match("^/mute%s+%d+%s+(%d+)%s+(.+)$")

		if minutes and reason then
			return string.format("/offmute %s %s %s", target_name, minutes, reason), "/offmute", nil, target_name
		end
	elseif source_kind == "/sban" and suggested_kind == "/sban" and target_name ~= "" then
		local days, reason = source_command:match("^/sban%s+%d+%s+(%d+)%s+(.+)$")

		if days and reason then
			return string.format("/sban %s %s %s", target_name, days, reason), "/sban", nil, target_name
		end

		reason = source_command:match("^/sban%s+%d+%s+(.+)$")

		if reason then
			return string.format("/sban %s %s", target_name, reason), "/sban", nil, target_name
		end
	end

	return nil, nil, nil, target_name
end

local function build_switched_request_from_context(context, command_text, kind, target_id, target_name)
	local target_label

	if target_id ~= nil then
		target_label, target_name = get_notice_target_label(target_id)
		target_name = target_name or get_switch_target_name(context and context.target_name or "", context and context.target_label or "")
	else
		target_name = get_switch_target_name(target_name, context and context.target_label or "")
		target_label = target_name
	end

	return {
		admin_name = tostring(context and context.admin_name or ""),
		admin_id = 0,
		command_text = command_text,
		target_label = target_label,
		target_id = target_id,
		target_name = target_name,
		kind = kind,
		created_at = os.clock(),
		signature_mode_used = nil
	}
end

local function find_online_player_by_nickname(target_name)
	target_name = lower(target_name)

	if target_name == "" or target_name:match("^%d+$") then
		return nil, nil
	end

	local local_id, local_name = get_local_identity()

	if local_id ~= nil and lower(local_name or "") == target_name then
		return local_id, local_name
	end

	for player_id = 0, 1003 do
		if (local_id == nil or player_id ~= tonumber(local_id)) and sampIsPlayerConnected(player_id) then
			local current_name = sampGetPlayerNickname(player_id)

			if current_name and current_name ~= "" and lower(current_name) == target_name then
				return player_id, current_name
			end
		end
	end

	return nil, nil
end

local function get_direct_online_switch_kind(kind)
	if kind == "/offwarn" then
		return "/warn"
	elseif kind == "/unwarn" then
		return "/unwarn"
	elseif kind == "/offban" then
		return "/ban"
	elseif kind == "/offjail" then
		return "/jail"
	elseif kind == "/unmute" then
		return "/unmute"
	elseif kind == "/unjail" then
		return "/unjail"
	elseif kind == "/offmute" then
		return "/mute"
	elseif kind == "/sban" then
		return "/sban"
	end

	return nil
end

local function build_local_online_switch_result(request, command_text)
    if request and request.force_offline then return nil end
	if SETTINGS.auto_switch_online_offline ~= true or request == nil then
		return nil
	end

	local suggested_kind = get_direct_online_switch_kind(request.kind)

	if suggested_kind == nil then
		return nil
	end

	if request.kind == "/sban" and request.target_id ~= nil then
		return nil
	end

	local context = build_online_offline_switch_context(request, command_text or request.command_text, nil)

	if context == nil then
		return nil
	end

	local target_name = get_switch_target_name(request.target_name, request.target_label)
	local online_id, online_name = find_online_player_by_nickname(target_name)

	if online_id == nil then
		return nil
	end

	local switched_command, switched_kind, switched_target_id, switched_target_name = build_switched_command_from_context(context, suggested_kind, online_id)

	if switched_command == nil then
		return nil
	end

	switched_target_name = switched_target_name or online_name or target_name

	local switched_request = build_switched_request_from_context(context, switched_command, switched_kind, switched_target_id, switched_target_name)
	switched_request.signature_mode_used = request.signature_mode_used

	return {
		context = context,
		command_text = switched_command,
		request = switched_request
	}
end

local function queue_switched_command_from_context(context, switched_command, switched_kind, switched_target_id, switched_target_name)
	local switched_request = build_switched_request_from_context(context, switched_command, switched_kind, switched_target_id, switched_target_name)

	state.awaiting_online_offline_switch_context = nil
	state.awaiting_database_lookup_context = nil

	queue_pre_punish_bundle(switched_request, switched_command, "online-offline-switch")
	message(string.format("Команда изменена по статусу игрока: %s → %s", trim(tostring(context.command_text or "")), switched_command), true)
	append_log(string.format("Автопереключение команды: %s -> %s", trim(tostring(context.command_text or "")), switched_command))
	debug_message(string.format("Автопереключение команды: %s -> %s", trim(tostring(context.command_text or "")), switched_command), true)
end

local function handle_online_offline_switch_hint(text)
	local context = state.awaiting_online_offline_switch_context

	if SETTINGS.auto_switch_online_offline ~= true or context == nil then
		return false
	end

	local suggested_kind, suggested_target_id = extract_online_switch_hint(text)

	if suggested_kind ~= nil then
		local switched_command, switched_kind, switched_target_id, switched_target_name = build_switched_command_from_context(context, suggested_kind, suggested_target_id)

		if switched_command ~= nil then
			queue_switched_command_from_context(context, switched_command, switched_kind, switched_target_id, switched_target_name)
		else
			debug_message("Автопереключение не выполнено: не удалось собрать online-команду по подсказке сервера.", true)
			state.awaiting_online_offline_switch_context = nil
		end

		return true
	end

	local offline_kind = extract_offline_switch_hint(text)

	if offline_kind ~= nil then
		local switched_command, switched_kind, switched_target_id, switched_target_name = build_switched_command_from_context(context, offline_kind, nil)

		if switched_command ~= nil then
			queue_switched_command_from_context(context, switched_command, switched_kind, switched_target_id, switched_target_name)
		else
			debug_message("Автопереключение не выполнено: не удалось собрать offline-команду по подсказке сервера.", true)
			state.awaiting_online_offline_switch_context = nil
		end

		return true
	end

	return false
end

function parse_existing_term_minutes(text, action_kind)
	text = trim(tostring(text or ""))
	text = trim(text:gsub("{%x%x%x%x%x%x}", ""))

	if text == "" then
		return nil
	end

	local minutes, seconds = text:match("осталось%s+(%d+):(%d+)")

	if minutes == nil then
		minutes, seconds = text:match("Оставшееся время:%s*(%d+):(%d+)")
	end

	if minutes == nil then
		return nil
	end

	minutes = tonumber(minutes) or 0
	seconds = tonumber(seconds) or 0

	if seconds > 0 then
		minutes = minutes + 1
	end

	return minutes
end

function build_stacked_term_command(context, total_minutes)
	local reason = trim(tostring(context.reason or ""))

	if reason == "" then
		return nil
	end

	if not lower(reason):find("+ старый срок", 1, true) then
		reason = reason .. " + старый срок"
	end

	return string.format("%s %s %d %s", context.command_name, context.target_token, total_minutes, reason)
end

function handle_existing_term_stack(text)
	local context = state.awaiting_stack_term_context

	if context == nil then return false end
    if (context.action_kind == 'jail' and not SETTINGS.stack_jail_enabled)
        or (context.action_kind == 'mute' and not SETTINGS.stack_mute_enabled) then
        state.awaiting_stack_term_context=nil;return false
    end
	local old_minutes = parse_existing_term_minutes(text, context.action_kind)

	if old_minutes == nil then
		return false
	end

	local total_minutes = math.min(300, old_minutes + (tonumber(context.new_minutes) or 0))
	local stacked_command = build_stacked_term_command(context, total_minutes)

	if stacked_command == nil then
		state.awaiting_stack_term_context = nil
		return false
	end

	local clear_command

	if context.action_kind == "mute" then
		clear_command = "/unmute " .. tostring(context.target_token)
	else
		clear_command = "/unjail " .. tostring(context.target_token)
	end

	state.awaiting_stack_term_context = nil
	enqueue_outgoing_command(clear_command, "stack-old-term-clear", nil, context.batch_id, false)
	if context.target_id ~= nil and SETTINGS.stack_notice_enabled then
        local notice=trim(rules.render(SETTINGS.stack_notice_template,{
            old=old_minutes,added=context.new_minutes,total=total_minutes,nick=context.target_name,id=context.target_id}))
        if notice~='' then enqueue_outgoing_command('/ans '..context.target_id..' '..notice, 'stack-old-term-notice', nil, context.batch_id, false) end
    end
	local reissue_delay = context.command_name == "/jail" and STACK_TERM_REISSUE_DELAY or 0
	enqueue_outgoing_command(stacked_command, "stack-old-term-issue", nil, context.batch_id, true, nil, nil, reissue_delay)
	message(string.format("Сроки объединены: %d + %d = %d мин.", old_minutes, tonumber(context.new_minutes) or 0, total_minutes), true)
	append_log(string.format("Объединение срока: %s -> %s", clear_command, stacked_command))
	debug_message(string.format("Объединение срока: %s -> %s", clear_command, stacked_command), true)
	return true
end

local function clear_pending(reason)
	if state.pending_request and reason then
		append_log(reason)
	end

	state.pending_request = nil
end

local function cancel_pending(chat_text, log_text)
	local request = state.pending_request

	if chat_text then
		message(chat_text, true)
	end

	append_request_log("CANCELLED", request, log_text or chat_text or "отменено", nil)
	clear_pending(log_text or chat_text)
end

local function sanitize_status_actor_name(name)
	name = trim(tostring(name or ""))

	if name == "" then
		return ""
	end

	return trim(name:gsub("%[%d+%]$", ""))
end

local function get_request_target_display_name(request)
	if request == nil then
		return "игрок"
	end

	local target_name = trim(request.target_name or "")

	if target_name ~= "" then
		return target_name
	end

	local target_label = trim(request.target_label or "")

	if target_label ~= "" then
		return target_label
	end

	return "игрок"
end

local function enqueue_admin_chat_status(text, source)
	text = trim(text)

	if text == "" then
		return
	end

	enqueue_outgoing_command("/a " .. text, source or "admin-status")
end

local function finalize_pending_target_left(request, reason)
	if request == nil then
		return false
	end

	local target_name = get_request_target_display_name(request)

	debug_message("Ожидающая команда снята: цель вышла из игры: " .. target_name, true)
	message(string.format("Запрос отменён: игрок %s вышел из игры.", target_name), true)
	append_request_log("TARGET_LEFT", request, "игрок вышел из игры", nil)
	clear_pending(reason or string.format("Ожидающая команда снята: игрок %s вышел из игры.", target_name))
	return true
end

local function finalize_pending_punished(request, issuer_name, reason)
	if request == nil then
		return false
	end

	local target_name = get_request_target_display_name(request)
	local requester_name = sanitize_status_actor_name(request.admin_name)
	local punisher_name = sanitize_status_actor_name(issuer_name)

	if punisher_name == "" then
		punisher_name = "другой администратор"
	end

	local admin_text = string.format("%s, игроку %s выдал наказание %s.", requester_name ~= "" and requester_name or "Администратор", target_name, punisher_name)

	debug_message(string.format("Ожидающая команда снята: игрок %s уже наказан администратором %s.", target_name, punisher_name), true)
	if SETTINGS.track_other_admin_punishments == true then
		enqueue_admin_chat_status(admin_text, "pending-already-punished")
	end
	message(string.format("Запрос отменён: %s уже наказан администратором %s.", target_name, punisher_name), true)
	append_request_log("OTHER_ADMIN", request, "наказание выдал " .. punisher_name, nil)
	clear_pending(reason or string.format("Ожидающая команда снята: игроку %s уже выдал наказание %s.", target_name, punisher_name))
	return true
end

local function finalize_queued_punished(context, issuer_name)
	if context == nil then
		return false
	end

	local target_name = trim(tostring(context.target_name or context.target_label or "игрок"))
	local requester_name = sanitize_status_actor_name(context.admin_name)
	local punisher_name = sanitize_status_actor_name(issuer_name)

	if punisher_name == "" then
		punisher_name = "другой администратор"
	end

	local removed = remove_outgoing_batch_items(context.batch_id)
	state.awaiting_punishment_guard_context = nil

	if state.awaiting_database_lookup_context ~= nil and state.awaiting_database_lookup_context.batch_id == context.batch_id then
		state.awaiting_database_lookup_context = nil
	end

	if SETTINGS.track_other_admin_punishments == true and requester_name ~= "" then
		enqueue_admin_chat_status(string.format("%s, игроку %s выдал наказание %s.", requester_name, target_name, punisher_name), "queued-already-punished")
	end

	message(string.format("Выдача остановлена: %s уже наказан администратором %s.", target_name, punisher_name), true)
	append_log(string.format("Очередь выдачи остановлена: игроку %s уже выдал наказание %s. Удалено команд из очереди: %d", target_name, punisher_name, removed))
	append_request_log("QUEUE_STOPPED", context, "наказание выдал " .. punisher_name .. ", удалено из очереди: " .. tostring(removed), nil)
	debug_message(string.format("Очередь выдачи остановлена: игроку %s уже выдал наказание %s. Удалено команд из очереди: %d", target_name, punisher_name, removed), true)
	return true
end

clear_afk_sensitive_contexts = function()
	local had_any = #state.request_queue>0
    state.request_queue={}

	if #state.outgoing_queue > 0 then
		append_log(string.format("AFK защита: очищена очередь отправки (%d).", #state.outgoing_queue))
		state.outgoing_queue = {}
		had_any = true
	end

	if state.pending_request ~= nil then
		append_log("Ожидающая команда снята: AFK защита.")
		append_request_log("AFK_CLEARED", state.pending_request, "очищено из-за ESC/AFK", nil)
		state.pending_request = nil
		had_any = true
	end

	if state.awaiting_punishment_guard_context ~= nil then
		append_log("AFK защита: снят контроль конфликта выдачи.")
		state.awaiting_punishment_guard_context = nil
		had_any = true
	end

	if state.awaiting_database_lookup_context ~= nil then
		append_log("AFK защита: снят контроль оффлайн-ответа.")
		state.awaiting_database_lookup_context = nil
		had_any = true
	end

	if state.awaiting_stack_term_context ~= nil then
		append_log("AFK protection: stack-term context cleared.")
		state.awaiting_stack_term_context = nil
		had_any = true
	end

	if state.awaiting_online_offline_switch_context ~= nil then
		append_log("AFK защита: снят контроль автопереключения online/offline.")
		state.awaiting_online_offline_switch_context = nil
		had_any = true
	end

	if had_any then
		state.afk_suppress_until = os.clock() + AFK_EXIT_SUPPRESS_SECONDS
		debug_message("Защита во время AFK отменила незавершённые автоматические действия.", false)
	end
end

local function parse_punishment_info_for_request(text, request)
	if request == nil or not is_punish_command(request.kind) then
		return nil
	end

	text = trim(tostring(text or ""))

	if text == "" then
		return nil
	end

	local target_name = lower(get_request_target_display_name(request))
	local patterns = {
		"^%[A%]%s+(%S+)%[%d+%]%s+посадил%s+в%s+тюрьму%s+([A-Za-z0-9_]+)",
		"^%[A%]%s+(%S+)%[%d+%]%s+посадил%s+в%s+тюрьму%s+игрока%s+([A-Za-z0-9_]+)",
		"^%[A%]%s+(%S+)%[%d+%]%s+поставил%s+затычку%s+игроку%s+([A-Za-z0-9_]+)",
		"^%[A%]%s+(%S+)%[%d+%]%s+выдал%s+затычку%s+игроку%s+([A-Za-z0-9_]+)",
		"^%[A%]%s+(%S+)%[%d+%]%s+кикнул%s+игрока%s+([A-Za-z0-9_]+)",
		"^%[A%]%s+(%S+)%[%d+%]%s+забанил%s+игрока%s+([A-Za-z0-9_]+)",
		"^%[A%]%s+(%S+)%[%d+%]%s+выдал%s+предупреждение%s+игроку%s+([A-Za-z0-9_]+)",
		"^Администратор%s+(%S+)%s+посадил%s+в%s+тюрьму%s+игрока%s+([A-Za-z0-9_]+)",
		"^Администратор%s+(%S+)%s+посадил%s+игрока%s+([A-Za-z0-9_]+)",
		"^Администратор%s+(%S+)%s+посадил%s+в%s+КПЗ%s+игрока%s+([A-Za-z0-9_]+)",
		"^Администратор%s+(%S+)%s+поставил%s+затычку%s+игроку%s+([A-Za-z0-9_]+)",
		"^Администратор%s+(%S+)%s+выдал%s+затычку%s+игроку%s+([A-Za-z0-9_]+)",
		"^Администратор%s+(%S+)%s+кикнул%s+игрока%s+([A-Za-z0-9_]+)",
		"^Администратор%s+(%S+)%s+забанил%s+оффлайн%s+игрока%s+([A-Za-z0-9_]+)",
		"^Администратор%s+(%S+)%s+забанил%s+игрока%s+([A-Za-z0-9_]+)",
		"^Администратор%s+(%S+)%s+выдал%s+предупреждение%s+игроку%s+([A-Za-z0-9_]+)"
	}

	for _, pattern in ipairs(patterns) do
		local admin_name, punished_name = text:match(pattern)

		if admin_name and punished_name and lower(punished_name) == target_name then
			return sanitize_status_actor_name(admin_name), punished_name
		end
	end

	local local_id, local_name = get_local_identity()

	if request.target_id ~= nil and local_id ~= nil and tonumber(request.target_id) == tonumber(local_id) then
		local self_patterns = {
			"^Администратор%s+(%S+)%s+посадил%s+Вас",
			"^Администратор%s+(%S+)%s+поставил%s+Вам%s+затычку",
			"^Администратор%s+(%S+)%s+кикнул%s+Вас",
			"^Администратор%s+(%S+)%s+забанил%s+Вас",
			"^Администратор%s+(%S+)%s+выдал%s+Вам%s+предупреждение"
		}

		for _, pattern in ipairs(self_patterns) do
			local admin_name = text:match(pattern)

			if admin_name then
				return sanitize_status_actor_name(admin_name), local_name or request.target_name
			end
		end
	end

	return nil
end

local function should_block_admin_target(request)
	return SETTINGS.block_known_admin_targets
		and request.target_name ~= nil
		and request.target_name ~= ""
		and is_punish_command(request.kind)
		and is_known_admin(request.target_name)
end

local function validate_pending_request(request)
	if request == nil then
		return false
	end

	if should_block_admin_target(request) then
		cancel_pending("Команда отклонена: игрок находится в защищённом списке администраторов или лидеров.", "Команда отклонена: игрок находится в защищённом списке администраторов или лидеров.")
		return false
	end

	if request.target_id ~= nil then
		if not sampIsPlayerConnected(request.target_id) then
			if is_online_punish_command(request.kind) then
				finalize_pending_target_left(request, "Запрос отменён: игрок вышел с сервера.")
			else
				cancel_pending("Запрос отменён: игрок вышел с сервера.", "Запрос отменён: игрок вышел с сервера.")
			end
			return false
		end

		local current_name = sampGetPlayerNickname(request.target_id)

		if lower(current_name) ~= lower(request.target_name) then
			if is_online_punish_command(request.kind) then
				finalize_pending_target_left(request, "Запрос отменён: ID теперь принадлежит другому игроку.")
			else
				cancel_pending("Запрос отменён: ID теперь принадлежит другому игроку.", "Запрос отменён: ID теперь принадлежит другому игроку.")
			end
			return false
		end
	end

	return true
end

local function is_activity_color(color)
	return ACTIVITY_COLORS[color] == true or color == SETTINGS.admin_chat_color
end

local function should_cancel_on_server_activity(color, text)
	local request = state.pending_request

	if request == nil or not SETTINGS.auto_cancel_on_activity or not is_activity_color(color) then
		return false
	end

	local target_name = lower(request.target_name)

	if target_name == "" then
		return false
	end

	local lower_text = lower(text)
    if text:find("[A]",1,true) then return false end

	if lower_text:find(target_name, 1, true) == nil then
		return false
	end

	local _, local_name = get_local_identity()

	if local_name and lower_text:find(lower(local_name), 1, true) ~= nil then
		return false
	end

	return true
end

local function capture_request(request)
    if is_user_afk_protected() or is_afk_exit_suppressed() then return end
    request.received_at=request.received_at or os.clock()
	if not integration.access:can(3) then return end
	if should_block_admin_target(request) then
		debug_message(string.format("Блок команды: цель %s есть в списке администраторов.", request.target_name or "-"), true)
		message("Команда отклонена: игрок находится в защищённом списке администраторов или лидеров.", true)
		append_log(string.format("Команда от %s[%d] отклонена: цель %s есть в списке администраторов.", request.admin_name, request.admin_id, request.target_name or "-"))
		append_request_log("REJECTED", request, "цель есть в списке администраторов/лидеров", nil)
		return
	end

	if command_supports_signature(request) then
		request.signature_mode_used = resolve_signature_mode(SETTINGS.signature_mode)
	end

    request.created_at=os.clock()
	state.pending_request = request
	play_request_notification_sound()
	debug_message(string.format("Команда захвачена: %s[%d] -> %s", request.admin_name, request.admin_id, request.command_text), true)
	message(string.format("%s[%d] запросил: %s", request.admin_name, request.admin_id, request.command_text), "request")
	message("Игрок: " .. request.target_label, "request")

	local issued_command = build_issued_command(request)
	local local_switch = build_local_online_switch_result(request, issued_command)

	if local_switch ~= nil then
		issued_command = local_switch.command_text
	end


	if SETTINGS.show_final_command_message then
		message("Итоговая команда: " .. issued_command, "final")
	end
	-- An actionable request must remain understandable with optional status
	-- messages / HUD disabled. Resolve saved bindings when the FIFO item activates.
	message(string.format("%s — отправить | %s — отклонить | %d с.",
		integration.keys:name('punish_confirm'), integration.keys:name('punish_cancel'), SETTINGS.request_timeout), "request")

	if SETTINGS.log_captured_requests then
		append_log(string.format("Поймана команда из админ-чата от %s[%d]: %s", request.admin_name, request.admin_id, request.command_text))
	end

	append_request_log("CAPTURED", request, "ожидает подтверждения", issued_command)
end

function advance_aegis_request_queue()
    if is_user_afk_protected() or is_afk_exit_suppressed() then return end
    if state.pending_request or not SETTINGS.enabled or not integration.access:can(3) then return end
    -- Do not overlap response contexts from two punishments.
    if #state.outgoing_queue>0 or state.awaiting_database_lookup_context or state.awaiting_online_offline_switch_context
        or state.awaiting_stack_term_context or state.awaiting_punishment_guard_context then return end
    while #state.request_queue>0 do
        local request=table.remove(state.request_queue,1)
        if os.clock()-(request.received_at or 0)>SETTINGS.queue_max_age then
            append_request_log('EXPIRED',request,'истёк срок в очереди')
        elseif request.invalidated then
            append_request_log('CANCELLED',request,request.invalidated)
        elseif request.target_id and (not sampIsPlayerConnected(request.target_id) or lower(sampGetPlayerNickname(request.target_id))~=lower(request.target_name)) then
            append_request_log('TARGET_CHANGED',request,'игрок вышел или ID сменил владельца')
        else
            capture_request(request)
            if state.pending_request then return end
        end
    end
end

local function handle_confirm()
	if not integration.access:require(3, function(reason) message(reason, true) end) then
		clear_afk_sensitive_contexts()
		return
	end
	local request = state.pending_request

	if not validate_pending_request(request) then
		debug_message("Подтверждение отменено: проверка ожидающей команды не пройдена.", true)
		return
	end

	local issued_command = build_issued_command(request)

	debug_message("Команда поставлена в очередь на отправку: " .. issued_command, true)
	local local_switch = build_local_online_switch_result(request, issued_command)

	if local_switch ~= nil then
		message(string.format("Команда изменена по статусу игрока: %s → %s", issued_command, local_switch.command_text), true)
		append_log(string.format("Локальное автопереключение команды: %s -> %s", issued_command, local_switch.command_text))
		debug_message(string.format("Локальное автопереключение команды: %s -> %s", issued_command, local_switch.command_text), true)
		request = local_switch.request
		issued_command = local_switch.command_text
	end

    local chain=state.command_chains[request.kind]
    if chain then
        local values={id=request.target_id,nick=request.target_name,admin=request.admin_name,command=issued_command}
        local args=split_command_args(request.command_text)
        for i,arg in ipairs(args)do values['arg'..i]=arg end
        local steps={}
        for _,step in ipairs(chain)do
            if step.command:find('{id}',1,true) and not request.target_id then
                message('Цепочка требует игрока онлайн.',true);return
            end
            local command=trim(rules.render(step.command,values))
            local prepared,why=integration.prepareChatCommand(command)
            if not prepared or not integration.commandAllowed(command) then
                message('Цепочка не запущена: '..tostring(why or 'недостаточно прав')..' — '..command,true);return
            end
            if SETTINGS.block_known_admin_targets and request.target_name and is_known_admin(request.target_name)
                and is_punish_command(get_command_name_from_text(command)) then
                message('Цепочка остановлена: цель в защищённом списке.',true);return
            end
            steps[#steps+1]={command=command,delay=step.delay}
        end
        state.next_outgoing_batch_id=state.next_outgoing_batch_id+1
        local batch=state.next_outgoing_batch_id
        for i,step in ipairs(steps)do
            local source=step.command:match('^/tr%s') and 'script-tr-command' or 'custom-chain'
            enqueue_outgoing_command(step.command,source,nil,batch,false,nil,nil,i==1 and step.delay or 0)
            local item=state.outgoing_queue[#state.outgoing_queue]
            if item and item.batch_id==batch then
                item.chain=true;item.chain_delay=step.delay;item.chain_request=request
            end
        end
        if request.report_status_text and trim(request.report_status_text)~='' then
            enqueue_outgoing_command('/a '..request.report_status_text,'custom-chain-report',nil,batch,false)
            local item=state.outgoing_queue[#state.outgoing_queue]
            if item and item.batch_id==batch then item.chain=true;item.chain_delay=0;item.chain_request=request end
        end
        append_request_log('ISSUED',request,'цепочка поставлена в очередь',issued_command)
        message('Цепочка поставлена в очередь: '..request.kind,true)
        clear_pending();return
    elseif request.script_tr_command then
        enqueue_outgoing_command(issued_command,'script-tr-command',nil,nil,false)
        clear_pending();return
    end

	if request.report_status_text ~= nil and trim(request.report_status_text) ~= "" then
		enqueue_outgoing_command(issued_command, "report-command", nil, nil, true)
		enqueue_admin_chat_status(request.report_status_text, "report-command-status")
		message(string.format("Поставлено в очередь с отчётом: %s", issued_command), true)
		append_log(string.format("Команда с отчётом от %s[%d] поставлена в очередь: %s", request.admin_name, request.admin_id, issued_command))
		append_request_log("ISSUED", request, "команда с отчётом поставлена в очередь", issued_command)
		clear_pending()
		return
	end

	queue_pre_punish_bundle(request, issued_command, "auto-confirm")
	message(string.format("Поставлено в очередь: %s", issued_command), true)
	append_log(string.format("Команда из админ-чата от %s[%d] поставлена в очередь: %s", request.admin_name, request.admin_id, issued_command))
	append_request_log("ISSUED", request, "команда поставлена в очередь", issued_command)
	clear_pending()
end

local function handle_cancel()
	if state.pending_request == nil then
		return
	end

	debug_message("Ожидающая команда отменена вручную.", true)
	cancel_pending("Запрос отменён.", "Ожидающая команда отменена пользователем.")
end

local function refresh_protected_list()
	if integration.protectedLists then integration.protectedLists(true) end
	load_known_admins()
	state.status_line='Сохранённые списки перечитаны. Получение списков с сервера — в чекере.'
end

local function process_pending()
	poll_user_activity()


	if is_user_afk_protected() then
		if not state.afk_guard_active then
			state.afk_guard_active = true
			clear_afk_sensitive_contexts()
		end
		return
	end

    if is_afk_exit_suppressed() then return end
	process_outgoing_queue()

	if state.awaiting_database_lookup_context ~= nil and os.clock() - (state.awaiting_database_lookup_context.created_at or 0) > 8 then
		state.awaiting_database_lookup_context = nil
	end

	if state.awaiting_punishment_guard_context ~= nil and os.clock() - (state.awaiting_punishment_guard_context.created_at or 0) > 12 then
		state.awaiting_punishment_guard_context = nil
	end

	if state.awaiting_online_offline_switch_context ~= nil and os.clock() - (state.awaiting_online_offline_switch_context.created_at or 0) > 8 then
		state.awaiting_online_offline_switch_context = nil
	end

	if state.awaiting_stack_term_context ~= nil and os.clock() - (state.awaiting_stack_term_context.created_at or 0) > STACK_TERM_RESPONSE_TIMEOUT then
		state.awaiting_stack_term_context = nil
	end

	advance_aegis_request_queue()
	local request = state.pending_request

	if request == nil then
		return
	end

	if os.clock() - request.created_at > SETTINGS.request_timeout then
		cancel_pending("Запрос отменён: время на подтверждение истекло.", "Запрос отменён: время на подтверждение истекло.")
		return
	end

	if request.target_id ~= nil and not validate_pending_request(request) then
		return
	end

	if sampIsChatInputActive() or (draft_keys and draft_keys:captureActive()) then
		return
	end

	if integration.keys:pressed('punish_confirm') then
		handle_confirm()
	elseif integration.keys:pressed('punish_cancel') then
		handle_cancel()
	end
end

function save_aegis_draft()
    if chain_editor then
        local text,err=chain_editor:serialize()
        if not text then state.settings_error=err;return false end
        set_imgui_buffer(ui.command_chains,text)
    end
    local chains,err=rules.chains(get_imgui_buffer_text(ui.command_chains))
    if not chains then state.settings_error=err;return false end
    for _,key in ipairs({'custom_signature','stack_notice_template'})do
        if get_imgui_buffer_text(ui[key]):find('[%z\1-\31]') then state.settings_error='Шаблон должен занимать одну строку.';return false end
    end
    local keys=integration.keys
    local nextData={};for id,data in pairs(keys.data)do nextData[id]=data end
    for _,id in ipairs({'punish_confirm','punish_cancel'})do
        local data=draft_keys.data[id]
        if data and draft_keys.dirty[id] then nextData[id]=data end
    end
    local keyCheck=rules.keyDraft(keys);keyCheck.data=nextData
    for _,id in ipairs({'punish_confirm','punish_cancel'})do
        if draft_keys.dirty[id] and keys:format(nextData[id])~=keys:format(keys.data[id])
            and #keyCheck:conflicts(id,nextData[id])>0 then
            state.settings_error='Назначение клавиши пересекается с другим действием. Выберите свободное сочетание.'
            return false
        end
    end
    local previous={};for k,v in pairs(SETTINGS)do previous[k]=v end
    apply_ui_to_settings()
    for _,entry in ipairs({{'punish_confirm','confirm_key'},{'punish_cancel','cancel_key'}})do
        SETTINGS[entry[2]]=nextData[entry[1]].key
    end
    local ok,err=save_settings_file()
    if not ok then
        for k,v in pairs(previous)do SETTINGS[k]=v end;sanitize_settings()
        state.settings_error='Не удалось сохранить настройки: '..tostring(err);return false
    end
    local keysOK,keyError=keys.storage:saveIni(nextData,keys.path)
    if not keysOK then
        for k,v in pairs(previous)do SETTINGS[k]=v end;sanitize_settings();save_settings_file()
        state.settings_error='Не удалось сохранить клавиши: '..tostring(keyError);return false
    end
    keys.data=nextData
    for _,id in ipairs({'punish_confirm','punish_cancel'})do local item=keys.items[id];if item and item.changed then item.changed(nextData[id])end end
    sync_ui_from_settings()
    if not SETTINGS.enabled then clear_afk_sensitive_contexts() end
    state.settings_error=nil
    message('Настройки сохранены.', 'settings')
    return true
end

function setup_aegis_ui()
    local color_text = imgui.new.char[9]()
    local displayed_color
    local editor_page, editor_group = 1, nil
    local function section(title)
        imgui.Spacing()
        imgui.TextColored(integration.color(integration.palette.accent), title)
        imgui.Separator()
    end

    local function meta(label, value)
        imgui.TextDisabled(label)
        imgui.SameLine()
        imgui.TextWrapped(tostring(value))
    end

    local function toggle(label, value, id)
        imgui.Checkbox(label .. '##' .. id, value)
    end

    local function draw_command_editor()
        local group = get_group_config(command_editor.group_key)
        if not group then close_command_editor(); return end
        if editor_group ~= command_editor.group_key then
            editor_group, editor_page = command_editor.group_key, 1
        end
        section(group.title)
        if command_editor.group_key == 'report' then
            imgui.TextWrapped('Формат: /команда | шаблон отчёта. Переменные: {admin}, {target}, {arg1}, {arg2}, {text}, {command}')
        else
            imgui.TextDisabled('Одна команда в каждой строке.')
        end
        imgui.TextDisabled('Выключенные строки сохраняются. Изменения применяются кнопкой «Сохранить».')
        imgui.Spacing()
        local page_size = 8
        local pages = math.max(1, math.ceil(#command_editor.rows / page_size))
        editor_page = math.max(1, math.min(editor_page, pages))
        if pages > 1 then
            if imgui.Button('<##command_editor_prev', imgui.ImVec2(36, 34)) then editor_page = math.max(1, editor_page - 1) end
            imgui.SameLine()
            imgui.Text('Страница ' .. editor_page .. ' / ' .. pages)
            imgui.SameLine()
            if imgui.Button('>##command_editor_next', imgui.ImVec2(36, 34)) then editor_page = math.min(pages, editor_page + 1) end
            imgui.Spacing()
        end
        for index = (editor_page - 1) * page_size + 1, math.min(editor_page * page_size, #command_editor.rows) do
            local buffer = command_editor.rows[index]
            imgui.PushItemWidth(-210)
            imgui.InputText('##command_row_' .. index, buffer, ffi.sizeof(buffer))
            imgui.PopItemWidth()
            imgui.SameLine()
            if imgui.Button('+##row_add_' .. index, imgui.ImVec2(34, 34)) then
                table.insert(command_editor.rows, index + 1, create_editor_row_buffer(''))
                editor_page = math.ceil((index + 1) / page_size)
                break
            end
            imgui.SameLine()
            if imgui.Button('x##row_remove_' .. index, imgui.ImVec2(34, 34)) then
                remove_command_editor_row(index)
                break
            end
            imgui.SameLine()
            local disabled=command_editor.disabled[buffer]
            if imgui.Button((disabled and 'Включить' or 'Выключить') .. '##row_toggle_' .. index, imgui.ImVec2(114,34)) then
                command_editor.disabled[buffer]=not disabled
                integration.notifyToggle('Команда: '..get_imgui_buffer_text(buffer),disabled==true)
            end
        end
        imgui.Spacing()
        if imgui.Button('Добавить строку', imgui.ImVec2(166, 34)) then
            add_command_editor_row('')
            editor_page = math.ceil(#command_editor.rows / page_size)
        end
        imgui.SameLine()
        if imgui.Button('Готово', imgui.ImVec2(120, 30)) then save_command_editor() end
        imgui.SameLine()
        if imgui.Button('Отменить', imgui.ImVec2(100, 30)) then close_command_editor() end
    end

    local function draw_toggles(width)
        local columns = width >= 760
        if columns then
            imgui.Columns(2, 'punishment_settings_columns', false)
            imgui.SetColumnWidth(0, width * 0.51)
        end
        section('Обработка запросов')
        toggle('Обрабатывать запросы из /a', ui.enabled, 'enabled')
        toggle('Защищать администраторов и лидеров', ui.block_known_admin_targets, 'block_admin_targets')
        toggle('Отменять по активности игрока', ui.auto_cancel_on_activity, 'activity_cancel')
        toggle('Выбирать команду по статусу игрока', ui.auto_switch_online_offline, 'switch_online')
        toggle('Уведомлять о форуме через /ans', ui.pre_punish_notice_enabled, 'ans_notice')
        toggle('Складывать сроки jail / offjail', ui.stack_jail_enabled, 'stack_jail')
        toggle('Складывать сроки mute / offmute', ui.stack_mute_enabled, 'stack_mute')
        imgui.TextWrapped('Защита распространяется и на ручные ban / warn. По умолчанию включена.')
        imgui.Spacing()
        imgui.TextDisabled('Время на подтверждение, сек.')
        imgui.PushItemWidth(100)
        imgui.InputInt('##request_timeout_checker', ui.request_timeout, 0, 0)
        imgui.PopItemWidth()
        imgui.Spacing()
        imgui.TextDisabled('Цвет сообщений /a')
        if displayed_color ~= ui.admin_chat_color[0] then
            displayed_color = ui.admin_chat_color[0]
            ffi.fill(color_text, 9, 0)
            ffi.copy(color_text, string.format('%08X', displayed_color % 4294967296), 8)
        end
        imgui.PushItemWidth(150)
        if imgui.InputText('##admin_chat_color_checker', color_text, 9) then
            local text = ffi.string(color_text)
            if text:match('^%x%x%x%x%x%x%x%x$') then
                local value = tonumber(text, 16)
                if value >= 2147483648 then value = value - 4294967296 end
                ui.admin_chat_color[0], displayed_color = value, value
            end
        end
        imgui.PopItemWidth()
        if not ffi.string(color_text):match('^%x%x%x%x%x%x%x%x$') then
            imgui.TextDisabled('Код цвета: 8 символов (0–9, A–F). До ввода полного кода цвет не меняется.')
        end
        section('Очередь запросов')
        imgui.InputInt('Мест в очереди##queue_limit',ui.queue_limit,0,0)
        imgui.InputInt('Срок ожидания, сек.##queue_max_age',ui.queue_max_age,0,0)
        imgui.TextWrapped('Запросы идут по порядку. Время подтверждения отсчитывается при показе запроса. ESC и отключение очищают очередь.')
        if columns then imgui.NextColumn() end
        section('Уведомления')
        toggle('Показывать статусы в чате', ui.show_chat_messages, 'local_messages')
        imgui.TextWrapped('Новый запрос и клавиши подтверждения показываются всегда.')
        toggle('Звук при новом запросе', ui.sound_notify_enabled, 'sound')
        toggle('Показывать итоговую команду в чате', ui.show_final_command_message, 'final_command')
        toggle('Показывать запрос поверх игры', ui.show_request_overlay, 'overlay')
        if request_overlay_fault then
            imgui.TextWrapped('Плашка отключена после ошибки отрисовки. Команды продолжают работать.')
            if imgui.Button('Повторить отрисовку плашки##overlay_retry') then request_overlay_fault=nil end
        end
        toggle('Сообщать в /a о чужом наказании', ui.track_other_admin_punishments, 'other_admin')
        section('Журнал')
        toggle('Записывать запросы в журнал', ui.log_captured_requests, 'log_commands')
        toggle('Показывать диагностику', ui.debug_enabled, 'debug')
        if columns then imgui.Columns(1) end
    end

    local function draw_commands()
        section('Группы команд')
        for _, key in ipairs({'forum_notice', 'no_notice', 'admin_chat', 'report'}) do
            local group = get_group_config(key)
            if group then
                local _, count = get_group_preview_lines(key, 3)
                local width = imgui.GetContentRegionAvail().x
                local columns = width >= 500
                if columns then
                    imgui.Columns(2, 'command_group_' .. key, false)
                    imgui.SetColumnWidth(0, width - 184)
                end
                imgui.Text(group.title)
                imgui.TextWrapped(group.hint)
                imgui.TextDisabled('Команд: ' .. count)
                if columns then imgui.NextColumn() end
                if imgui.Button('Редактировать##' .. key, imgui.ImVec2(166, 34)) then open_command_editor(key); imgui.SetScrollY(0) end
                if columns then imgui.Columns(1) end
                imgui.Spacing()
                imgui.Separator()
            end
        end
    end

    local function draw_chains()
        if not chain_editor then chain_editor=integration.service('aegis_chain_editor.lua').new(imgui,ffi,get_imgui_buffer_text(ui.command_chains)) end
        chain_editor:draw(function(trigger)
            local commands=rebuild_command_group(get_imgui_buffer_text(ui.admin_chat_commands_text))
            local reports=rebuild_report_command_group(get_imgui_buffer_text(ui.report_commands_text))
            return commands[trigger] or reports[trigger]
        end,function(trigger)
            local text=get_imgui_buffer_text(ui.admin_chat_commands_text)
            if #text+#trigger+1<ffi.sizeof(ui.admin_chat_commands_text) then
                set_imgui_buffer(ui.admin_chat_commands_text,text..'\n'..trigger)
            else state.settings_error='Список команд заполнен.' end
        end)
    end

    local function draw_notice()
        local _, local_name = get_local_identity()
        local author = state.pending_request and state.pending_request.admin_name or local_name or 'Nick_Name'
        section('Уведомление о форуме через /ans')
        imgui.PushItemWidth(-1)
        for index = 1, 3 do
            local buffer = ui['forum_notice_line_' .. index]
            imgui.TextDisabled('Строка ' .. index)
            imgui.InputText('##forum_notice_line_' .. index .. '_paged', buffer, ffi.sizeof(buffer))
        end
        imgui.PopItemWidth()
        section('Уведомление о сложении сроков')
        toggle('Отправлять /ans о сложении сроков',ui.stack_notice_enabled,'stack_notice')
        imgui.PushItemWidth(-1)
        imgui.InputText('##stack_notice_template',ui.stack_notice_template,ffi.sizeof(ui.stack_notice_template))
        imgui.PopItemWidth()
        imgui.TextWrapped('Переменные: {old}, {added}, {total}, {nick}, {id}. Это уведомление настраивается отдельно от сообщения о форуме.')
        section('Подпись наказания')
        meta('Шаблон', get_signature_label(ui.signature_mode[0]))
        meta('Пример', get_signature_text(author,ui.signature_mode[0],get_imgui_buffer_text(ui.custom_signature)))
        imgui.Spacing()
        if imgui.Button('Предыдущий##signature_paged', imgui.ImVec2(132, 30)) then
            ui.signature_mode[0] = ui.signature_mode[0] - 1
            if ui.signature_mode[0] < 1 then ui.signature_mode[0] = #SIGNATURE_VARIANT_LABELS end
        end
        imgui.SameLine()
        if imgui.Button('Следующий##signature_paged', imgui.ImVec2(132, 30)) then
            ui.signature_mode[0] = ui.signature_mode[0] + 1
            if ui.signature_mode[0] > #SIGNATURE_VARIANT_LABELS then ui.signature_mode[0] = 1 end
        end
        if ui.signature_mode[0]==17 then
            imgui.PushItemWidth(-1)
            imgui.InputText('##custom_signature',ui.custom_signature,ffi.sizeof(ui.custom_signature))
            imgui.PopItemWidth()
            imgui.TextWrapped('Переменные: {admin}, {first}, {last}, {initials}.')
        end
    end

    local function draw_keys()
        if not draft_keys then draft_keys=rules.keyDraft(integration.keys) end
        integration.keys.externalCapture=draft_keys
        integration.keys.externalCaptureUntil=integration.keys.api.getGameTimer()+300
        draft_keys:draw(imgui,'punish_confirm')
        draft_keys:draw(imgui,'punish_cancel')
    end

    AEGIS_ACTIVE_SETTINGS_PAGE = AEGIS_ACTIVE_SETTINGS_PAGE or 1
    AEGIS_SETTINGS_PAGES = {'Обработка', 'Команды', 'Уведомление', 'Клавиши', 'Цепочки'}
    integration.drawSettings = function()
        if AEGIS_ACTIVE_SETTINGS_PAGE~=4 and draft_keys then draft_keys:cancelCapture() end
        if not integration.access:can(2) then imgui.TextWrapped('Обработка ручных наказаний доступна с 2 уровня.');return end
        if not integration.access:can(3) then
            section('Ручная выдача наказаний')
            imgui.TextWrapped('Сложение срока работает при ручной выдаче. Приём запросов из /a и их подтверждение доступны с 3 уровня.')
            toggle('Складывать сроки jail / offjail',ui.stack_jail_enabled,'stack_jail')
            toggle('Складывать сроки mute / offmute',ui.stack_mute_enabled,'stack_mute')
            toggle('Защищать администраторов и лидеров',ui.block_known_admin_targets,'block_admin_targets')
            toggle('Выбирать команду по статусу игрока', ui.auto_switch_online_offline, 'switch_online')
            toggle('Уведомлять о форуме через /ans', ui.pre_punish_notice_enabled, 'ans_notice')
            for index=1,3 do
                local buffer=ui['forum_notice_line_'..index]
                imgui.InputText('##manual_notice_'..index,buffer,ffi.sizeof(buffer))
            end
            draw_notice()
            if state.settings_error then imgui.TextWrapped(state.settings_error) end
            if imgui.Button('Сохранить##manual_settings') then save_aegis_draft() end
            if imgui.Button('Отменить изменения##manual_settings') then sync_ui_from_settings() end
            return
        end
        imgui.TextWrapped('Изменения на всех вкладках применяются только по кнопке «Сохранить».')
        if state.settings_error then imgui.TextWrapped(state.settings_error) end
        if command_editor.window[0] then draw_command_editor(); return end
        editor_group = nil
        local width = imgui.GetContentRegionAvail().x
        local per_row = width < 280 and 1 or (width < 640 and 2 or 4)
        local tab_width = math.min(150, math.max(80, (width - (per_row - 1) * 8) / per_row))
        for index, title in ipairs(AEGIS_SETTINGS_PAGES) do
            if (index - 1) % per_row ~= 0 then imgui.SameLine() end
            local selected = AEGIS_ACTIVE_SETTINGS_PAGE == index
            if selected then imgui.PushStyleColor(imgui.Col.Button, integration.color(integration.palette.selection)) end
            if imgui.Button(title .. '##page_' .. index, imgui.ImVec2(tab_width, 30)) then
                AEGIS_ACTIVE_SETTINGS_PAGE = index
                imgui.SetScrollY(0)
            end
            if selected then imgui.PopStyleColor(1) end
        end
        if AEGIS_ACTIVE_SETTINGS_PAGE == 1 then draw_toggles(width)
        elseif AEGIS_ACTIVE_SETTINGS_PAGE == 2 then draw_commands()
        elseif AEGIS_ACTIVE_SETTINGS_PAGE == 3 then draw_notice()
        elseif AEGIS_ACTIVE_SETTINGS_PAGE == 4 then draw_keys() else draw_chains() end
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        if imgui.Button('Сохранить##paged', imgui.ImVec2(130, 30)) then
            save_aegis_draft()
        end
        imgui.SameLine()
        if imgui.Button('Отменить изменения##paged', imgui.ImVec2(180, 30)) then
            sync_ui_from_settings();state.settings_error=nil
        end
        if imgui.Button('По умолчанию на всех вкладках##paged') then
            local saved={};for k,v in pairs(SETTINGS)do saved[k]=v end
            copy_defaults();sync_ui_from_settings()
            for k,v in pairs(saved)do SETTINGS[k]=v end
            draft_keys.data.punish_confirm={key=DEFAULT_SETTINGS.confirm_key}
            draft_keys.data.punish_cancel={key=DEFAULT_SETTINGS.cancel_key}
            draft_keys.dirty.punish_confirm=true;draft_keys.dirty.punish_cancel=true
            state.settings_error='Значения по умолчанию подготовлены. Нажмите «Сохранить» для применения.'
        end
    end

    integration.status = function()
        return {enabled = SETTINGS.enabled, pending = state.pending_request ~= nil, queued = #state.outgoing_queue, waiting = #state.request_queue}
    end

    integration.draw = function()
        if not integration.access:can(3) then imgui.TextWrapped('Автовыдача доступна с 3 уровня администратора.');return end
        local width = imgui.GetContentRegionAvailWidth()
        local columns = width >= 680
        if columns then
            imgui.Columns(2, 'punishment_overview', false)
            imgui.SetColumnWidth(0, width * 0.60)
        end
        section('Активный запрос')
        if state.pending_request then
            local request = state.pending_request
            local expires = math.max(0, math.floor(SETTINGS.request_timeout - (os.clock() - request.created_at)))
            local command = build_issued_command(request)
            meta('Администратор', request.admin_name .. '[' .. tostring(request.admin_id) .. ']')
            meta('Игрок', request.target_label or '—')
            imgui.TextWrapped(request.command_text)
            if command ~= request.command_text then meta('Итоговая команда', command) end
            imgui.Spacing()
            imgui.TextDisabled('До отмены: ' .. expires .. ' сек.')
            if imgui.Button('Выдать', imgui.ImVec2(120, 32)) then handle_confirm() end
            imgui.SameLine()
            if imgui.Button('Отменить', imgui.ImVec2(120, 32)) then handle_cancel() end
        else
            imgui.TextDisabled('Новых запросов нет')
            imgui.TextWrapped('Новый запрос из /a появится здесь с игроком, автором и командой.')
        end
        section('Состояние')
        imgui.TextColored(integration.color(SETTINGS.enabled and integration.palette.green or integration.palette.muted),
            SETTINGS.enabled and 'Обработка запросов включена' or 'Обработка запросов выключена')
        imgui.TextWrapped(state.status_line ~= '' and state.status_line or 'Готово к работе.')
        meta('Команд на отправку', #state.outgoing_queue)
        meta('Запросов ожидают',#state.request_queue)
        for index,request in ipairs(state.request_queue)do
            imgui.TextWrapped(index..'. '..request.admin_name..': '..request.command_text)
        end
        if #state.request_queue>0 and imgui.Button('Очистить очередь запросов') then state.request_queue={} end
        if columns then imgui.NextColumn() end
        section('Защищённые игроки')
        local snapshot=integration.protectedLists and integration.protectedLists(false)
        local admins,leaders,unique={},{},{}
        if snapshot then
            for _,name in ipairs(snapshot.admins) do admins[lower(name)]=true;unique[lower(name)]=true end
            for _,name in ipairs(snapshot.leaders) do leaders[lower(name)]=true;unique[lower(name)]=true end
        end
        local function count(set) local n=0;for _ in pairs(set) do n=n+1 end;return n end
        meta('Администраторы',snapshot and count(admins) or state.known_admin_only_count)
        meta('Лидеры',snapshot and count(leaders) or state.known_leader_count)
        meta('Уникальных ников',snapshot and count(unique) or state.known_admin_count)
        imgui.TextWrapped(SETTINGS.block_known_admin_targets and 'Защита включена' or 'Защита администраторов и лидеров выключена, включая ban и warn.')
        
        if imgui.Button('Перечитать списки') then refresh_protected_list() end
        if imgui.Button('Настроить списки в чекере') then integration.openSettings('adm') end
        imgui.Spacing()
        section('Шаблоны команд')
        meta('С уведомлением о форуме', count_command_group(state.forum_notice_commands))
        meta('Без уведомления', count_command_group(state.no_notice_commands))
        meta('Из админ-чата', count_command_group(state.admin_chat_commands))
        meta('С отчётом', count_command_group(state.report_commands))
        imgui.TextWrapped('Числа выше — количество шаблонов в группах, не игроков и не выданных наказаний.')
        imgui.Spacing()
        if imgui.Button('Открыть справку', imgui.ImVec2(168, 30)) then integration.openHelp('punishments') end
        imgui.Spacing()
        imgui.TextWrapped('Шаблоны, уведомления и клавиши — во вкладке «Настройки».')
        if columns then imgui.Columns(1) end
    end

end

integration.protectionEnabled=function()return SETTINGS.block_known_admin_targets~=false end

integration.matchPunishment=function(command,text,expectedTarget)
    local kind,target=command:match('^/(%S+)%s+(%S+)')
    if not kind then return false end
    kind=kind:lower()
    local verbs={offban='забанил',ban='забанил',jail='посадил',offjail='посадил',mute='затычку',offmute='затычку',warn='предупреждение',offwarn='предупреждение',kick='кикнул'}
    if not verbs[kind] or not text:find(verbs[kind],1,true) then return false end
    local id=tonumber(target)
    local nick=expectedTarget or (id and sampIsPlayerConnected(id) and sampGetPlayerNickname(id) or target)
    local issuer= parse_punishment_info_for_request(text,{kind="/"..kind,target_name=nick,target_id=id,target_label=nick})
    local _,localName=get_local_identity()
    return issuer~=nil and localName~=nil and lower(issuer)==lower(localName)
end

if ui then
	setup_aegis_ui()
end

function integration.start()
	while not isSampAvailable() do
		wait(100)
	end

	math.randomseed(os.time() + math.floor(os.clock() * 1000))
	math.random()
	math.random()

	ensure_files()
	load_settings_file()
    integration.keys:register('punish_confirm','Автовыдача: подтвердить',{key=SETTINGS.confirm_key},function(bind) SETTINGS.confirm_key=bind.key end)
    integration.keys:register('punish_cancel','Автовыдача: отменить',{key=SETTINGS.cancel_key},function(bind) SETTINGS.cancel_key=bind.key end)
	load_known_admins()
	sync_ui_from_settings()

	debug_message(string.format("Старт скрипта. admin_chat_color=%d, debug=%s, ans=%s", SETTINGS.admin_chat_color, tostring(SETTINGS.debug_enabled), tostring(SETTINGS.pre_punish_notice_enabled)), true)

	while true do
		wait(0)
		process_pending()
		safe_draw_pending_request_overlay()
	end
end

function integration.stop()
    clear_afk_sensitive_contexts()
	do
		release_request_overlay_fonts()
	end
end

function sampev.onServerMessage(color, text)
	text = cp1251_to_utf8(text)

	local is_candidate = is_debug_candidate(color, text)

	if is_candidate then
		debug_message(string.format("Входящее сообщение: color=%d, text=%s", color, text), true)
	end

	if is_user_afk_protected() then
		if not state.afk_guard_active then
			state.afk_guard_active = true
			clear_afk_sensitive_contexts()
		end
		return
	end

	if is_afk_exit_suppressed() then
		if is_candidate then
			debug_message("Игнор: сообщение пропущено во время защиты после выхода из AFK.", true)
		end
		return
	end

	if state.awaiting_punishment_guard_context ~= nil then
		local queued_issuer_name = parse_punishment_info_for_request(text, state.awaiting_punishment_guard_context)

		if queued_issuer_name ~= nil then
			finalize_queued_punished(state.awaiting_punishment_guard_context, queued_issuer_name)
			return
		end
	end

	if handle_existing_term_stack(text) then
		return
	end

	if handle_online_offline_switch_hint(text) then
		return
	end

    local response_context=state.awaiting_database_lookup_context
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

    for _,queued in ipairs(state.request_queue)do
        if parse_punishment_info_for_request(text,queued) then queued.invalidated='Игрок уже наказан' end
    end
	if state.pending_request ~= nil then
		local issuer_name = parse_punishment_info_for_request(text, state.pending_request)

		if issuer_name ~= nil then
			finalize_pending_punished(state.pending_request, issuer_name, string.format("Ожидающая команда снята: игрок %s уже наказан администратором %s.", get_request_target_display_name(state.pending_request), issuer_name))
			return
		end
	end

	if should_cancel_on_server_activity(color, text) then
		debug_message("Сработала автоотмена по активности цели.", true)
		cancel_pending("Запрос отменён: сервер сообщил о действиях с этим игроком.", "Запрос отменён: сервер сообщил о действиях с этим игроком.")
		return
	end

	if not SETTINGS.enabled then
		if is_candidate then
			debug_message("Игнор: функция выключена.", true)
		end
		return
	end

	if color ~= SETTINGS.admin_chat_color then
		if is_candidate then
			debug_message(string.format("Игнор: цвет %d не совпадает с настройкой %d.", color, SETTINGS.admin_chat_color), true)
		end
		return
	end

	if isGamePaused() or isPauseMenuActive() then
		debug_message("Игнор: игра на паузе или открыто меню паузы.", true)
		return
	end

	if text:find("]: /", 1, true) == nil then
		debug_message("Игнор: в сообщении нет фрагмента ']: /'.", true)
		return
	end

	local admin_name, admin_id, command_text = text:match("%[A%]%s*(.-)%[(%d+)%]%s*:%s*(/.*)")

	if not admin_name or not admin_id or not command_text then
		debug_message("Игнор: не удалось распознать ник, ID или команду.", true)
		return
	end

	command_text = trim(command_text)
	debug_message(string.format("Парсер строки: admin=%s, id=%s, command=%s", admin_name, admin_id, command_text), true)

	local command_name = get_command_name_from_text(command_text)

	if not is_reactive_command(command_name) then
		debug_message("Игнор: команда не входит в группу отслеживания админ-чата: " .. tostring(command_name or command_text), true)
		return
	end

	local request = parse_admin_chat_request(admin_name, admin_id, command_text)

	if request == false then
		debug_message("Команда распознана, но цель не в сети: " .. command_text, true)
		message(string.format("Запрос %s[%s] пропущен: игрок с указанным ID не в сети.", admin_name, admin_id), true)
		append_log(string.format("Команда из админ-чата от %s[%s] проигнорирована: указанный ID не в сети: %s", admin_name, admin_id, command_text))
		append_request_log("IGNORED", {
			admin_name = admin_name,
			admin_id = tonumber(admin_id),
			command_text = command_text,
			target_label = "-",
			target_name = "-"
		}, "указанный ID не в сети", nil)
		return
	end

	if request == nil then
		debug_message("Игнор: команда не поддерживается парсером: " .. command_text, true)
		return
	end

	if not is_reactive_command(request.kind) then
		debug_message("Игнор: команда не входит в список реакций: " .. request.kind, true)
		return
	end

	if is_user_afk_protected() then
		debug_message("Игнор: запрос из админ-чата пропущен из-за AFK защиты.", false)
		return
	end

	if is_afk_exit_suppressed() then
		debug_message("Игнор: запрос из админ-чата пропущен во время защиты после выхода из AFK.", false)
		return
	end

	debug_message("Команда успешно распознана и передаётся в захват.", true)
    if not integration.access:can(3) then return end
    request.received_at=os.clock()
    for _,queued in ipairs(state.request_queue)do
        if queued.command_text==request.command_text and queued.admin_name==request.admin_name then return end
    end
    if state.pending_request and state.pending_request.command_text==request.command_text and state.pending_request.admin_name==request.admin_name then return end
    if #state.request_queue>=SETTINGS.queue_limit then
        message('Очередь запросов заполнена: новый запрос пропущен.',true)
        append_request_log('QUEUE_FULL',request,'очередь заполнена');return
    end
    table.insert(state.request_queue,request)
    append_request_log('QUEUED',request,'ожидает своей очереди')
    advance_aegis_request_queue()
end

function sampev.onSendCommand(command)
	touch_user_activity()

	if state.bypass_outgoing_hook > 0 then
		return
	end
    -- An unrelated manual command makes a subsequent unlabelled error ambiguous.
    state.awaiting_database_lookup_context=nil

	local command_text = trim(cp1251_to_utf8(command or ""))

	if command_text == "" then
		return
	end

	local command_name = get_command_name_from_text(command_text)

	if command_name == nil then
		return
	end

	if not is_manual_command_tracked(command_name) then
		return
	end

	local request = parse_manual_outgoing_request(command_text)

	if request == nil then
		if is_forum_notice_command(command_name) and SETTINGS.pre_punish_notice_enabled then
			debug_message("Ручная команда из списка реакций не была обработана: цель не определилась как онлайн: " .. command_text, true)
		end
		return
	end

	local local_switch = build_local_online_switch_result(request, request.command_text)

	if local_switch ~= nil then
		state.awaiting_online_offline_switch_context = nil
		debug_message("Ручная команда локально автопереключена: " .. request.command_text .. " -> " .. local_switch.command_text, true)
		message(string.format("Команда изменена по статусу игрока: %s → %s", request.command_text, local_switch.command_text), true)
		append_log(string.format("Ручная команда локально автопереключена: %s -> %s", request.command_text, local_switch.command_text))
		queue_pre_punish_bundle(local_switch.request, local_switch.command_text, "manual-local-online-switch")

		if should_send_pre_punish_notice(local_switch.request) then
			message(string.format("Перед наказанием %s будут отправлены уведомления /ans.", local_switch.request.target_label or ("ID " .. tostring(local_switch.request.target_id or "?"))), true)
		end

		return false
	end


	if is_forum_notice_command(command_name) and SETTINGS.pre_punish_notice_enabled then
		debug_message("Перехвачена ручная команда: " .. request.command_text, true)

		if not is_request_target_online(request) then
			if SETTINGS.auto_switch_online_offline == true then
				local switch_context = build_online_offline_switch_context(request, request.command_text, nil)

				if switch_context ~= nil then
					state.awaiting_online_offline_switch_context = switch_context
					append_log(string.format("Ручная команда поставлена на автопереключение: %s", request.command_text))
				end
			end

			debug_message("Ручная команда из группы форум-уведомлений пропущена без /ans: цель не в онлайне: " .. command_text, true)
			return
		end

		queue_pre_punish_bundle(request, request.command_text, "manual-command")
		message(string.format("Перед наказанием %s будут отправлены уведомления /ans.", request.target_label or ("ID " .. tostring(request.target_id or "?"))), true)
		return false
	end

	if SETTINGS.auto_switch_online_offline == true then
		local switch_context = build_online_offline_switch_context(request, request.command_text, nil)

		if switch_context ~= nil then
			state.awaiting_online_offline_switch_context = switch_context
			append_log(string.format("Ручная команда поставлена на автопереключение: %s", request.command_text))
		end
	end

	local stack_term_context = get_stackable_term_context(request, request.command_text, nil)

	if stack_term_context ~= nil then
		state.awaiting_stack_term_context = stack_term_context
	end

	debug_message("Отслеживается ручная команда без очереди: " .. request.command_text, false)
end

function sampev.onPlayerQuit(playerId, reason)
    for _,request in ipairs(state.request_queue)do if request.target_id==playerId then request.invalidated="Игрок вышел с сервера" end end
	local request = state.pending_request

	if request == nil or request.target_id == nil or not is_online_punish_command(request.kind) then
		return
	end

	if tonumber(request.target_id) ~= tonumber(playerId) then
		return
	end

	debug_message(string.format("Игрок %s[%d] вышел из игры во время ожидания команды.", request.target_name or "?", request.target_id), true)
	finalize_pending_target_left(request, string.format("Ожидающая команда снята: игрок %s[%d] вышел из игры.", request.target_name or "?", request.target_id))
end

-- A reconnect invalidates pending requests, targets and delayed commands.
integration.onDisconnect = function()
    clear_afk_sensitive_contexts()
    state.next_outgoing_at = 0
    state.bypass_outgoing_hook = 0
end
