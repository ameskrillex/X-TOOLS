-- X-TOOLS | Project and integration: Casual_Alvarez | Module: runtime.lua
-- Original third-party credits, where present, are retained below.
-- CasualTool application lifecycle, services and feature namespaces (LuaJIT 2.1).
local Runtime = {}
Runtime.__index = Runtime
local unpack = unpack
local function pack(...) return {n = select('#', ...), ...} end
local function copy(t)
    local result = {}
    for k, v in pairs(t) do result[k] = v end
    return result
end

local names={beautifulsky='Красивое небо · BeautifulSky',nakaz='Безопасная выдача наказаний',adminzone='AdminZone',airbreak='AirBreak',broom='Метла',core='Основные инструменты',familia='Семьи',adm='Чекер',aegis='Наказания',
    reminders='Напоминание игрокам в msg',tpm='Интерьеры и площадки для мероприятий',speed_boost='Ускорение транспорта',clickwarp='ClickWarp',invisible='Невидимость',
    gang='Банды',joinquit='Входы и выходы',killids='ID в списке убийств',
    online='Чистый онлайн',hospital='Перемещение игроков',menu='Наблюдение',road='Перемещение на дорогу',tempfamily='Временная семья',lego='LEGO',autostart='Команды при старте',autoreply='Автоответ',movement='Движение и трюки',
    environment='Местные время и погода',queue='Очередь из файла',lookup='Проверка игрока',
    capture='Капты',bullet='Траектории выстрелов',stopsbiv='Контроль аптечек'}

-- Release factories are compiled as part of CasualAT.lua. Never fall back to
-- files from an older installation when a release entry is missing.
function Runtime:source(name)
    if self.sources then
        return self.sources[name], 'Missing built-in X-Tools source: '..name
    end
    return loadfile(self.base..'/'..name) -- development checkout only
end

function Runtime:service(name)
    if self.services[name]==nil then
        self.services[name]=assert(self:source(name))()
    end
    return self.services[name]
end

function Runtime.new(base, host, sources, release)
    local self = setmetatable({base = base, host = host, api = copy(_G),
        sources = sources, release = release or {}, services = {},
        modules = {}, order = {}, commands = {}, eventNames = {}, stopped = false}, Runtime)
    self.theme = self:service('theme.lua')
    self.pointerInside=self:service('pointer_bounds.lua').new()
    self.workspace = self:service('workspace.lua')
    self.guide = self:service('help.lua')
    self.typography = self:service('typography.lua').new(base,copy(_G))
    local root = host.path and host.path:match('^(.*)[/\\]') or self.api.getWorkingDirectory()
    local storageApi=copy(self.api)
    storageApi.storageError=function(err)
        self.api.print(err)
        local clock=self.api.os.clock()
        if not self.storageErrorAt or clock-self.storageErrorAt>10 then
            self.storageErrorAt=clock
            self:message('Не удалось сохранить или перенести данные.\nПодробности — в moonloader.log.\nСостояние: /xt > «Система X-Tools» (значок настроек).')
        end
    end
    self.storage = self:service('storage.lua').new(storageApi, root)
    storageApi.storageRecovered=function(text)self:message(text)end
    self.settingsTransfer=self:service('settings_transfer.lua').new({storage=self.storage,
        codec=self:service('settings_code.lua'),hash=self:service('sha256.lua'),
        encodeJson=self.api.encodeJson,decodeJson=self.api.decodeJson})
    local transferOk,transferNotice=pcall(self.settingsTransfer.applyPending,self.settingsTransfer)
    self.transferNotice=transferNotice
    if not transferOk then self.transferNotice='Импорт настроек: '..tostring(transferNotice)end
    self.preferences=self:service('preferences.lua').new(self.storage)
    self.theme.apply(self.preferences.colors[self.preferences.data.main.color][2])
    self.toasts=self:service('toasts.lua').new(function() return self.api.getGameTimer() end)
    self.powered=true
    self.clock=self:service('clock_settings.lua').new(self.api.os,self.preferences)
    self.nativeFonts=self:service('native_fonts.lua').new(self.api,self.preferences)
    self.keys=self:service('keybinds.lua').new(self.api,self.storage)
    self.typography.preference=self.preferences.data.main.font
    self.offban=self:service('offban_guard.lua').new(self)
    self.schedule = self:service('schedule.lua').new(self.storage)
    self.eventNotice=self:service('event_notice.lua').new(self.storage)
    self.updateNotice=self:service('update_notice.lua').new()
    self.access = self:service('access.lua').new(self.api)
    self.accessSerial,self.accessIdentity=self.access:revision(),self.access.identity
    self.updates = self:service('updates.lua').new(self:service('update_adapter.lua').new(self),host,self.release)
    return self
end

function Runtime:welcome()
    local u8=self.api.require('encoding').UTF8
    self.api.print('[X-Tools] Loaded and ready. /xt')
    if self.transferNotice then self:message(self.transferNotice)end
    if self.preferences.recoveryNotice then self:message(self.preferences.recoveryNotice);self.preferences.recoveryNotice=nil end
    for _,line in ipairs({
        '{B5A0FF}========== {FFFFFF}X-TOOLS {B5A0FF}==========',
        '{B5A0FF}BY CASUAL ALVAREZ {777785}| {D6F5DC}ЗАГРУЖЕН И ГОТОВ К РАБОТЕ',
        '{B5A0FF}/xt {D9D9E5}— открыть панель управления'
    })do self.api.sampAddChatMessage(u8:decode(line),-1)end
end

function Runtime:isChatVisible()
    local m=self.modules.chat_appearance
    if m and m.enabled and m.bridge.nativeVisible then
        local visible=m.bridge.nativeVisible()
        if visible~=nil then return visible end
    end
    return self.api.sampIsChatVisible()
end
function Runtime:chat(text,color)
    local u8=self.api.require('encoding').UTF8
    local decoded=self.preferences:mask(tostring(u8(text)))
    local styled=self:service('chat_style.lua').format(decoded,self.theme.palette)
    local result
    for _,line in ipairs(self:service('chat_style.lua').lines(u8:decode(styled),self.theme.palette)) do
        result=self.api.sampAddChatMessage(line,color)
    end
    return result
end

function Runtime:message(text)
    self.api.print('[X-Tools] ' .. text)
    if self.api.sampAddChatMessage and self.api.isSampAvailable() then
        local u8 = self.api.require('encoding').UTF8
        local readable=tostring(text):gsub('→','>'):gsub('←','<')
        if self.preferences then readable=self.preferences:mask(readable) end
        for line in readable:gmatch('[^\r\n]+')do
            local ok,encoded=pcall(u8.decode,u8,'[X-Tools] '..line)
            if not ok then encoded=u8:decode('[X-Tools] Подробности сообщения — в moonloader.log.') end
            self:chat(encoded, -1)
        end
    end
end

function Runtime:setPowered(value)
    value=value==true
    if value and not self.access:canUseTools() then self:message('Скрипт предназначен для администраторов Advance RP. Войдите в аккаунт администратора.');return end
    if self.powered==value then return end
    if not value then
        if self.placement then self:finishPlacement()end
        for _,m in ipairs(self.order)do
            self.offban:cancel(m.id)
            if m.bridge then
                if m.bridge.suspend then self:call(m,m.bridge.suspend)
                else
                    if m.id~='core' then self:call(m,m.bridge.stop)end
                    self:call(m,m.bridge.onDisconnect)
                end
                if m.gui then m.gui.Process=false end
            end
        end
        if self.fastConnect then self.fastConnect:stop();self.fastConnect=nil end
        if self.overlayVisible then self.overlayVisible.v=false end
        self.keys:cancelCapture()
    end
    local core=self.modules.core
    if core and core.bridge and core.bridge.onPowerChanged then self:call(core,core.bridge.onPowerChanged,value)end
    self.powered=value
    self.toasts:push('X-TOOLS',value)
    if value and self.started and self.api.getModuleHandle then self.fastConnect=self:service('fastconnect.lua').start(self.api)end
    if core then core.gui.Process=true end
    if _G.show_main_window then _G.show_main_window.v=true end
    self:syncGui()
end
function Runtime:featureAllowed(id)
    local policy=self:service('permissions.lua')
    if self.access:displayLevel()=='S1' then
        if not policy.s1Modules[id] then return false end
    elseif id~='integration' and not self.access:can(policy.modules[id] or 1) then return false end
    if self.powered==false and id~='integration' then return false end
    local p=self.preferences.data.main
    if id=='capture' or id=='gang' then return p.ghetto end
    if id=='familia' or id=='family_registry' or id=='family_mask_warning' or id=='family_weapon_warning' then return p.families end
    if id=='killids' then return p.killidsKiller or p.killidsVictim end
    if id=='stopsbiv' then return p.medkitMode=='ghetto' and p.ghetto or p.medkitMode=='families' and p.families end
    return true
end
function Runtime:setFeature(key,value)
    local p=self.preferences.data.main
    local previous=p[key];p[key]=value
    if key=='ghetto' and value==true and previous~=true then
        self:message('Работа с зоопарком включена')
    end
    if not value and (key=='ghetto' or key=='families') then
        if p.medkitMode==key then p.medkitMode='none' end
        for _,id in ipairs(key=='ghetto' and {'capture','gang','stopsbiv'} or {'familia','family_registry','family_mask_warning','family_weapon_warning','stopsbiv'}) do
            self.offban:cancel(id)
            local m=self.modules[id];if m and m.bridge then self:call(m,m.bridge.onDisconnect) end
        end
    end
    local family=self.modules.familia
    if key=='families' and family and family.bridge.setEnabled then family.bridge.setEnabled(value) end
    self.preferences:save()
end

