-- X-TOOLS | Project and integration: Casual_Alvarez | Module: preferences.lua
-- Original third-party credits, where present, are retained below.
local Preferences={}
Preferences.__index=Preferences
Preferences.colors={{'Фиолетовый',0xC080FF,0x322B4C},{'Голубой',0x40CEFF,0x203B50},
    {'Мятный',0x35F4B3,0x203E37},{'Розовый',0xFF70BD,0x4A2B3B},{'Янтарный',0xFFD04A,0x493D29},
    {'Красный',0xFF4F70,0x4B2530},
    {'Аврора · ледяной голубой',0x59DFFF,0x203B45},
    {'Янтарь · тёплое золото',0xFFAB51,0x493322},
    {'Нефрит · изумрудный',0x62E9AB,0x234236},
    {'Рубин · красный кристалл',0xFF6086,0x482633},
    {'Космос · лавандовый',0xAA91FF,0x352C4D}}

local function finite(value,fallback)
    local number=tonumber(value)
    if not number or number~=number or number==math.huge or number==-math.huge then return fallback end
    return number
end

local function boolean(value,fallback)
    if value==true or value==1 or value=='true' then return true end
    if value==false or value==0 or value=='false' then return false end
    return fallback
end

function Preferences:validate()
    self.data=type(self.data)=='table' and self.data or {}
    self.data.main=type(self.data.main)=='table' and self.data.main or {}
    local p=self.data.main
    p.color=math.max(1,math.min(#Preferences.colors,math.floor(finite(p.color,1))))
    p.font=math.max(1,math.min(11,math.floor(finite(p.font,1))))
    for _,key in ipairs({'logoStyle','backgroundStyle'}) do
        p[key]=math.max(0,math.min(5,math.floor(finite(p[key],0))))
    end
    if p.pendingThemeStyle~=nil then p.pendingThemeStyle=math.max(0,math.min(5,math.floor(finite(p.pendingThemeStyle,0))))end
    if p.pendingFont~=nil then p.pendingFont=math.max(1,math.min(11,math.floor(finite(p.pendingFont,1))))end
    -- Migrate mixed legacy choices to the theme of the selected background.
    p.themeStyle=math.max(0,math.min(5,math.floor(finite(p.themeStyle,p.backgroundStyle))))
    p.logoStyle=p.themeStyle
    p.backgroundStyle=p.themeStyle
    p.color=p.themeStyle>0 and 6+p.themeStyle or 1
    p.statusPanelStyle=math.max(0,math.min(5,math.floor(finite(p.statusPanelStyle,0))))
    p.fishEyeAngle=math.max(30,math.min(150,math.floor(finite(p.fishEyeAngle,101))))
    p.scale=1 -- Migrate old interface zoom to the single supported size.
    p.timezoneEnabled=boolean(p.timezoneEnabled,false)
    p.timezoneMskOffset=math.max(-15,math.min(11,math.floor(finite(p.timezoneMskOffset,0))))
    p.compactSidebar=boolean(p.compactSidebar,false)
    p.wallpaper=boolean(p.wallpaper,true)
    p.motion=boolean(p.motion,true)
    p.pauseMenu=nil -- Retired custom ESC; discard legacy / imported settings.
    p.windowManual=boolean(p.windowManual,false)
    p.windowMoved=boolean(p.windowMoved,false)
    p.windowPresetVersion=math.max(0,math.floor(finite(p.windowPresetVersion,0)))
    if p.windowPresetVersion<1 then
        -- Apply the shared home layout once, including existing manual sizes.
        p.windowWidth,p.windowHeight,p.windowX,p.windowY=0,0,0,0
        p.windowManual,p.windowMoved=false,false
        p.windowPresetVersion=1
        self.windowPresetPending=true
    end
    for _,name in ipairs({'windowWidth','windowHeight','windowX','windowY'}) do
        -- Zero means initial placement/size; the workspace clamps to the actual screen.
        p[name]=math.max(0,math.min(32768,math.floor(finite(p[name],0))))
    end
    for _,name in ipairs({'commandLayout','streamer','ghetto','families','roadFollowup','legoReplace','antiBH','blockF1F4','matrixJump','backFlip','cjMovement','fishEye','spectateChatN','invisibleOnStart','invisibleChatN'}) do p[name]=boolean(p[name],false) end
    for _,name in ipairs({'killidsKiller','killidsVictim'}) do p[name]=boolean(p[name],true) end
    if p.medkitMode~='ghetto' and p.medkitMode~='families' then p.medkitMode='none' end
    return p
end

function Preferences.new(storage)
    local path=storage:path('settings','interface.ini')
    local defaults={main={color=1,font=1,scale=1,compactSidebar=false,wallpaper=true,motion=true,
        windowWidth=0,windowHeight=0,windowX=0,windowY=0,windowManual=false,windowMoved=false,windowPresetVersion=0,
        streamer=false,ghetto=false,families=false,medkitMode='none',killidsKiller=true,killidsVictim=true}}
    local ok,data=pcall(storage.loadIni,storage,defaults,path)
    local recovery
    if not ok then
        local backupOk,backup=pcall(function()
            assert(storage:exists(path..'.bak'),'No backup')
            return storage:loadIni(defaults,path..'.bak')
        end)
        data=backupOk and backup or defaults
        recovery=backupOk and 'Настройки интерфейса восстановлены из резервной копии.'
            or 'Настройки интерфейса повреждены. Используется стандартное оформление.'
    end
    local self=setmetatable({storage=storage,path=path,data=data},Preferences)
    self:validate()
    -- Apply saved appearance only at construction, before loading any textures/fonts.
    if self.data.main.pendingThemeStyle~=nil then
        self.data.main.themeStyle=self.data.main.pendingThemeStyle
        self.data.main.pendingThemeStyle=nil
    end
    if self.data.main.pendingFont~=nil then
        self.data.main.font=self.data.main.pendingFont
        self.data.main.pendingFont=nil
    end
    self:validate()
    if recovery then
        self.recoveryPending=true;self.recoveryNotice=recovery
        if not self:save() then self.recoveryNotice=recovery..' Сохранение недоступно; исходные файлы не перезаписаны.' end
    end
    return self
end
function Preferences:save()
    self:validate()
    if self.recoveryPending then
        local ok,saved=pcall(function()
            -- Preserve both original inputs before saveIni rotates .bak.
            for _,source in ipairs({self.path,self.path..'.bak'})do
                if self.storage:exists(source)then
                    local bytes=assert(self.storage:read(source),'Cannot preserve damaged settings')
                    local archive
                    for i=1,1000 do
                        local candidate=source..'.damaged.'..i
                        if not self.storage:exists(candidate)then archive=candidate;break end
                    end
                    assert(archive,'Too many recovery archives')
                    assert(self.storage:write(archive,bytes),'Cannot archive settings')
                end
            end
            return self.storage:saveIni(self.data,self.path)
        end)
        if not ok or not saved then return false end
        self.recoveryPending=false
        return true
    end
    return self.storage:saveIni(self.data,self.path)
end
function Preferences:mask(text)
    if not self.data.main.streamer or type(text)~='string' then return text end
    -- Presentation only: raw protocol messages and data stay available to parsers.
    return (text:gsub('%d+%.%d+%.%d+%.%d+', '[IP скрыт]'))
end
return Preferences