function Runtime:component(id)
    if not self.modules[id] then
        local m = {id = id, enabled = true, events = {}, gui = {}, fonts = {}}
        self.modules[id] = m
        self.order[#self.order + 1] = m
    end
    return self.modules[id]
end

function Runtime:call(m, fn, ...)
    if self.stopped or not m.enabled or not fn then return end
    local perf=self.performance
    local token
    if perf and perf.active then
        self.performanceLabels=self.performanceLabels or setmetatable({},{__mode='k'})
        local label=self.performanceLabels[fn]
        if not label then
            for name,value in pairs(m.bridge or {})do if value==fn then label=name;break end end
            if not label then for name,value in pairs(m.events or {})do if value==fn then label=name;break end end end
            label=label or 'callback';self.performanceLabels[fn]=label
        end
        token=perf:enter(m.id,label)
    end
    local args = pack(...)
    local result = pack(xpcall(function() return fn(unpack(args, 1, args.n)) end,
        function(err)
            if err == m.cancelled then return err end
            return debug.traceback(tostring(err), 2)
        end)) -- LuaJIT permits yielding through protected calls.
    if self.performance then self.performance:leave(token)end
    if not result[1] then
        if result[2] ~= m.cancelled then self:fail(m, result[2]) end
        return
    end
    return unpack(result, 2, result.n)
end

function Runtime:stop(m)
    if not m.enabled then return end
    m.enabled = false
    if m.bridge and m.bridge.stop then
        pcall(m.bridge.stop)
    end
    for font in pairs(m.fonts) do pcall(function() self.nativeFonts:release(font) end) end
    m.fonts = {}
    self:syncGui()
end

function Runtime:fail(m, err)
    m.error = tostring(err)
    self:stop(m)
    self.api.print('[X-Tools / '..m.id..'] '..m.error)
    self:message('«'..(names[m.id] or m.id)..'»: работа остановлена из-за ошибки. Подробности — в moonloader.log.')
end

function Runtime:events(id)
    local m = self:component(id)
    if m.eventProxy then return m.eventProxy end
    self.sampev = self.sampev or self.api.require('lib.samp.events')
    if not self.zoneWallModel then
        self.zoneWallModel=self:service('zone_wall.lua').new()
        for _,event in ipairs({'onSendChat','onPlayerQuit','onCreateGangZone','onGangZoneDestroy','onGangZoneFlash','onGangZoneStopFlash','onInitGame','onConnectionClosed','onConnectionLost','onGamemodeRestart'})do
            local key=event
            if not self.eventNames[key]then
                self.eventNames[key]=true
                self.sampev[key]=function(...)return self:dispatch(key,...)end
            end
        end
    end
    m.eventProxy = setmetatable({}, {
        __index = function(_, key) return m.events[key] or self.sampev[key] end,
        __newindex = function(_, key, fn)
            assert(fn == nil or type(fn) == 'function', 'Invalid event: ' .. key)
            m.events[key] = fn
            if not self.eventNames[key] then
                self.eventNames[key] = true
                self.sampev[key] = function(...) return self:dispatch(key, ...) end
            end
        end
    })
    return m.eventProxy
end

function Runtime:authenticator()
    if not self.authService then self.authService=self:service('authenticator.lua').new(self) end
    return self.authService
end

-- Final guard uses the saved protection setting; defaults to enabled when unavailable.
local protectedPhrases={'кристаллически похуй','абсолютно поебать','мне похуй'}
local function normalizeProtectedPhrase(text)
    return text:lower():gsub('[\208\209][\128-\191]',function(c)
        local a,b=c:byte(1,2)
        if a==208 and b>=144 and b<=159 then return string.char(208,b+32)end
        if a==208 and b>=160 and b<=175 then return string.char(209,b-32)end
        return c
    end):gsub('%s+',' '):match('^%s*(.-)%s*$')
end
function Runtime:blockProtectedPunishment(raw,manual)
    local aegis=self.modules.aegis
    if aegis and aegis.bridge and aegis.bridge.protectionEnabled then
        local ok,enabled=pcall(aegis.bridge.protectionEnabled)
        if ok and enabled==false then self.protectedConfirmation=nil;return false end
    end
    local command,target=tostring(raw or ''):match('^%s*/([%w_]+)%s+(%S+)')
    command=command and command:lower()
    if not ({ban=true,warn=true,sban=true,offban=true,offwarn=true})[command] then return false end
    local nickname=target
    if target:match('^%d+$') then
        -- Offline commands use account numbers, not live player IDs.
        if command=='offban' or command=='offwarn' then return false end
        local id=tonumber(target)
        if not self.api.sampIsPlayerConnected(id) then return false end
        nickname=self.api.sampGetPlayerNickname(id)
    end
    local adm=self.modules.adm
    if not (adm and adm.bridge and adm.bridge.isKnownAdmin) then return false end
    local ok,known=pcall(adm.bridge.isKnownAdmin,nickname)
    if ok and known then
        local text=tostring(raw)
        local pending=self.protectedConfirmation
        local now=self.api.getGameTimer()
        if manual and pending and pending.confirmed and pending.command==text
            and pending.nickname==nickname and now<=pending.expires then
            self.protectedConfirmation=nil
            return false,true
        end
        if not (pending and pending.command==text and pending.nickname==nickname and now<=pending.expires) then
            local targetId=target:match('^%d+$')and tonumber(target)or nil
            if not targetId then
                -- Nickname-based commands may still target an online player.
                -- Capture its slot now; it may no longer resolve in onPlayerQuit.
                for id=0,1004 do
                    if self.api.sampIsPlayerConnected(id) and self.api.sampGetPlayerNickname(id)==nickname then targetId=id;break end
                end
            end
            pending={command=text,nickname=nickname,targetId=targetId,expires=now+120000,
                phrase=protectedPhrases[math.random(#protectedPhrases)]}
        end
        pending.confirmed=false
        self.protectedConfirmation=pending
        -- Keep consuming a late reply briefly even if the pending command was
        -- cancelled by a disconnect, access change or target leaving the game.
        self.protectedPhraseWindow={started=now,expires=pending.expires+120000}
        self:message('Защита: '..tostring(nickname)..' — администратор или лидер.')
        self:message('Команда остановлена. Вы рискуете потерять права администратора.')
        self:message('Подтвердите риск в чате: «'..pending.phrase..'»')
        self:message('Фраза останется в скрипте. Регистр букв не важен.')
        self:message('Затем повторите ту же команду. На подтверждение — 2 минуты.')
        return true
    end
    return false
end

function Runtime:dispatch(name, ...)
    -- Native/launcher chat must not submit text intended for an X-Tools field.
    -- Explicit actions sent by our UI retain their normal guarded send path.
    if (name=='onSendChat' or name=='onSendCommand')and not self.outboundOwner and self:chatWindowOpen()then return false end
    if name=='onSendCommand' and self.powered~=false and not self.outboundOwner
        and self.preferences.data.main.commandLayout then
        local raw=(...)
        local converted=self:service('command_layout.lua').convert(raw)
        if converted~=raw then
            local kind=converted:match('^/([^%s]+)')
            if kind and self.api.sampIsChatCommandDefined and self.api.sampIsChatCommandDefined(kind) then
                if self:checkSession()==false or not self:commandAllowed(converted)then return false end
                local identity=self.access.identity
                self.api.lua_thread.create(function()
                    self.api.wait(0)
                    if not self.stopped and self.powered~=false and self.access.identity==identity
                        and not self:chatWindowOpen() and self:checkSession()~=false then
                        self.api.sampProcessChatInput(converted)
                    end
                end)
                return false
            end
            -- Re-enter normal permission/protection/module handling exactly once.
            local result=self:dispatch(name,converted)
            if result==false or type(result)=='table' then return result end
            return {converted}
        end
    end
    if name=='onInitGame' or name=='onConnectionClosed' or name=='onConnectionLost'
        or name=='onGamemodeRestart' then self.protectedConfirmation=nil end
    if name=='onPlayerQuit' and self.protectedConfirmation
        and self.protectedConfirmation.targetId==(...) then self.protectedConfirmation=nil end
    if name=='onSendChat' then
        local text=normalizeProtectedPhrase(tostring(self.api.require('encoding').UTF8((...) or '')))
        local isConfirmation=false
        for _,phrase in ipairs(protectedPhrases)do if text==phrase then isConfirmation=true;break end end
        local now=self.api.getGameTimer()
        local window=self.protectedPhraseWindow
        local recent=window and now>=window.started and now<=window.expires
        if isConfirmation and (self.protectedConfirmation or recent) then
            local sessionOk=self:checkSession()
            local pending=self.protectedConfirmation
            if self.outboundOwner then return false end -- automatic text cannot acknowledge a risk
            if sessionOk~=false and pending and self.api.getGameTimer()<=pending.expires then
                if text==pending.phrase then
                    pending.confirmed=true
                    self:message('Защита снята для одной команды. Отправьте её ещё раз.')
                else
                    self:message('Нужна фраза из запроса: «'..pending.phrase..'»')
                end
            else
                self.protectedConfirmation=nil
                self:message('Запрос истёк или отменён. Повторите команду наказания.')
            end
            return false
        end
    end
    if name=='onSendCommand' then
        if self:checkSession()==false then return false end
    end
    if name=='onSendCommand' and not self:commandAllowed((...)) then return false end
    if name=='onSendCommand' then
        local text=tostring(self.api.require('encoding').UTF8((...) or ''))
        local blocked,confirmed=self:blockProtectedPunishment(text,not self.outboundOwner)
        if blocked then return false end
        -- Explicit manual one-shot: send exactly the confirmed command, without
        -- Aegis rewriting, queuing or intercepting it as another punishment.
        if confirmed then return end
    end
    if name=='onHideMenu' and self.hidingServerMenu then return end
    if name=='onSendCommand' and not self.outboundOwner then self:traceInspection(nil,(...));self.offban:track((...))end
    if self:checkSession()==false then return end
    if self.zoneWallModel then self.zoneWallModel:observe(name,...)end
    -- Menu definitions are passive protocol data, not privileged actions.
    -- INITMENU can precede authorization and module startup; SHOWMENU reuses it.
    if self.menuCacheIdentity~=self.access.identity or name=='onInitGame'
        or name=='onConnectionClosed' or name=='onConnectionLost' or name=='onGamemodeRestart' then
        self.serverMenuDefinitions={};self.menuCacheIdentity=self.access.identity
    end
    if name=='onInitMenu' then
        local values=pack(...);local id=tonumber(values[1])
        if id and id>=0 and id<=127 then
            self.serverMenuDefinitions=self.serverMenuDefinitions or {}
            self.serverMenuDefinitions[id]=values
        end
    end
    if name=='onShowDialog' then
        local id,style,title,b1,b2,body=...
        if id==1 or id==88 then
            local encoding=self.api.require('encoding').UTF8
            local function clean(value) return encoding(tostring(value or '')):gsub('{%x%x%x%x%x%x}','') end
            if self.loginDialog then
                local ok,result=pcall(self.loginDialog,id,style,clean(title),clean(body))
                if not ok then self:message('Автовход не выполнен. Введите данные вручную.')
                elseif result==false then return false end
            end
            if self:authenticator():dialog(id,style,clean(title),clean(body))==false then return false end
        end
    elseif name=='onConnectionClosed' or name=='onConnectionRejected' or name=='onConnectionRequestAccepted' then
        if self.authService then self.authService.attempted=false end
    end
    if name=='onTogglePlayerControllable' then self.serverControllable=(...)~=false
    elseif name=='onInitGame' or name=='onConnectionClosed' or name=='onConnectionLost' then
        self.serverControllable=nil
    end
    self.access:observe(name, ...)
    if self.automaticLeader then self.automaticLeader:observe(name,...) end
    if name=='onTogglePlayerSpectating' then
        if (...)==false then
            self:requestSpectateInputRelease()
            self.spectateInputRelease.allowExit=true
            self.spectateExitUntil=self.api.getGameTimer()+3000
            self.spectateExitIdentity=self.access.identity
        else
            self.spectateExitUntil=nil
        end
    elseif name=='onConnectionClosed' or name=='onConnectionLost' or name=='onInitGame' then
        self.spectateInputRelease=nil;self.spectateExitUntil=nil
    elseif (name=='onSetPlayerPos' or name=='onSetPlayerPosFindZ' or name=='onSetInterior'
        or name=='onTogglePlayerControllable') and self.spectateExitUntil
        and self.spectateExitIdentity==self.access.identity
        and self.api.getGameTimer()<=self.spectateExitUntil then
        self:requestSpectateInputRelease()
        self.spectateInputRelease.allowExit=true
    end
    local guarded=self.offban:observe(name,...)
    if guarded==false then return false end
    self:syncAccessClients()
    if self.powered==false or not self.access:canUseTools() then return end
    local args, changed = pack(...), false
    for _, m in ipairs(self.order) do
        local result
        if not (self.offban.releasing and name=='onSendCommand' and m.id=='aegis') and (self:featureAllowed(m.id) or m.id=='capture' and name=='onCreate3DText') then result = self:call(m, m.events[name], unpack(args, 1, args.n)) end
        -- Preserve SAMP.Lua's cancellation semantics. Later consumers must not
        -- enqueue a second command or interpret a privately consumed dialog.
        if result == false then return false end
        if type(result) == 'table' then
            args = result
            args.n = args.n or #args
            changed = true
        end
    end
    if name=='onSendCommand' and not self.outboundOwner and not self.offban.releasing then
        local text=tostring(self.api.require('encoding').UTF8(args[1] or ''))
        if self.offban:enqueue('manual','sampSendChat',text) then return false end
    end
    if self.preferences.data.main.streamer then
        local fields=name=='onServerMessage' and {2} or name=='onShowDialog' and {3,6} or {}
        local u8=self.api.require('encoding').UTF8
        for _,index in ipairs(fields) do
            local raw=args[index];local masked=self.preferences:mask(tostring(u8(raw or '')))
            if masked~=tostring(u8(raw or '')) then args[index]=u8:decode(masked);changed=true end
        end
    end
    if name=='onSendCommand' and self:blockProtectedPunishment(args[1]) then return false end
    if changed then return args end
end

-- A placement session preserves navigation and the content scroll position.
function Runtime:beginPlacement(finish,update)
    if self.placement then self:finishPlacement() end
    self.placement={finish=finish,update=update,scroll=self.workspaceScroll or 0,started=self.api.getGameTimer()}
    if _G.show_main_window then _G.show_main_window.v=false end
    self:message('Переместите элемент мышью.\nEnter — сохранить и вернуться в настройки.')
end
function Runtime:finishPlacement()
    local session=self.placement;if not session then return end
    self.placement=nil
    if session.finish then session.finish()end
    self.restoreWorkspaceScroll=session.scroll
    if _G.show_main_window then _G.show_main_window.v=true end
end

function Runtime:inputSnapshot()
    local function read(fn)
        if type(fn)~='function' then return '?' end
        local ok,value=pcall(fn);return ok and tostring(value) or 'error'
    end
    local g=self.imgui or {}
    if g.SwitchContext then pcall(g.SwitchContext)end
    local parts={'version='..tostring(self.host.version),'cursor='..tostring(g.ShowCursor),
        'lock='..tostring(g.LockPlayer),'inputOff='..tostring(g.DisableInput),
        'native='..read(self.api.sampGetCursorMode),'chat='..read(self.api.sampIsChatInputActive),
        'dialog='..read(self.api.sampIsDialogActive),'marker='..tostring(_G.cursorEnabled),
        'main='..tostring(_G.show_main_window and _G.show_main_window.v),
        'overlay='..tostring(self.overlayVisible and self.overlayVisible.v),
        'placement='..tostring(self.placement~=nil)}
    if g.GetIO then local ok,io=pcall(g.GetIO);if ok and io then
        parts[#parts+1]='captureMouse='..tostring(io.WantCaptureMouse)
        parts[#parts+1]='captureKeys='..tostring(io.WantCaptureKeyboard)
        parts[#parts+1]='textInput='..tostring(io.WantTextInput)
        parts[#parts+1]='softwareCursor='..tostring(io.MouseDrawCursor)
    end end
    parts[#parts+1]='activeItem='..read(g.IsAnyItemActive)
    parts[#parts+1]='frame='..read(g.GetFrameCount)
    if self.lastInputClick then
        local click=self.lastInputClick
        parts[#parts+1]='field='..click.owner..'/'..click.kind
        parts[#parts+1]='fieldActive='..tostring(click.active)
        parts[#parts+1]='clickAge='..tostring(self.api.getGameTimer()-click.at)
    end
    for _,m in ipairs(self.order) do
        if m.enabled and m.bridge and m.bridge.hudActive then
            local ok,v,c,l=pcall(m.bridge.hudActive)
            if ok and (v or c)then parts[#parts+1]=m.id..'='..tostring(v)..'/'..tostring(c)..'/'..tostring(l)end
        end
        if m.gui and m.gui.Process then parts[#parts+1]=m.id..'.gui='..tostring(m.gui.ShowCursor)..'/'..tostring(m.gui.LockPlayer)end
    end
    return table.concat(parts,' ')
end

function Runtime:traceInput()
    self.inputTraceUntil=self.api.getGameTimer()+30000
    self.inputTraceFields={}
    self:message('Диагностика ввода включена на 30 секунд. Закройте чат, откройте нужное окно и нажмите на текстовое поле.')
    self.api.lua_thread.create(function()
        for i=1,30 do
            self.api.wait(1000)
            if self.stopped then return end
            self.api.print('[X-Tools INPUT] '..self:inputSnapshot())
        end
        self:message('Диагностика записана: пришлите строки [X-Tools INPUT] из moonloader.log.')
    end)
end

function Runtime:noteTextInput(owner,kind)
    local now=self.api.getGameTimer()
    if not self.inputTraceUntil or now>self.inputTraceUntil then return end
    local g=self.imgui
    if not g.IsItemHovered or not g.IsMouseClicked or not g.IsItemActive then return end
    local active,hover,clicked=g.IsItemActive()==true,g.IsItemHovered()==true,g.IsMouseClicked(0)==true
    if hover and clicked then self.lastInputClick={owner=owner,kind=kind,active=active,at=now}end
    -- Record interaction metadata only, never labels, buffers or typed characters.
    -- Do not call GetID here: its native KeepAliveID side effect changes the state
    -- we are diagnosing. Do not force keyboard focus or select the user's text.
    do
        local mouse=g.GetMousePos();local first,last=g.GetItemRectMin(),g.GetItemRectMax()
        -- Rectangles distinguish visible fields without reading labels or IDs.
        local field=owner..'/'..kind..string.format('/%.0f,%.0f',first.x,first.y)
        self.inputTraceFields=self.inputTraceFields or {}
        local previous=self.inputTraceFields[field]
        local frame=g.GetFrameCount()
        local state=tostring(active)..'/'..tostring(hover)
        self.inputTraceFields[field]={state=state,frame=frame}
        if clicked or active and not previous or previous and previous.state~=state then
            self.api.print('[X-Tools INPUT FIELD] '..self:inputSnapshot()..string.format(
                ' owner=%s kind=%s active=%s hover=%s click=%s tab=%s gap=%s mouse=%.0f,%.0f rect=%.0f,%.0f:%.0f,%.0f',
                owner,kind,tostring(active),tostring(hover),tostring(clicked),tostring(self.api.isKeyDown(9)),
                previous and tostring(frame-previous.frame)or '?',mouse.x,mouse.y,first.x,first.y,last.x,last.y))
        end
    end
end

-- Chat and server dialogs share SA-MP cursor capture. Release only after
-- the last input surface closes, keeping the current spectator camera intact.
function Runtime:releaseNativeSpectateInput()
    local api=self.api
    if type(api.showCursor)=='function' then api.showCursor(false,false) end
    if self.serverControllable==false then return end
    -- MoonLoader's control lock and SA-MP's camera cursor mode are independent.
    -- A hidden cursor can still leave CMODE_LOCKCAM_NOCURSOR active.
    if type(api.sampGetCursorMode)=='function' and type(api.sampSetCursorMode)=='function'
        and api.sampGetCursorMode()~=0 then api.sampSetCursorMode(0) end
    if type(api.isPlayerControlLocked)=='function' and type(api.lockPlayerControl)=='function'
        and api.isPlayerControlLocked() then api.lockPlayerControl(false) end
end

function Runtime:reconcileClosedChat()
    local api=self.api
    local chat=type(api.sampIsChatInputActive)=='function' and api.sampIsChatInputActive()
    local dialog=type(api.sampIsDialogActive)=='function' and api.sampIsDialogActive()
    local menu=self.modules.menu
    local observed=menu and menu.enabled and menu.bridge and menu.bridge.observation and self:call(menu,menu.bridge.observation)
    local now=api.getGameTimer()
    local previous=self.lastInputObservation
    self.lastInputObservation=observed and {identity=self.access.identity} or nil
    if previous and not observed and previous.identity==self.access.identity then
        self:requestSpectateInputRelease()
        self.spectateInputRelease.allowExit=true
    end
    if not observed then self.nativeInputSession=nil;return end
    local pending=self.nativeInputSession
    if pending and pending.identity~=self.access.identity then self.nativeInputSession=nil;pending=nil end
    if chat or dialog or self.imgui.ShowCursor or self.imgui.LockPlayer then
        self.nativeInputSession={identity=self.access.identity,after=now+100}
        return
    end
    if not pending then return end
    if self.imgui.ShowCursor or self.imgui.LockPlayer
        or (api.sampIsScoreboardOpen and api.sampIsScoreboardOpen())
        or (api.isPauseMenuActive and api.isPauseMenuActive())
        or (api.isGameWindowForeground and not api.isGameWindowForeground()) then
        pending.after=now+100;return
    end
    if now>=pending.after then
        self.nativeInputSession=nil
        self:releaseNativeSpectateInput()
    end
end

-- Spectate refreshes (including /tr follow-up) happen after chat cleanup.
-- Release a leftover native cursor only once, after the final server transition.
function Runtime:requestSpectateInputRelease()
    local now=self.api.getGameTimer()
    self.spectateInputRelease={after=now+150,expires=now+3000,identity=self.access.identity}
end
function Runtime:reconcileSpectateInput()
    local pending=self.spectateInputRelease
    if not pending then return end
    local api=self.api;local now=api.getGameTimer()
    local menu=self.modules.menu
    local observed=menu and menu.enabled and menu.bridge and menu.bridge.observation and self:call(menu,menu.bridge.observation)
    if pending.identity~=self.access.identity or now>pending.expires or now<pending.after-150 then
        self.spectateInputRelease=nil;return
    end
    if (not observed and not pending.allowExit) or now<pending.after then return end
    if self.imgui.ShowCursor or self.imgui.LockPlayer
        or api.sampIsChatInputActive and api.sampIsChatInputActive()
        or api.sampIsDialogActive and api.sampIsDialogActive()
        or api.sampIsScoreboardOpen and api.sampIsScoreboardOpen()
        or api.isPauseMenuActive and api.isPauseMenuActive()
        or api.isGameWindowForeground and not api.isGameWindowForeground() then return end
    self.spectateInputRelease=nil
    self:releaseNativeSpectateInput()
end

-- One bounded recovery per focus/mouse return; never continuously force capture.
function Runtime:notePointerFocus(msg)
    if msg==0x8 or msg==0x2A3 then -- WM_KILLFOCUS / WM_MOUSELEAVE
        self.pointerWasOutside=true;self.pointerReturn=nil
    elseif (msg==0x7 or msg==0x200) and self.pointerWasOutside then
        -- WM_MOUSEMOVE can still arrive while the pointer is outside (capture).
        if self.api.isGameWindowForeground and not self.api.isGameWindowForeground() then return end
        if self.pointerInside and self.pointerInside()==false then return end
        self.pointerWasOutside=false
        local now=self.api.getGameTimer()
        self.pointerReturn={after=now+250,expires=now+1500,identity=self.access.identity}
    end
end

function Runtime:reconcileSoftwareCursor()
    local g=self.imgui
    if not g or g.ShowCursor then return end
    -- Run after drawing: NewFrame resets the cursor shape even for passive HUDs.
    -- This affects only our ImGui context, not SA-MP dialogs or Windows capture.
    local io=g.GetIO()
    if io.MouseDrawCursor then
        io.MouseDrawCursor=false
    end
    if g.SetMouseCursor then g.SetMouseCursor(-1) end
end
function Runtime:reconcilePointerFocus()
    local a=self.api;local now=a.getGameTimer()
    local foreground=not a.isGameWindowForeground or a.isGameWindowForeground()
    if not foreground then self.pointerWasOutside=true;self.pointerReturn=nil
    elseif self.pointerForeground==false then self:notePointerFocus(0x7)end
    self.pointerForeground=foreground
    if foreground and self.pointerInside then
        local inside=self.pointerInside()
        if inside==false then self:notePointerFocus(0x2A3)
        elseif inside==true and self.pointerWasOutside then self:notePointerFocus(0x200)end
    end
    local pending=self.pointerReturn
    if not pending then return end
    if pending.identity~=self.access.identity or now>pending.expires or now<pending.after-250
        or self.reloading or a.sampGetGamestate()~=3 then self.pointerReturn=nil;return end
    if not foreground or now<pending.after then return end
    if self.imgui.ShowCursor or self.imgui.LockPlayer or self.placement or _G.cursorEnabled
        or a.sampIsChatInputActive and a.sampIsChatInputActive()
        or a.sampIsDialogActive and a.sampIsDialogActive()
        or a.sampIsScoreboardOpen and a.sampIsScoreboardOpen()
        or a.isPauseMenuActive and a.isPauseMenuActive()
        or self.serverControllable==false then
        self.pointerReturn=nil;return
    end
    -- MoonLoader showCursor and SA-MP's cursor mode are independent.
    -- A stale MoonLoader cursor can remain visible with native mode already 0.
    if not pending.moonloaderReleased then
        pending.moonloaderReleased=true
        if type(a.showCursor)=='function'then a.showCursor(false,false)end
    end
    if type(a.sampGetCursorMode)=='function' and type(a.sampSetCursorMode)=='function' and a.sampGetCursorMode()~=0 then
        self.pointerReturn=nil
        a.sampSetCursorMode(0)
    end
end

function Runtime:chatWindowOpen()
    local active=(_G.show_main_window and _G.show_main_window.v)==true
        or (self.overlayVisible and self.overlayVisible.v)==true or self.chatUiActive==true
    return active and not self.stopped and not self.reloading and not self.api.isPauseMenuActive()
end

function Runtime:guardInterfaceChat()
    if not self:chatWindowOpen()then return end
    if type(self.api.sampIsChatInputActive)=='function'and self.api.sampIsChatInputActive()
        and type(self.api.sampSetChatInputEnabled)=='function'then
        -- Some launchers poll keys directly, bypassing consumeWindowMessage.
        -- Close only native chat; never clear ImGui focus, key state or text buffers.
        self.api.sampSetChatInputEnabled(false)
    end
end

function Runtime:guardChatKey(msg,key)
    if msg==0x8 or msg==0x1C and key==0 then self.chatBlockedKeys=nil;return false end
    local down=msg==0x100 or msg==0x104
    local up=msg==0x101 or msg==0x105
    local blocked=false
    if (down or up)and (key==0x54 or key==0x75)then
        self.chatBlockedKeys=self.chatBlockedKeys or {}
        if down and self:chatWindowOpen()then self.chatBlockedKeys[key]=true;blocked=true
        elseif up then blocked=self.chatBlockedKeys[key]==true;self.chatBlockedKeys[key]=nil end
    elseif (msg==0x102 or msg==0x106)and self:chatWindowOpen()then
        blocked=key==0x54 or key==0x74 or key==0x415 or key==0x435 or key==0xC5 or key==0xE5
    end
    if blocked and self.api.consumeWindowMessage then self.api.consumeWindowMessage(true,false)end
    return blocked
end

function Runtime:syncGui()
    self.theme.apply(self.preferences.colors[self.preferences.data.main.color][2])
    if self.eventNotice then self.eventNotice:update(self.schedule,os.time(),self.api.getGameTimer(),not self.stopped and self.powered~=false and self.access:can(1) and self.api.sampGetGamestate()==3)end
    if self.updateNotice then self.updateNotice:update(self.api.getGameTimer(),not self.stopped and not self.reloading and not self.api.isPauseMenuActive() and self.api.isGameWindowForeground())end
    for _,id in ipairs({'airbreak','broom','invisible'}) do
        local m=self.modules[id]
        if m and m.enabled and m.bridge and m.bridge.isActive then
            self.toasts:observe(id,names[id],self:call(m,m.bridge.isActive))
        end
    end
    local core=self.modules.core
    if core and core.bridge and core.bridge.toggleStates then
        for name,value in pairs(core.bridge.toggleStates()) do self.toasts:observe(name,name,value) end
    end

    if self.stopped or self.syncingGui or not self.imgui then return end
    self.syncingGui=true
    local ok,err=pcall(function() self:applyGuiState();self:guardInterfaceChat();self:reconcileClosedChat();self:reconcileSpectateInput();self:reconcilePointerFocus() end)
    self.syncingGui=false
    if not ok and self.lastGuiError~=tostring(err) then
        self.lastGuiError=tostring(err)
        self.api.print('[X-Tools INPUT ERROR] '..self.lastGuiError)
    end
end

function Runtime:beginStartupBanner()
    local ok,err=pcall(function()
        self:legacyImgui('core')
        self.startupBanner=self:service('startup_banner.lua').new(function()return self.api.getGameTimer()end)
        self:syncGui()
    end)
    if not ok then self.api.print('[X-Tools startup banner] '..tostring(err)) end
end

function Runtime:applyGuiState()
    if self.reloading then
        self.chatUiActive=false
        self.imgui.Process=false;self.imgui.ShowCursor=false;self.imgui.LockPlayer=false;self.imgui.DisableInput=false
        return
    end
    if not self.imgui then return end
    local loading=self.startupBanner and self.startupBanner:update(self.access:level()==nil) or false
    if self.powered==false then
        local visible=_G.show_main_window and _G.show_main_window.v or false
        self.chatUiActive=false
        self.imgui.Process=visible or loading or self.toasts:visible() or self.eventNotice:visible() or self.updateNotice:visible();self.imgui.ShowCursor=visible;self.imgui.LockPlayer=visible;self.imgui.DisableInput=false;return
    end
    if self.placement then
        local session=self.placement
        if session.update then session.update()end
        if self.api.getGameTimer()-session.started>250 and self.api.isKeyJustPressed(13)then self:finishPlacement()end
    end
    local process, cursor, lock = self.placement~=nil, self.placement~=nil, self.placement~=nil
    local auxiliaryInput=self.placement~=nil
    local mainVisible=_G.show_main_window and _G.show_main_window.v
    local windowVisible=mainVisible or (self.overlayVisible and self.overlayVisible.v)
    local marker=self.markerSession
    if windowVisible or (marker and marker.target~=_G.sp_player_id) then
        _G.cursorEnabled=false;_G.markerHeld=false;self.markerSession=nil
    end
    local warp=self.modules.clickwarp
    if warp and warp.enabled and warp.bridge and warp.bridge.ownsMarkerInput
        and self:call(warp,warp.bridge.ownsMarkerInput) then
        _G.cursorEnabled=false;_G.markerHeld=false;self.markerSession=nil
    end
    if warp and warp.enabled and warp.bridge and warp.bridge.reconcilePointer then
        self:call(warp,warp.bridge.reconcilePointer,windowVisible==true)
    end
    for _, m in ipairs(self.order) do
        if (m.id == 'core' or m.id == 'menu') and m.enabled and m.gui.Process then
            process = true
            local wants=m.gui.ShowCursor~=false and (m.id~='core' or mainVisible)
            cursor=cursor or wants
            if m.id~='core' and wants then auxiliaryInput=true end
            lock=lock or (wants and m.gui.LockPlayer~=false)
        end
    end
    for _,m in ipairs(self.order) do
        if m.enabled and m.bridge and m.bridge.hudActive then
            local visible,wantsCursor,wantsLock=self:call(m,m.bridge.hudActive)
            auxiliaryInput=auxiliaryInput or (visible==true and wantsCursor==true)
            process=process or visible==true;cursor=cursor or (visible==true and wantsCursor==true)
            lock=lock or (visible==true and wantsCursor==true and wantsLock~=false)
        end
    end
    if mainVisible or (self.overlayVisible and self.overlayVisible.v) then process,cursor,lock=true,true,true end
    self.chatUiActive=auxiliaryInput
    if _G.cursorEnabled then process,cursor=true,true end
    self.imgui.Process = process or loading or self.toasts:visible() or self.eventNotice:visible() or self.updateNotice:visible()
    self.imgui.ShowCursor = cursor
    -- The backend owns cursor capture and player locking together. Never fight
    -- its cursor thread with a per-frame lock/unlock in the application.
    local menu=self.modules.menu
    local observed=menu and menu.enabled and menu.bridge and menu.bridge.observation and self:call(menu,menu.bridge.observation)
    -- Opening a settings window while spectating must not toggle player control:
    -- MoonLoader's player lock can alter the spectator camera permanently.
    self.imgui.LockPlayer = process and lock and not observed
    -- Input remains available to interactive windows; passive HUDs use NoInputs.
    self.imgui.DisableInput = false
end

function Runtime:legacyImgui(id)
    local m = self:component(id)
    if m.guiProxy then return m.guiProxy end
    if not self.imgui then
        self.imgui = self.api.require('imgui')
        local checkbox=self.imgui.Checkbox
        self.imgui.Checkbox=function(label,value,notificationLabel)
            local previous=value.v
            local changed=checkbox(label,value)
            if previous~=value.v then
                local caption=notificationLabel or label
                if tostring(caption):gsub('##.*',''):match('^%s*$')then caption='Настройка'end
                self.toasts:push(self.preferences:mask(caption),value.v)
            end
            return changed
        end
        self:service('numeric_input.lua').install(self.imgui)
        for _, key in ipairs({'OnInitialize', 'BeforeDrawFrame', 'OnDrawFrame'}) do
            self.imgui[key] = function(...)
                if key=='BeforeDrawFrame' or key=='OnDrawFrame'then self:guardInterfaceChat()end
                if key == 'OnInitialize' then self.guiInitialized = true end
                if key == 'BeforeDrawFrame' then
                    self:service('art.lua').beginFrame()
                    self.typography.preference=self.preferences.data.main.font
                    self.typography.scale=self.preferences.data.main.scale or 1
                    self.typography:load(self.imgui)
                    if not self.avatar then self.avatar=self:service('avatar.lua').new(self.imgui,self.base,_G) end
                    self.avatar:update()
                    if self.typography.failed and not self.fontErrorReported then
                        self.fontErrorReported=true
                        self:message('Не удалось загрузить шрифт интерфейса: '..self.typography.failed)
                    end
                end
                for _, owner in ipairs(self.order) do
                    if (owner.id == 'core' or owner.id == 'menu' and self.powered~=false and not self.editingAllHud) and
                        (key == 'BeforeDrawFrame' or key == 'OnInitialize' or owner.gui.Process
                            or owner.id=='core' and self.overlayVisible and self.overlayVisible.v) then
                        self:call(owner, owner.gui[key], ...)
                    end
                end
                if key=='OnDrawFrame' then
                    for _,owner in ipairs(self.order) do
                        if self.powered~=false and owner.enabled and owner.bridge and owner.bridge.drawHud and (self.access:displayLevel()~='S1' or self:featureAllowed(owner.id)) and (not self.editingAllHud or owner.id=='display_layout') then
                            local colors,vars=self.theme.push(self.imgui,1)
                            self:call(owner,owner.bridge.drawHud)
                            self.theme.pop(self.imgui,colors,vars)
                        end
                    end
                end
                if key=='OnDrawFrame' then
                    if self.startupBanner then self.startupBanner:draw(self) end
                    self.toasts:draw(self)
                    if not self.api.isPauseMenuActive() and self.api.isGameWindowForeground()then
                        self.eventNotice:draw(self)
                        self.updateNotice:draw(self)
                    end
                end
                self:syncGui()
                if key=='OnDrawFrame' then self:reconcileSoftwareCursor() end
            end
        end
    end
    local private = {Process = true, ShowCursor = true, DisableInput = true, LockPlayer = true, OnInitialize = true,
        BeforeDrawFrame = true, OnDrawFrame = true}
    -- Explicit field scopes keep native input state separate across embedded
    -- modules and repeated rows, including widgets with hidden captions.
    local inputScope=0
    for i=1,#id do inputScope=(inputScope*31+id:byte(i))%2147483647 end
    -- ## hides a suffix but hashes the WHOLE label; only ### overrides identity.
    local function inputId(label)return label:match('###(.*)$') or label end
    local function inputWidget(key,label,...)
        local g=self.imgui
        -- Integer scope avoids MoonImGui's overloaded string/pointer PushID.
        -- The caller's ID stack still separates repeated rows.
        g.PushID(inputScope)
        local result=pack(pcall(g[key],label,...))
        if result[1] and (key=='InputText' or key=='InputTextMultiline')then pcall(self.noteTextInput,self,id,key)end
        g.PopID()
        if not result[1]then error(result[2],0)end
        return unpack(result,2,result.n)
    end
    m.guiProxy = setmetatable({}, {
        __index = function(_, key)
            if key=='InputInt' or key=='InputFloat' or key=='SliderInt' or key=='SliderFloat' or key=='Combo' then return function(label,...)
                local text=label:gsub('##.*','')
                if self.drawingWorkspace and text~='' then
                    local g=self.imgui;local scale=self.preferences.data.main.scale or 1
                    local available=g.GetContentRegionAvailWidth()
                    local itemWidth=g.CalcItemWidth and g.CalcItemWidth() or 300*scale
                    if type(itemWidth)~='number' then itemWidth=300*scale end
                    if itemWidth+g.CalcTextSize(text).x+16*scale>available then
                        g.TextWrapped(self.preferences:mask(text))
                        g.PushItemWidth(math.max(1,math.min(available,360*scale)))
                        local result=inputWidget(key,'###xt_field_'..inputId(label),...);g.PopItemWidth();return result
                    end
                end
                return inputWidget(key,self.preferences:mask(label:gsub('##.*',''))..'###xt_field_'..inputId(label),...)
            end end
            if key=='Checkbox' then return function(label,value,notificationLabel)
                label=self.preferences:mask(label)
                if self.drawingWorkspace then
                    return self:service('ui_components.lua').checkbox(self.imgui,label,value,self.preferences.data.main.scale,nil,notificationLabel or label)
                end
                return self.imgui.Checkbox(label,value,notificationLabel)
            end end
            if key=='GetWindowDrawList' then return function()
                local draw=self.imgui.GetWindowDrawList()
                return setmetatable({}, {__index=function(_,name)
                    local method=draw[name]
                    if type(method)~='function' then return method end
                    return function(_, ...)
                        local args=pack(...)
                        if name=='AddText' then for i=1,args.n do if type(args[i])=='string' then args[i]=self.preferences:mask(args[i]) end end end
                        return method(draw,unpack(args,1,args.n))
                    end
                end})
            end end
            if key=='Button' then return function(label,size,...)
                label=self.preferences:mask(label)
                if self.drawingWorkspace then
                    local scale=self.preferences.data.main.scale or 1
                    local available=math.max(40,self.imgui.GetContentRegionAvailWidth())
                    local width=size and size.x and size.x>0 and math.min(available,size.x) or available
                    local visible,id=label:match('^(.-)(##.*)$')
                    visible=visible or label;id=id or '##'..label
                    local wrapped=self:service('ui_components.lua').wrap(self.imgui,visible,math.max(1,width-20*scale))
                    if wrapped~=visible then label=wrapped..'###'..label end
                    if size then size=self.imgui.ImVec2(size.x>0 and math.min(available,size.x) or size.x,math.max(32*scale,size.y,self.imgui.CalcTextSize(wrapped).y+16*scale)) end
                end
                -- MoonImGui's native binding expects ImVec2 when argument 2 is
                -- present. Omitted dimensions must not become an explicit nil.
                if size==nil then return self.imgui.Button(label) end
                return self.imgui.Button(label,size,...)
            end end
            if key=='SmallButton' or key=='Selectable' then return function(label,...) return self.imgui[key](self.preferences:mask(label),...) end end
            if key=='InputText' or key=='InputTextMultiline' then return function(label,value,...)
                local args=pack(...)
                if self.preferences.data.main.streamer and value and type(value.v)=='string' and value.v:find('%d+%.%d+%.%d+%.%d+') then
                    local position=key=='InputText' and 1 or 2
                    args[position]=self.api.require('bit').bor(args[position]or 0,self.imgui.InputTextFlags.Password)
                    args.n=math.max(args.n,position)
                end
                if self.drawingWorkspace and key=='InputText' and label:gsub('##.*','')~='' then
                    local g=self.imgui;local scale=self.preferences.data.main.scale or 1
                    local text=label:gsub('##.*','');local width=g.GetContentRegionAvailWidth()
                    local itemWidth=g.CalcItemWidth and g.CalcItemWidth() or 300*scale
                    if type(itemWidth)~='number' then itemWidth=300*scale end
                    if itemWidth+g.CalcTextSize(text).x+16*scale>width then
                        g.TextWrapped(self.preferences:mask(text));g.PushItemWidth(math.max(1,math.min(width,360*scale)))
                        local result=inputWidget(key,'###xt_field_'..inputId(label),value,unpack(args,1,args.n));g.PopItemWidth();return result
                    end
                end
                return inputWidget(key,self.preferences:mask(label:gsub('##.*',''))..'###xt_field_'..inputId(label),value,unpack(args,1,args.n))
            end end
            if key=='Text' or key=='TextUnformatted' or key=='TextWrapped' or key=='TextDisabled' or key=='SetTooltip' then return function(text,...) return self.imgui[key](self.preferences:mask(text),...) end end
            if key=='TextColored' then return function(color,text,...) return self.imgui.TextColored(color,self.preferences:mask(text),...) end end
            if key=='Separator' then return function() return self:service('layout.lua').separator(self.imgui) end end
            if id == 'core' and self.embeddedCore then
                if key == 'SetNextWindowPos' or key == 'SetNextWindowSize' or key == 'SetWindowSize' then return function() end end
                if key == 'Begin' then return function() self.imgui.BeginGroup(); return true end end
                if key == 'End' then return self.imgui.EndGroup end
                if key == 'BeginChild' then return function(name, ...)
                    m.childStack = m.childStack or {}
                    local flat = name == 'item view'
                    m.childStack[#m.childStack + 1] = flat
                    if flat then self.imgui.BeginGroup(); return true end
                    return self.imgui.BeginChild(name, ...)
                end end
                if key == 'EndChild' then return function()
                    if table.remove(m.childStack) then self.imgui.EndGroup() else self.imgui.EndChild() end
                end end
            end
            if private[key] then return m.gui[key] end
            return self.imgui[key]
        end,
        __newindex = function(_, key, value)
            if private[key] then
                m.gui[key] = value
                if key == 'OnInitialize' and self.guiInitialized then self:call(m, value) end
                -- Reconcile on the runtime tick/frame, never inside a property setter.
            else self.imgui[key] = value end
        end
    })
    return m.guiProxy
end

function Runtime:register(m, name, fn)
    name = name:lower()
    local existing=self.commands[name]
    if existing and existing.owner==m then
        return existing.chatRegistered==true
    end
    assert(not self.commands[name], 'Duplicate command /' .. name)
    local callback = function(...)
        if not self:commandAllowed('/'..name) then return false end
        if name~='reconn' and not self:featureAllowed(m.id) then self:message('Раздел выключен или недоступен на вашем уровне администратора.');return false end
        return self:call(m, fn, ...)
    end
    local command = {owner = m, callback = callback, chatRegistered = false}
    self.commands[name] = command
    -- /tr belongs to the integrated road module, including after a reload.
    if m.id=='road' and name=='tr' and self.api.sampIsChatCommandDefined
        and self.api.sampIsChatCommandDefined(name) and self.api.sampUnregisterChatCommand then
        self.api.sampUnregisterChatCommand(name)
    end
    if self.api.sampIsChatCommandDefined then
        if self.api.sampIsChatCommandDefined(name) then
            command.conflict = true
            self:message('/' .. name .. ' уже занята другим обработчиком.\n«' .. (names[m.id] or m.id) .. '» доступен через меню X-Tools.\nСуществующая команда сохранена.')
            return false
        end
    end
    local result = self.api.sampRegisterChatCommand(name, callback)
    assert(result ~= false, 'Cannot register /' .. name)
    command.chatRegistered = true
    return result
end

function Runtime:invoke(name, args)
    local command = self.commands[name]
    if command and command.owner.enabled then return command.callback(args or '') end
    self:message('/' .. name .. ': функция не загружена. Состояние: /atmodules; справка: /athelp.')
end

-- Kept as a compatibility entry point; routine command tracing is disabled.
function Runtime:traceInspection(owner,text) end

function Runtime:canServerCommand(text)
    local policy=self:service('permissions.lua')
    if self.access:displayLevel()=='S1' then return false end
    local special=policy.specialCommand(self.access:displayLevel(),text)
    if special~=nil then return special end
    local minimum=policy.command(text)
    return minimum==nil or minimum==0 or self.access:can(minimum)
end

function Runtime:commandAllowed(text,serverCommand)
    local policy=self:service('permissions.lua')
    local name=tostring(text or ''):match('^%s*/([%w_]+)')
    if self.access:displayLevel()=='S1' then
        if not serverCommand and name and policy.s1Commands[name:lower()] then return true end
        if serverCommand or name and policy.commands[name:lower()] then
            self:message('S1: эта админ-функция недоступна.');return false
        end
        return true
    end
    local localHelper=name and (self.commands[name:lower()] or self.coreCommands and self.coreCommands[name:lower()])
    if serverCommand or not localHelper then
        local special=policy.specialCommand(self.access:displayLevel(),text)
        if special~=nil then
            if not special then self:message('Команда /'..name..' не входит в перечень доступа '..self.access:displayLevel()..'.') end
            return special
        end
    end
    local minimum=policy.command(text)
    if minimum==nil or minimum==0 then return true end
    return self.access:require(minimum,function(reason)self:message(reason)end)
end

function Runtime:prepareChatCommand(command)
    local api=copy(self.api)
    local u8=self.api.require('encoding').UTF8
    api.encode=function(text)return u8:decode(text)end
    return self:service('chat_wrap.lua').split(command,_G.auto_perenos==true,api)
end

function Runtime:wrapChat(owner,apiName,command)
    local parts,target=self:prepareChatCommand(command)
    if not parts then self:message(target);return true end
    if #parts<=1 then return false end
    local revision,identity=self.access:revision(),self.access.identity
    local module=self.modules[owner]
    self.api.lua_thread.create(function()
        for index,part in ipairs(parts) do
            if index>1 then self.api.wait(500)end
            local found,me=self.api.sampGetPlayerIdByCharHandle(self.api.PLAYER_PED)
            if self.stopped or not module or not module.enabled or self.powered==false
                or self.access:revision()~=revision or self.access.identity~=identity
                or self.api.sampGetGamestate()~=3 or not self:featureAllowed(owner)
                or not (found and target.id==me or self.api.sampIsPlayerConnected(target.id))
                or self.api.sampGetPlayerNickname(target.id)~=target.nickname then return end
            if self:send(owner,apiName,part)==false then return end
        end
    end)
    return true
end

function Runtime:send(owner, apiName, ...)
    if self.editingAllHud then return false end
    if self:checkSession()==false then return false end
    local allowed,reason=self.access:require(1)
    if not allowed then
        local clock=self.api.os.clock()
        if not self.accessNoticeAt or clock-self.accessNoticeAt>3 then self.accessNoticeAt=clock; self:message(reason) end
        return false
    end
    if not self:featureAllowed(owner) then return false end
    local arguments=pack(...)
    if type(arguments[1])=='string' then
        local text=tostring(self.api.require('encoding').UTF8(arguments[1]))
        if self:blockProtectedPunishment(text) then return false end
        if not self:commandAllowed(text,true) then return false end
        if self:wrapChat(owner,apiName,arguments[1]) then return true end
        if self.offban:enqueue(owner,apiName,text) then return true end
        self.offban:track(text)
    end
    self:traceInspection(owner,arguments[1])
    local previous=self.outboundOwner
    self.outboundOwner=owner
    local result=pack(pcall(self.api[apiName],...))
    self.outboundOwner=previous
    if not result[1] then error(result[2],0) end
    return unpack(result,2,result.n)
end

function Runtime:serverSupports()
    local ok,address,port=pcall(self.api.sampGetCurrentServerAddress)
    if not ok then return false end
    return self:service('server_policy.lua').allows(address,port)
end

function Runtime:fileApi()
    if self.storageIo then return self.storageIo end
    local api=copy(self.api.io)
    api.open=function(path,mode) return self.storage:open(path,mode) end
    api.close=function(file) return file:close() end
    api.lines=function(path)
        local file=assert(api.open(path,'r'))
        return function()
            local line=file:read('*l')
            if line==nil then file:close() end
            return line
        end
    end
    self.storageIo=api
    return api
end

function Runtime:coreStorage()
    if self.corePaths then return self.corePaths end
    local root=self.host.path and self.host.path:match('^(.*)[/\\]') or self.api.getWorkingDirectory()
    local specs={
        config={'settings','core.ini','config/AdminTools/config.ini'},
        stats={'data','admin-statistics.ini','config/AdminTools/stats.ini'},
        events={'settings','events.json','AdminTools/events.json'},
        chat={'logs','chat.txt','AdminTools/logs/chat_log.txt'},
        find={'logs','organization-online.html','AdminTools/logs/find_log.html'},
        kills={'logs','kills.txt','AdminTools/logs/killList_log.txt'},
        captureDeaths={'data','capture/death-nicknames.txt','AdminTools/data/capture_death_nicknames_cmd.txt'},
    }
    local paths={}
    for name,spec in pairs(specs) do paths[name]=self.storage:path(spec[1],spec[2],{root..'/'..spec[3]}) end
    self.corePaths=paths
    return paths
end

function Runtime:environment(m, path)
    local env = setmetatable({}, {__index = self.api})
    m.env, m.cancelled = env, {}
    env._G = env
    env.io = self:fileApi()
    for _, name in ipairs({'string', 'table', 'math', 'os'}) do env[name] = copy(self.api[name]) end
    env.os.remove=function(path) return self.storage:remove(path) end
    env.os.rename=function(source,target) return self.storage:rename(source,target) end
    env.os.date=function(...)return self.clock:date(...)end
    env.os.time=function(...)return self.clock:time(...)end
    env.integration = {
        base = self.base,
        layout = self:service('layout.lua').new(self:legacyImgui(m.id)),
        version = self.host.version,
        disable = function() self:stop(m) end,
        service = function(name) return self:service(name) end,
        workerCode = function(name) return string.dump(assert(self:source(name))) end,
        storage = self.storage,
        preferences=self.preferences, keys=self.keys,
        claimFlight=function()
            for _,id in ipairs({'movement','airbreak','broom'})do
                local other=self.modules[id]
                if other and other~=m and other.bridge and other.bridge.stop then self:call(other,other.bridge.stop)end
            end
        end,
        flightActive=function()
            for _,id in ipairs({'airbreak','broom'})do
                local flight=self.modules[id]
                if flight and flight.bridge.isActive and flight.bridge.isActive()then return true end
            end
            return false
        end,
        familyRegistryBusy=function()
            local r=self.modules.family_registry
            return r and r.bridge and r.bridge.busy and r.bridge.busy()or false
        end,
        temporaryFamilyState=function()
            local r=self.modules.tempfamily
            return r and r.bridge and r.bridge.familyState and r.bridge.familyState()
        end,
        familyBones=function(ped)
            local r=self.modules.capture
            return r and r.bridge and r.bridge.familyBones and r.bridge.familyBones(ped)
        end,
        familyHighlight=function(nick)
            local r=self.modules.family_registry
            if r and r.enabled and self:featureAllowed('family_registry') and r.bridge.hudActive()then return r.bridge.memberColor(nick)end
        end,
        generalHighlight=function()
            local r=self.modules.capture
            if r and r.enabled and self:featureAllowed('core') and r.bridge.generalHighlight then return r.bridge.generalHighlight()end
            return false,0
        end,
        featureAllowed=function(id) return self:featureAllowed(id or m.id) end,
        nametagColor=function(color)
            local m=self.modules.mask_names
            if m and m.enabled and self:featureAllowed('mask_names') and m.bridge.nametagColor then
                return self:call(m,m.bridge.nametagColor,color) or color
            end
            return color
        end,
        originalPlayerColor=function(id,color)
            local mask=self.modules.mask_names
            if mask and mask.enabled and mask.bridge.originalPlayerColor then return self:call(mask,mask.bridge.originalPlayerColor,id,color) or color end
            return color
        end,
        isMaskColor=function(color)
            local mask=self.modules.mask_names
            return color~=nil and mask and mask.enabled and mask.bridge.isMaskColor and self:call(mask,mask.bridge.isMaskColor,color) or false
        end,
        maskColor=function()
            local mask=self.modules.mask_names
            return mask and mask.enabled and mask.bridge.maskColor and self:call(mask,mask.bridge.maskColor) or 0xFF222222
        end,
        wallhackActive=function() return self.wallhackActive==true end,
        matchPunishment=function(command,text,target) local a=self.modules.aegis;return a and a.bridge.matchPunishment and a.bridge.matchPunishment(command,text,target) end,
        sendBan=function(command,requester)
            local previous=self.offban.requester;self.offban.requester=requester
            local ok,result=pcall(self.send,self,m.id,'sampSendChat',self.api.require('encoding').UTF8:decode(command))
            self.offban.requester=previous
            if not ok then error(result,0) end
            return result
        end,
        guardResult=function(command) return self.offban.results[command] end,
        cancelPending=function() self.offban:cancel(m.id) end,
        access = self.access,
        commandMinimum = function(text) return self:service('permissions.lua').command(text) or 1 end,
        commandAllowed = function(text) return self:commandAllowed(text) end,
        prepareChatCommand = function(text) return self:prepareChatCommand(text) end,
        canServerCommand = function(text) return self:canServerCommand(text) end,
        serverSupports = function(feature) return self:serverSupports(feature) end,
        checkUpdates = function(manual) return self:checkUpdates(manual) end,
        root = self.host.path and self.host.path:match('^(.*)[/\\]') or self.api.getWorkingDirectory(),
        fontFace = function(size,bold) return self.typography:get(size,bold) end,
        maskText = function(text) return self.preferences:mask(text) end,
        palette = self.theme.palette,
        color = function(hex) return self.theme.color(self:legacyImgui(m.id), hex) end,
        refreshInput = function() self:syncGui() end,
        releaseSpectateInput = function() self:requestSpectateInputRelease() end,
        releaseTransitionInput = function()
            self:requestSpectateInputRelease()
            self.spectateInputRelease.allowExit=true
        end,
        windowOpen = function() return _G.show_main_window and _G.show_main_window.v or false end,
        beginPlacement = function(finish,update) self:beginPlacement(finish,update) end,
        finishPlacement = function() self:finishPlacement() end,
        closeWindow = function() if _G.show_main_window then _G.show_main_window.v = false end end,
        invoke = function(name, args)
            local previous=self.outboundOwner;self.outboundOwner=m.id
            local result=pack(pcall(self.invoke,self,name,args))
            self.outboundOwner=previous
            if not result[1] then error(result[2],0) end
            return unpack(result,2,result.n)
        end,
        squareWarningsEnabled = function()
            local registry=self.modules.family_registry
            return registry and registry.enabled and registry.bridge and self:call(registry,registry.bridge.squareWarningsEnabled)==true
        end,
        squareWarning = function(text,id)
            local registry=self.modules.family_registry
            if registry and registry.enabled and registry.bridge then self:call(registry,registry.bridge.squareWarning,text,id)end
        end,
        message = function(text) self:message(text) end,
        notifyToggle=function(label,value) self.toasts:push(self.preferences:mask(label),value) end,
        openFamilyDiscord = function()self.familyPage=3;self:open('familia')end,
        open = function(page) self:open(page) end,
        openTeleportation = function() self:open('teleport') end,
        openSettings = function(category) self:openSettings(category) end,
        openHelp = function(category) self:openHelp(category) end,
        openQueue = function() self:open('queue') end,
        commandOwner = function() return self.outboundOwner end,
        observation = function()
            local menu=self.modules.menu
            return menu and menu.bridge.observation and self:call(menu,menu.bridge.observation) or nil
        end,
        hideServerMenu=function(id)
            if not self.api.raknetEmulRpcReceiveBitStream then return true end
            local bs=self.api.raknetNewBitStream()
            self.hidingServerMenu=true
            local ok=pcall(function()
                self.api.raknetBitStreamWriteInt8(bs,id)
                self.api.raknetEmulRpcReceiveBitStream(self.api.require('samp.raknet').RPC.HIDEMENU,bs)
            end)
            self.hidingServerMenu=false
            self.api.raknetDeleteBitStream(bs)
            return ok
        end,
        serverMenuDefinition=function(id)
            if self.menuCacheIdentity~=self.access.identity then self.serverMenuDefinitions={} end
            local cached=self.serverMenuDefinitions and self.serverMenuDefinitions[tonumber(id)]
            if cached then return cached end
            self.readNativeMenu=self.readNativeMenu or self:service('observation_native.lua').new(self.api)
            return self.readNativeMenu(id)
        end,
        styledChatHit=function(x,y)
            local chat=self.modules.chat_appearance
            if chat and chat.enabled and chat.bridge.chatHit then return chat.bridge.chatHit(x,y)end
            return false
        end,
        serverZones=function()return self.zoneWallModel end,
        layoutEditing=function()return self.editingAllHud==true end,
        setLayoutEditing=function(value)self.editingAllHud=value end,
        collectLayoutItems=function()
            local rows={}
            for _,owner in ipairs(self.order)do
                if owner.bridge and owner.bridge.layoutItems then
                    for _,item in ipairs(self:call(owner,owner.bridge.layoutItems) or {})do rows[#rows+1]=item end
                end
            end
            if self.pingLayoutItem then rows[#rows+1]=self.pingLayoutItem()end
            return rows
        end,
        drawHitHistory=function() local m=self.modules.observer_extras;if m then return self:call(m,m.bridge.drawHitHistory)end end,
        drawSkySettings=function()local m=self.modules.beautifulsky;if m then return self:call(m,m.bridge.drawSettings)end end,
        queueFamilyPunishment=function(plan)
            local family=self.modules.familia
            if not family or not family.enabled or not self:featureAllowed('familia')then return false end
            return self:call(family,family.bridge.queueSafePunishment,plan)==true
        end,
        familyFeaturesEnabled=function()return self:featureAllowed('familia')end,
        answerFamily = function(recipient,subject,guard,delay)
            local family=self.modules.familia
            if not family or not family.enabled or not self:featureAllowed('familia') then return false end
            return self:call(family,family.bridge.answerFamily,recipient,subject,guard,delay)==true
        end,
        queryBusy = function(kind)
            for _, owner in ipairs(self.order) do
                if owner~=m and owner.enabled and owner.bridge and owner.bridge.queryPending
                    and self:call(owner,owner.bridge.queryPending,kind) then return true end
            end
            return false
        end,
        protectedLists = function(reload)
            local adm=self.modules.adm
            if adm and adm.enabled and adm.bridge and adm.bridge.protectedLists then
                return self:call(adm,adm.bridge.protectedLists,reload)
            end
        end,
        isKnownAdmin = function(nickname)
            local adm = self.modules.adm
            if adm and adm.enabled and adm.bridge and adm.bridge.isKnownAdmin then
                return self:call(adm, adm.bridge.isKnownAdmin, nickname)
            end
        end,
        adminLevel = function()
            return self.access:level()
        end
    }
    m.bridge = env.integration
    env.require = function(name)
        if name == 'samp.events' or name == 'lib.samp.events' then return self:events(m.id) end
        if name == 'imgui' then return self:legacyImgui(m.id) end
        if name == 'admintools.ui' then
            local factory = self:service('ui_compat.lua')
            return factory(self:legacyImgui(m.id), self.api.require('ffi'))
        end
        return self.api.require(name)
    end
    env.sampAddChatMessage=function(text,color) return self:chat(text,color) end
    env.sampIsChatVisible=function()return self:isChatVisible()end
    env.renderFontDrawText=function(...) return self.nativeFonts:draw(...) end
    env.renderGetFontDrawTextLength=function(...) return self.nativeFonts:width(...) end
    env.renderGetFontDrawHeight=function(...) return self.nativeFonts:height(...) end
    env.sampRegisterChatCommand = function(name, fn) return self:register(m, name, fn) end
    for _, name in ipairs({'sampSendChat','sampProcessChatInput'}) do
        env[name] = function(...) return self:send(m.id,name,...) end
    end
    env.wait = function(ms)
        if self.performance then self.performance:pause()end
        if ms == -1 then
            -- Standalone scripts freeze their main thread here. Integrated
            -- mains are child threads, where MoonLoader rejects wait(-1).
            -- Keep callbacks alive without passing that sentinel to MoonLoader.
            while m.enabled do
                self.api.wait(1000)
                if m.enabled then self:checkSession() end
            end
            error(m.cancelled, 0)
        end
        self.api.wait(ms)
        while (self.powered==false or self.access:displayLevel()=='S1' and not self:service('permissions.lua').s1Modules[m.id]) and m.enabled and not self.stopped do self.api.wait(100)end
        if not m.enabled then error(m.cancelled, 0) end
        self:checkSession()
        if self.performance then self.performance:resume(m.id)end
    end
    env.lua_thread = setmetatable({create = function(fn, ...)
        return self.api.lua_thread.create(function(...) return self:call(m, fn, ...) end, ...)
    end}, {__index = self.api.lua_thread})
    env.renderCreateFont = function(...)
        local font = self.nativeFonts:create(...)
        if font then m.fonts[font] = true end
        return font
    end
    env.renderReleaseFont = function(font)
        m.fonts[font] = nil
        return self.nativeFonts:release(font)
    end
    -- Callbacks may arrive after a download-owning module has stopped.
    env.downloadUrlToFile = function(url, target, callback, ...)
        return self.api.downloadUrlToFile(url, target, function(...)
            return self:call(m, callback, ...)
        end, ...)
    end
    return env
end

function Runtime:load(id, filename)
    local m = self:component(id)
    if m.loaded then return m end
    m.loaded=true
    local path = self.base .. '/modules/' .. filename
    local chunk, err = self:source('modules/' .. filename)
    if not chunk then self:fail(m, err); return end
    setfenv(chunk, self:environment(m, path))
    self:call(m, chunk)
    if m.enabled and m.bridge.start then m.env.lua_thread.create(m.bridge.start) end
end

function Runtime:start()
    if self.started then return end
    if self:checkSession()==false then return end
    self.started = true
    self.gameState = self.api.sampGetGamestate()
    -- Core callbacks are already installed. No component can overwrite them.
    self:load('familia', 'familia.lua')
    self:load('adm', 'adm.lua')
    self:load('aegis', 'aegis.lua')
    self:load('gang', 'gang.lua')
    self:load('joinquit', 'joinquit.lua')
    self:load('killids', 'killids.lua')
    self:load('hospital', 'hospital.lua')
    self:load('menu', 'menu.lua')
    self:load('road', 'road.lua')
    self:load('movement','movement.lua')
    self:load('airbreak','airbreak.lua')
    self:load('broom','broom.lua')
    self:load('mask_names','mask_names.lua')
    self:load('family_mask_warning','family_mask_warning.lua')
    self:load('family_weapon_warning','family_weapon_warning.lua')
    self:load('rvanka_warning','rvanka_warning.lua')
    self:load('zone_wall','zone_wall.lua')
    self:load('death_effect','death_effect.lua')
    self:load('casual','casual.lua')
    self:load('fisheye','fisheye.lua')
    self:load('fogdist','fogdist.lua')
    self:load('beautifulsky','beautifulsky.lua')
    self:load('observer_extras','observer_extras.lua')
    self:load('adm_tab','glass_scoreboard.lua')
    self:load('speed_boost','speed_boost.lua')
    self:load('clickwarp','clickwarp.lua')
    self:load('tpm','tpm.lua')
    self:load('adminzone','adminzone.lua')
    self:register(self.modules.adminzone,'az',function()return self.modules.adminzone.bridge.enter()end)
    self:load('reminders','reminders.lua')
    self:load('rephelp','rephelp.lua')
    self:load('correction','correction.lua')
    self:load('chat_copy','chat_copy.lua')
    self:load('chat_appearance','chat_appearance.lua')
    self:load('punishment_log','punishment_log.lua')
    self:load('invisible','invisible.lua')
    self:load('radar_restore','radar_restore.lua')
    self:load('autostart','autostart.lua')
    self:load('autoreply','autoreply.lua')
    self:load('nakaz','nakaz.lua')
    self:load('report_assist','report_assist.lua')
    self:load('display_layout','display_layout.lua')
    self:load('lego','lego.lua')
    self:load('tempfamily','tempfamily.lua')
    self:load('family_registry','family_registry.lua')
    self:load('online', 'online.lua')
    self:load('environment', 'environment.lua')
    self:load('weapon_skills','weapon_skills.lua')
    self:load('queue', 'queue.lua')
    self:load('lookup', 'lookup.lua')
    self:load('capture', 'capture.lua')
    self:load('bullet', 'bullet.lua')
    self:load('stopsbiv', 'stopsbiv.lua')
    self:register(self:component('integration'), 'atmodules', function() self:status() end)
    self:register(self:component('integration'), 'atinput', function() self:traceInput() end)
    self:register(self:component('integration'), 'xtfps', function(args) self:performanceCommand(args) end)
    self:register(self:component('integration'), 'athelp', function() self:openHelp('start') end)
    self:register(self:component('integration'), 'casualupdate', function() self:checkUpdates(true) end)
    self:register(self:component('integration'), 'update', function() self.updateCommandPending=true end)
    self.updateLoginPending=true
    self.api.lua_thread.create(function()
        while not self.stopped do
            self.api.wait(0)
            if self.performance then self.performance:tick(self.powered)end
            self:processUpdateCommand()
            if self:checkSession()~=false then
                if self.powered~=false then
                    self.offban:update()
                    if self.automaticSkin then self.automaticSkin:update() end
                    if self.automaticLeader then self.automaticLeader:update() end
                end
                for _,m in ipairs(self.order) do if m.bridge and m.id~='lookup' and self:featureAllowed(m.id) then self:call(m,m.bridge.update) end end
                self:syncGui()
            end
        end
    end)
end

function Runtime:performanceCommand(args)
    if not self.performance then
        self.performance=self:service('performance.lua').new(self.api,self.storage,
            function(text)self:message(text)end,self.release.version or self.host.version or 'development')
    end
    local loaded={}
    for _,m in ipairs(self.order)do if m.enabled then loaded[#loaded+1]=m.id end end
    self.performance:command(args,table.concat(loaded,', '))
end

function Runtime:status()
    for _, m in ipairs(self.order) do
        if m.id ~= 'core' and m.id ~= 'integration' then
            self:message((names[m.id] or m.id) .. ': ' .. (m.enabled and 'загружено' or 'не загружено; подробности в moonloader.log'))
        end
    end
    self:message('Галочки включения функций — в настройках. Команды и помощь: /athelp.')
end

function Runtime:openHelp(category)
    self.helpSection=self.guide.section(category or 'start').id
    self.helpPage=1
    self.helpIntro=nil
    if self.helpSearch then self.helpSearch.v='' end
    self.helpResetScroll=true
    self:open('commands')
end

function Runtime:drawHelp() self.guide.draw(self) end

-- Chat callbacks only enqueue. Start updater work after the native callback returns.
function Runtime:processUpdateCommand()
    if not self.updateCommandPending then return end
    self.updateCommandPending=false
    if self.stopped then return end
    self:call(self:component('integration'),function() self.updates:update() end)
end

function Runtime:checkUpdates(manual)
    local status = self.updates:check(manual)
    if manual~=false then self.settingsPage='system'; self:open('settings') end
    return status
end

function Runtime:drawSystemSettings()
    local g=self.imgui
    local form=self:service('layout.lua').new(g)
    local columns=form.begin('system_summary',780)
    g.Text('Права администратора')
    local level=self.access:level()
    g.TextWrapped(level~=nil and ('Уровень в текущей сессии: '..level) or 'Уровень пока не подтверждён сервером. Ограниченные действия недоступны; меню и настройки работают.')
    
    form.next(columns)
    g.Text('Хранение данных')
    g.TextWrapped('Настройки, данные, кэш и журналы находятся в одном каталоге:')
    g.TextWrapped(self.api.require('encoding').UTF8(self.storage.root))
    
    if #self.storage.errors>0 then
        g.TextWrapped('Есть ошибки хранения данных: '..#self.storage.errors..'. Подробности — в moonloader.log. Проверьте доступ к каталогу и свободное место.')
    end
    form.finish(columns)
    g.Spacing(); g.Separator(); g.Spacing()
    self:service('settings_transfer_ui.lua').draw(self)
    g.Spacing(); g.Separator(); g.Spacing()
    local conflicts={}
    for name,command in pairs(self.commands) do
        if command.conflict then conflicts[#conflicts+1]='/'..name end
    end
    if #conflicts>0 then
        table.sort(conflicts)
        g.Text('Занятые команды')
        g.TextWrapped(table.concat(conflicts,', '))
        g.TextWrapped('Эти команды уже заняты другими обработчиками. Встроенные функции доступны через меню X-Tools.')
        g.Spacing(); g.Separator(); g.Spacing()
    end
    self.updates:draw(g,self)
end

function Runtime:nativeCallback(name, ...)
    if name=='onD3DDeviceReset' then self:service('art.lua').refreshAll() end
    if self.stopped then return end
    if name=='onD3DPresent' or name=='onWindowMessage'then self:guardInterfaceChat()end
    if self.performance and self.performance.active then
        if name=='onD3DPresent' then
            self.performance:frame(self.api.sampGetGamestate()==3 and self.api.isGameWindowForeground()and not self.api.isPauseMenuActive())
        elseif name=='onD3DDeviceLost' or name=='onD3DDeviceReset' then self.performance.lastFrame=nil
        elseif name=='onWindowMessage' then
            local msg,value=...
            if msg==0x8 or msg==0x1C and value==0 then self.performance.lastFrame=nil end
        end
    end
    -- Every ESC page belongs to GTA. Do not draw over it or consume its input.
    if (name=='onD3DPresent' or name=='onWindowMessage')and self.api.isPauseMenuActive()then return end
    if name=='onWindowMessage' then self:notePointerFocus((...))end
    if self.editingAllHud and name=='onD3DPresent' then return end
    if name=='onWindowMessage' and self.keys:captureActive()then
        local msg,key=...
        if msg==0x100 or msg==0x104 or msg==0x101 or msg==0x105 then
            self.keys:captureEvent(key,msg==0x100 or msg==0x104)
            if self.api.consumeWindowMessage then self.api.consumeWindowMessage(true,false)end
            return
        end
    end
    if name=='onWindowMessage' and self:guardChatKey(...)then return end
    if name=='onWindowMessage' and self.powered~=false and self.preferences.data.main.blockF1F4
        and self.modules.movement and self.modules.movement.enabled and self:featureAllowed('movement') then
        local msg,key=...
        if key==0x76 and (msg==0x100 or msg==0x101 or msg==0x104 or msg==0x105) then
            if self.api.consumeWindowMessage then self.api.consumeWindowMessage(true,false)end
            return
        end
    end
    if self.powered==false then
        if name=='onWindowMessage' then
            local msg,key=...
            local b=self.keys.data.menu
            if b and msg==0x101 and key==b.key and not self.api.sampIsChatInputActive() and not self.api.sampIsDialogActive()then
                if _G.show_main_window then _G.show_main_window.v=not _G.show_main_window.v end
                self:syncGui()
            end
        end
        return
    end
    for _, m in ipairs(self.order) do
        if m.id ~= 'core' and m.bridge and (self.access:displayLevel()~='S1' or self:featureAllowed(m.id)) then self:call(m, m.bridge[name], ...) end
    end
end

function Runtime:checkSession()
    if self.stopped then return false end
    self.access:sync()
    self:syncAccessClients()
    local state = self.api.sampGetGamestate()
    if state==3 and not self:serverSupports() then
        self.access:reset('X-Tools недоступен на этом сервере.')
        self:message('X-Tools остановлен: этот адрес не разрешён в коде скрипта.')
        self:shutdown()
        if type(self.host.unload)=='function' then self.host:unload() end
        return false
    end
    if self.gameState == 3 and state ~= 3 then
        self.protectedConfirmation=nil
        self.updateLoginPending=true
        if self.placement then self:finishPlacement()end
        self.gameState, self.sessionChanged = state, true
        for _, m in ipairs(self.order) do
            if m.bridge then self:call(m, m.bridge.onDisconnect) end
        end
    else self.gameState = state end
    if self.updateLoginPending and self.started and state==3 and self.access:canUseTools()then
        self.updateLoginPending=false
        self.updates:start()
    end
    return true
end

function Runtime:syncAccessClients()
    local serial=self.access:revision()
    if serial==self.accessSerial then return end
    self.protectedConfirmation=nil
    local identityChanged=self.access.identity~=self.accessIdentity
    self.accessSerial,self.accessIdentity=serial,self.access.identity
    if self.started then
        if not self.access:canUseTools() then
            if self.powered then self.adminSuspended=true;self:setPowered(false) end
            if self.access.current==0 then self:message('Скрипт предназначен для администраторов Advance RP.') end
        elseif self.adminSuspended then
            self.adminSuspended=false;self:setPowered(true)
        end
    end
    self.offban:reset()
    self.accessSerial,self.accessIdentity=serial,self.access.identity
    local pendingOwners={rvanka_warning=true,weapon_skills=true,core=true,familia=true,lookup=true,nakaz=true,aegis=true,queue=true,hospital=true,road=true,movement=true,autostart=true,autoreply=true,lego=true,tempfamily=true,menu=true,stopsbiv=true,invisible=true,clickwarp=true,reminders=true,rephelp=true,correction=true}
    for _,m in ipairs(self.order) do
        if m.bridge and (identityChanged or pendingOwners[m.id]) then
            self:call(m,m.bridge.onAccessChanged or m.bridge.onDisconnect)
        end
    end
end

function Runtime:openSettings(category)
    if category=='aegis' or category=='adm' then self:open(category);self.moduleMode='settings';return end
    local mapped={menu={'menu'},online={'core',1},environment={'core',1},gang={'capture'},stopsbiv={self.preferences.data.main.medkitMode=='families' and 'familia' or 'capture'},keys={'core',2},utilities={'core',3},chat={'core',4}}
    local item=mapped[category]
    self:open(item and item[1] or category)
    self.moduleMode='settings';if item and item[2] then self.coreSettingsTab=item[2] end
end

function Runtime:open(page)
    if self.access:displayLevel()=='S1' and page=='home' then page='core' end
    if self.access:displayLevel()=='S1' and not self:service('permissions.lua').s1Pages[page] then
        self:message('S1: доступны игровые функции и настройки оформления.');return
    end
    local minimum=self:service('permissions.lua').pages[page]
    if minimum and not self.access:require(minimum,function(reason)self:message(reason)end) then return end
    if not self.access:canUseTools() then self:message('Скрипт предназначен для администраторов Advance RP. Войдите в аккаунт администратора.');return end
    if self.keys.cancelCapture then self.keys:cancelCapture() end
    local standaloneLookup=page=='lookup' or page=='lego'
    local openingOverlay=standaloneLookup
    if openingOverlay then
        self.overlaySizes=self.overlaySizes or {}
        if self.overlay and self.overlayFullSize then self.overlaySizes[self.overlay]=self.overlayFullSize end
        self.overlayFullSize=self.overlaySizes[page]
        self.overlayWasMinimized=false
        self.overlay=page;self.overlayVisible=self.imgui.ImBool(true);self.overlaySettings=false;page=self.page or 'home'
    end
    self.page = page
    self.moduleMode = 'functions'
    if not openingOverlay and page~='modules' and self.overlay and page~='home' then self.overlayVisible.v=false end
    if _G.show_main_window then _G.show_main_window.v = not standaloneLookup end
    self:component('core').gui.Process = true
    self:syncGui()
end

function Runtime:menuOwnsKeys()
    local menu = self.modules.menu
    return menu and menu.enabled and menu.bridge and menu.bridge.ownsKeys and menu.bridge.ownsKeys() or false
end

local corePanels = {'teleportation_window','event_window','templeader_window','weather_window',
    'settings_window','statistic_window'}
function Runtime:selectCorePanel(name)
    for _, key in ipairs(corePanels) do
        if _G[key] then _G[key].v = key == name end
    end
end

function Runtime:drawMain(drawCore)
    if _G.show_main_window and _G.show_main_window.v then self.workspace.draw(self, drawCore) end
    if self.overlay and self.overlayVisible and self.overlayVisible.v then
        local g=self.imgui;local m=self.modules[self.overlay]
        local sw,sh=self.api.getScreenResolution()
        local minimized=m and m.bridge.isMinimized and m.bridge.isMinimized()
        local scale=self.preferences.data.main.scale or 1
        local initial={aegis={940,500},adm={1120,720},lookup={1250,900},lego={1120,720}}
        local dimensions=initial[self.overlay]
        local size=minimized and g.ImVec2(math.min(480*scale,sw-48),132*scale) or (self.overlayFullSize or g.ImVec2(math.min(dimensions[1]*scale,sw-48),math.min(dimensions[2]*scale,sh-64)))
        if g.SetNextWindowSizeConstraints then g.SetNextWindowSizeConstraints(g.ImVec2(math.min(420*scale,sw-48),math.min(240*scale,sh-64)),g.ImVec2(sw-48,sh-64)) end
        g.SetNextWindowSize(size,(minimized or self.overlayWasMinimized) and g.Cond.Always or g.Cond.FirstUseEver)
        self.overlayWasMinimized=minimized
        self.theme.apply(self.preferences.colors[self.preferences.data.main.color][2])
        local c,v=self.theme.push(g,self.preferences.data.main.scale or 1)
        local font=self.typography:get(16);if font then g.PushFont(font) end
        local title=({aegis='Автовыдача',adm='Чекер',lookup='Проверка игрока',lego='LEGO — поиск локаций'})[self.overlay]
        local visible=g.Begin('X-Tools — '..title..'###CasualTool — '..title,self.overlayVisible)
        if not minimized then self.overlayFullSize=g.GetWindowSize() end
        if visible and m and m.bridge then
            if self.overlay=='adm' then
                local entries={{'Настройки','Настройки##overlay_settings'}, {'Админы','Админы##checker_top'}, {'Лидеры','Лидеры##checker_top'}, {'Друзья','Друзья##checker_top'}}
                local available=g.GetContentRegionAvail().x;local count=available>=600 and 4 or 2
                for index,item in ipairs(entries) do
                    if (index-1)%count~=0 then g.SameLine() end
                    local selected=index==1 and self.overlaySettings or (not self.overlaySettings and (m.bridge.directoryPage or 2)==index)
                    if selected then g.PushStyleColor(g.Col.Button,self.theme.color(g,self.theme.palette.selection)) end
                    if g.Button(item[2],g.ImVec2((available-(count-1)*8)/count,32)) then
                        self.overlaySettings=index==1
                        if index>1 then m.bridge.directoryPage=index end
                    end
                    if selected then g.PopStyleColor(1) end
                end
                g.Separator();m.bridge.externalNavigation=true
            elseif self.overlay~='lookup' and self.overlay~='lego' then
                if g.Button('Функции##overlay_functions') then self.overlaySettings=false end
                g.SameLine();if g.Button('Настройки##overlay_settings') then self.overlaySettings=true end
                g.Separator()
            end
            self.drawingWorkspace=true
            self:call(m,m.bridge[self.overlaySettings and self.overlay~='lookup' and 'drawSettings' or 'draw'])
            self.drawingWorkspace=false
            if m then m.bridge.externalNavigation=false end
        end
        g.End();if font then g.PopFont() end;self.theme.pop(g,c,v)
        if not self.overlayVisible.v and m and m.bridge then self:call(m,m.bridge.onWindowClosed) end
    end
end

function Runtime:prepareReload()
    local ownedInput=self.imgui and (self.imgui.ShowCursor or self.imgui.LockPlayer) or _G.cursorEnabled or self.placement~=nil
    if self.placement then self:finishPlacement() end
    if self.preferences then self.preferences:save() end
    for _,m in ipairs(self.order) do
        if m.bridge and m.bridge.prepareReload then
            local ok,result=pcall(m.bridge.prepareReload)
            assert(ok and result~=false, 'Не удалось подготовить '..m.id..' к перезапуску: '..tostring(result))
        end
    end
    self.reloadOwnedInput=ownedInput
    self.reloading=true
    if _G.show_main_window then _G.show_main_window.v=false end
    if self.overlayVisible then self.overlayVisible.v=false end
    _G.cursorEnabled=false;_G.markerHeld=false;self.markerSession=nil
    for _,m in ipairs(self.order)do
        if m.gui then m.gui.Process=false;m.gui.ShowCursor=false;m.gui.LockPlayer=false end
    end
    if self.imgui then self:applyGuiState()end
    self:releaseReloadInput(self.reloadOwnedInput)
end

function Runtime:releaseReloadInput(owned)
    if not owned then return end
    local api=self.api
    if type(api.sampIsChatInputActive)=='function' and api.sampIsChatInputActive() then return end
    if type(api.sampIsDialogActive)=='function' and api.sampIsDialogActive() then return end
    self:releaseNativeSpectateInput()
end

function Runtime:shutdown()
    if self.stopped then return end
    if self.performance then self.performance:finish('SCRIPT STOPPED')end
    local ownedCursor=self.reloadOwnedInput or self.imgui and self.imgui.ShowCursor or _G.cursorEnabled or self.placement~=nil
    local ownedLock=self.imgui and self.imgui.LockPlayer
    if self.placement then self:finishPlacement() end
    if self.preferences then self.preferences:save() end
    self.stopped = true
    if self.api.sampUnregisterChatCommand then
        for name,command in pairs(self.commands) do
            if command.chatRegistered then pcall(self.api.sampUnregisterChatCommand,name);command.chatRegistered=false end
        end
    end
    if self.fastConnect then self.fastConnect:stop() end
    self.updates:stop()
    if self.avatar then self.avatar:shutdown() end
    self:service('art.lua').shutdownAll()
    if self.aboutArt and self.aboutArt.texture then pcall(self.imgui.ReleaseTexture,self.aboutArt.texture);self.aboutArt=nil end
    for _, m in ipairs(self.order) do if m.id ~= 'core' then self:stop(m) end end
    for font in pairs(self.nativeFonts.entries) do pcall(function() self.nativeFonts:release(font) end) end
    if self.modules.core then self.modules.core.gui.Process=false; self.modules.core.gui.ShowCursor=false end
    if _G.show_main_window then _G.show_main_window.v=false end
    self.placement=nil;self.markerSession=nil;_G.cursorEnabled=false;_G.markerHeld=false
    if self.overlayVisible then self.overlayVisible.v=false end
    if self.imgui then self.imgui.Process=false;self.imgui.ShowCursor=false;self.imgui.LockPlayer=false;self.imgui.DisableInput=false end
    -- The ImGui cursor coroutine may not get another frame before unload.
    pcall(function()self:releaseReloadInput(ownedCursor or ownedLock)end)
end

return Runtime
