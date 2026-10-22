-- X-TOOLS | Project and integration: Casual_Alvarez | Module: keybinds.lua
-- Original third-party credits, where present, are retained below.
-- Shared bindings and their editor. Edits are committed only after conflict review.
local Keys={}
Keys.__index=Keys

local function binding(data)
    data=data or {}
    return {key=tonumber(data.key) or 0,ctrl=data.ctrl==true,alt=data.alt==true,
        shift=data.shift==true,second=tonumber(data.second) or 0,third=tonumber(data.third) or 0,originalVersion=tonumber(data.originalVersion) or 0}
end

-- A longer chord takes priority over every strict subset.
local function extends(short,long)
    if not short or not long or short.key==0 or long.key==0 then return false end
    local a,b={},{}
    for _,k in ipairs({short.key,short.second or 0,short.third or 0})do if k>0 then a[k]=true end end
    for _,k in ipairs({long.key,long.second or 0,long.third or 0})do if k>0 then b[k]=true end end
    for flag,key in pairs({ctrl=17,alt=18,shift=16})do
        if short[flag]then a[key]=true end
        if long[flag]then b[key]=true end
    end
    local extra=false
    for k in pairs(a)do if not b[k]then return false end end
    for k in pairs(b)do if not a[k]then extra=true end end
    return extra
end

-- Legacy MoonImGui does not wrap long words. Never split a UTF-8 code point.
local function wrap(g,text,width)
    local lines,line={},''
    width=math.max(1,width)
    for paragraph in (tostring(text)..'\n'):gmatch('(.-)\n') do
        line=''
        for word in paragraph:gmatch('%S+') do
            local nextLine=line=='' and word or line..' '..word
            if g.CalcTextSize(nextLine).x<=width then line=nextLine
            else
                if line~='' then lines[#lines+1]=line;line='' end
                for char in word:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                    if line~='' and g.CalcTextSize(line..char).x>width then lines[#lines+1]=line;line='' end
                    line=line..char
                end
            end
        end
        lines[#lines+1]=line
    end
    return table.concat(lines,'\n'),#lines*(tonumber(g.CalcTextSize('M').y) or 16)
end

function Keys.new(api,storage)
    local path=storage:path('settings','keybinds.ini')
    return setmetatable({api=api,storage=storage,path=path,data=storage:loadIni({},path),items={},order={}},Keys)
end

function Keys:register(id,label,defaults,changed,active)
    if self.items[id] then return self.items[id] end
    local originals={matrix_jump={key=32,shift=true},back_flip={key=32,second=67},
        clickwarp={key=4},observer_chat={key=116}}
    defaults=originals[id] or defaults
    local data=binding(self.data[id] or defaults)
    if originals[id] and data.originalVersion<1 then
        if data.key==0 then data=binding(defaults) end
        data.originalVersion=1
        self.data[id]=data
        self.storage:saveIni(self.data,self.path)
    end
    if id=='report_assist' and data.key==74 and data.alt and not data.ctrl and not data.shift and data.second==0 and data.third==0 then
        data=binding(defaults)
        self.data[id]=data;self.storage:saveIni(self.data,self.path)
    end
    self.data[id]=data
    local item={id=id,label=label,changed=changed,active=active,defaults=defaults}
    self.items[id]=item;self.order[#self.order+1]=item
    if changed then changed(data) end
    return item
end

function Keys:format(data)
    local b=binding(data)
    if b.key==0 then return 'Не назначена' end
    local function keyName(key)
        local known={[1]='Mouse 1',[2]='Mouse 2',[4]='Mouse 3',[5]='Mouse 4',[6]='Mouse 5',
            [16]='Shift',[17]='Ctrl',[18]='Alt',[8]='Backspace',[9]='Tab',[13]='Enter',[19]='Pause',[27]='Esc',[32]='Space',[33]='Page Up',[34]='Page Down',
            [35]='End',[36]='Home',[37]='Left',[38]='Up',[39]='Right',[40]='Down',
            [45]='Insert',[46]='Delete',[188]=',',[190]='.',[192]='~'}
        if known[key] then return known[key] end
        if key>=112 and key<=135 then return 'F'..(key-111) end
        if key>=48 and key<=90 then return string.char(key) end
        local vk=self.api.require('vkeys')
        if vk.id_to_name then
            local ok,value=pcall(vk.id_to_name,key)
            if ok and type(value)=='string' then return value:gsub('^VK_','') end
        end
        return tostring(key)
    end
    return (b.ctrl and 'Ctrl + ' or '')..(b.alt and 'Alt + ' or '')..(b.shift and 'Shift + ' or '')
        ..keyName(b.key)..(b.second>0 and ' + '..keyName(b.second) or '')..(b.third>0 and ' + '..keyName(b.third) or '')
end

function Keys:name(id) return self:format(self.data[id]) end

function Keys:textInputActive(includeKeyboardCapture)
    -- Poll outside the draw callback as well: floating editors share this
    -- context but do not necessarily open the main X-Tools window.
    local ok,active=pcall(function()
        self.inputGui=self.inputGui or self.api.require('imgui')
        local g=self.inputGui
        if not g or g.Process==false or g.DisableInput==true then return false end
        if g.SwitchContext then g.SwitchContext() end
        local io=g.GetIO and g.GetIO()
        return io and (io.WantTextInput==true or includeKeyboardCapture==true and io.WantCaptureKeyboard==true) or false
    end)
    return ok and active==true
end

function Keys:rawDown(id)
    local b=self.data[id];local a=self.api
    if not b or b.key==0 or b.key==9 or b.second==9 or b.third==9 or self:captureActive() then return false end
    local item=self.items[id]
    if item and item.active and not item.active()then
        item.down=false;item.chordUsed=false;item.heldChordUsed=false
        return false
    end
    if self:textInputActive() then
        if item then
            item.inputSuppressed=true
            item.down=false;item.chordUsed=false;item.heldChordUsed=false
        end
        return false
    end
    if item and item.inputSuppressed then
        -- A key held while editing must not become a fresh press (or the
        -- release of a shorter chord) when the editor loses focus.
        item.down=false;item.chordUsed=false;item.heldChordUsed=false
        if not a.isKeyDown(b.key) and (b.second==0 or not a.isKeyDown(b.second))
            and ((b.third or 0)==0 or not a.isKeyDown(b.third)) then
            item.inputSuppressed=nil
        end
        return false
    end
    return a.isKeyDown(b.key) and (b.second==0 or a.isKeyDown(b.second))
        and ((b.third or 0)==0 or a.isKeyDown(b.third))
        and (not b.ctrl or a.isKeyDown(0x11)) and (not b.alt or a.isKeyDown(0x12)) and (not b.shift or a.isKeyDown(0x10))
end

-- Held actions share chord priority, and cannot reactivate as a chord is released.
function Keys:down(id)
    local item=self.items[id]
    if not item then return false end
    if not self:rawDown(id) then item.heldChordUsed=false;return false end
    for other in pairs(self.items)do
        if other~=id and self:overlaps(id,other) and extends(self.data[id],self.data[other]) and self:rawDown(other)then
            item.heldChordUsed=true
        end
    end
    return not item.heldChordUsed
end

function Keys:pressed(id)
    local item=self.items[id];if not item then return false end
    if self:captureActive()then item.down=false;item.chordUsed=false;return false end
    local down=self:rawDown(id)
    if down then
        for other,shortItem in pairs(self.items)do
            if self:overlaps(id,other) and extends(self.data[other],self.data[id])then shortItem.chordUsed=true end
        end
    end
    local hasLonger,used=false,false
    for other in pairs(self.items)do
        if other~=id and self:overlaps(id,other) and extends(self.data[id],self.data[other])then
            hasLonger=true
            if self:rawDown(other)then used=true end
        end
    end
    if hasLonger then
        if used then item.chordUsed=true end
        local fire=not down and item.down and not item.chordUsed
        item.down=down
        if not down then item.chordUsed=false end
        return fire==true
    end
    local pressed=down and not item.down;item.down=down;return pressed
end

function Keys:cancelCapture()
    self.capture=nil;self.pending=nil;self.captureError=nil;self.captureHeld={};self.captureOrder={};self.captureCandidate=nil
end

local modifiers={[16]=16,[160]=16,[161]=16,[17]=17,[162]=17,[163]=17,[18]=18,[164]=18,[165]=18}
function Keys:captureActive()
    if self.externalCapture then
        local now=self.api.getGameTimer and self.api.getGameTimer()or 0
        if now<=(self.externalCaptureUntil or 0) then
            if self.externalCapture:captureActive() then return true end
        else
            self.externalCapture:cancelCapture();self.externalCapture=nil
        end
    end
    return self.capture~=nil or (self.suppressUntil or 0)>(self.api.getGameTimer and self.api.getGameTimer()or 0)
end
function Keys:captureEvent(key,down)
    if not self.capture or self.pending then return end
    key=modifiers[key]or key
    self.captureHeld=self.captureHeld or {};self.captureOrder=self.captureOrder or {}
    if key==27 then if down then self:cancelCapture()end;return end
    if key==8 then if down then self.captureCandidate=binding()end;return end
    if down then
        if not self.captureHeld[key]then self.captureOrder[#self.captureOrder+1]=key end
        self.captureHeld[key]=true
    elseif self.captureHeld[key]then
        local primary={};local mods={}
        for _,k in ipairs(self.captureOrder)do
            if modifiers[k]then mods[k]=true else primary[#primary+1]=k end
        end
        local data={key=primary[1]or key,second=primary[2]or 0,third=primary[3]or 0,
            ctrl=mods[17]and key~=17 or #primary>0 and mods[17],
            alt=mods[18]and key~=18 or #primary>0 and mods[18],
            shift=mods[16]and key~=16 or #primary>0 and mods[16]}
        self.captureHeld[key]=nil
        if #primary>3 then self.captureError='Можно назначить до трёх клавиш и модификаторы.';self.captureOrder={};self.captureHeld={}
        else self.captureCandidate=binding(data)end
    end
end

-- Possible execution modes, not whether a feature happens to be enabled now.
-- Unclassified/global actions retain conservative conflict checks.
local function modes(id)
    if id:match('^observation_')then return {spectate_menu=true}end
    if id=='previous'or id=='next'then return {spectate_direct=true}end
    if id=='clickwarp'or id=='clickwarp_apply'then return {spectate_menu=true,spectate_direct=true}end
    if id=='matrix_jump'or id=='back_flip'then return {foot=true}end
    if id=='speed_boost'then return {vehicle=true}end
    if id=='airbreak_car_up'or id=='airbreak_car_down'then return {airvehicle=true}end
    if id=='airbreak_ground'then return {airfoot=true}end
    if id=='airbreak'or id=='broom'then return {foot=true,vehicle=true,airfoot=true,airvehicle=true,broom=true}end
    if id:match('^airbreak_')then return {airfoot=true,airvehicle=true}end
end
function Keys:overlaps(first,second)
    local a,b=modes(first),modes(second)
    if not a or not b then return true end
    for mode in pairs(a)do if b[mode]then return true end end
    return false
end

function Keys:conflicts(id,data)
    data=binding(data)
    local found={}
    if data.key==0 then return found end
    for _,item in ipairs(self.order) do
        local other=self.data[item.id]
        -- Current runtime allows extra held modifiers. M and Ctrl+M can fire
        -- together, as can Q and Q+E; warn even for a currently inactive module.
        if item.id~=id and self:overlaps(id,item.id) and other and other.key>0 and not extends(data,other) and not extends(other,data) and
            (data.key==other.key or data.second>0 and data.second==other.key
                or other.second>0 and (data.key==other.second or data.second==other.second)
                or (data.third or 0)>0 and (data.third==other.key or data.third==other.second or data.third==other.third)
                or (other.third or 0)>0 and (data.key==other.third or data.second==other.third)
                or data.key==16 and other.shift or data.key==17 and other.ctrl or data.key==18 and other.alt
                or other.key==16 and data.shift or other.key==17 and data.ctrl or other.key==18 and data.alt) then
            found[#found+1]=item
        end
    end
    return found
end

local function reserved(data) return data.key==9 or data.second==9 or data.third==9 end

function Keys:commit(id,data,replace)
    if reserved(data) then self.captureError="Tab используется таблицей игроков и не может быть переназначен.";return false end
    if not self.items[id] then return false end
    local nextData={}
    for key,value in pairs(self.data) do nextData[key]=binding(value) end
    local changed={id}
    if replace then
        for _,item in ipairs(self:conflicts(id,data)) do
            nextData[item.id]=binding({originalVersion=self.data[item.id].originalVersion});changed[#changed+1]=item.id
        end
    end
    nextData[id]=binding(data)
    nextData[id].originalVersion=tonumber(self.data[id].originalVersion) or 0
    local ok,err=self.storage:saveIni(nextData,self.path)
    if not ok then
        self.captureError='Не удалось сохранить назначение. Проверьте доступ к папке настроек.'
        return false,err
    end
    self.data=nextData
    for _,key in ipairs(changed) do
        local item=self.items[key]
        if item and item.changed then item.changed(self.data[key]) end
    end
    self.suppressUntil=(self.api.getGameTimer and self.api.getGameTimer()or 0)+300
    self:cancelCapture()
    return true
end

function Keys:request(id,data)
    data=binding(data)
    if reserved(data) then self.captureError="Tab используется таблицей игроков и не может быть переназначен.";return false end
    local conflicts=self:conflicts(id,data)
    if #conflicts>0 then
        self.pending={id=id,data=data};self.capture=id
        return false
    end
    return self:commit(id,data)
end

function Keys:drawCapture(g,id)
    if self.capture~=id then return end
    local width=math.max(1,g.GetContentRegionAvailWidth())
    local function text(value) g.TextWrapped((wrap(g,value,width))) end
    local function action(value,suffix)
        local padding=g.GetStyle().FramePadding
        local label,height=wrap(g,value,math.max(1,width-padding.x*2))
        local scale=(tonumber(g.CalcTextSize('M').y) or 16)/16
        return g.Button(label..'##'..suffix,g.ImVec2(math.min(width,g.CalcTextSize(label).x+padding.x*2),
            math.max(32*scale,height+padding.y*2)))
    end
    if self.api.isKeyJustPressed(27) then self:cancelCapture();return end
    -- Handle the cancel click before polling mouse buttons for a new binding.
    if action('Отмена','bind_cancel_'..id) then self:cancelCapture();return end
    if self.pending then
        local conflicts=self:conflicts(id,self.pending.data)
        local labels={};for _,item in ipairs(conflicts) do labels[#labels+1]='«'..item.label..'»' end
        text('Сочетание '..self:format(self.pending.data)..' пересекается с: '..table.concat(labels,', ')..'.')
        text('Перенос снимет назначения только у перечисленных действий, которые могут работать в том же режиме.')
        if action('Перенести назначение','bind_replace_'..id) then
            local data=self.pending.data;self:commit(id,data,true)
        end
        if self.capture and action('Выбрать другое','bind_retry_'..id) then self.pending=nil;self.captureError=nil end
    else
        text('Зажмите до трёх клавиш и отпустите. Можно назначить отдельно Shift / Ctrl / Alt. Esc — отмена, Backspace — убрать назначение.')
        if self.captureCandidate then local value=self.captureCandidate;self.captureCandidate=nil;self:request(id,value);return end
        self.capturePoll=self.capturePoll or {}
        for key=1,255 do
            if key~=3 and key~=7 and key<160 then
                local down=self.api.isKeyDown(key)==true
                if down and not self.capturePoll[key]then self:captureEvent(key,true)
                elseif not down and self.capturePoll[key]then self:captureEvent(key,false)
                elseif not down and self.api.isKeyJustPressed(key)then self:captureEvent(key,true);self:captureEvent(key,false)end
                self.capturePoll[key]=down
            end
        end
        if self.captureCandidate then local value=self.captureCandidate;self.captureCandidate=nil;self:request(id,value)end
    end
    if self.captureError then text(self.captureError) end
end

function Keys:draw(g,id,columnWidth)
    local item=self.items[id];if not item then return end
    -- Module facades scale legacy absolute dimensions. This shared editor already
    -- measures the active font, so draw through the same raw renderer only once.
    self.gui=self.gui or self.api.require('imgui')
    g=self.gui or g
    local width=math.max(1,g.GetContentRegionAvailWidth())
    local lineHeight=tonumber(g.CalcTextSize('M').y) or 16
    local scale=lineHeight/16
    local gap=8*scale
    local padding=g.GetStyle().FramePadding
    local startX,startY=g.GetCursorPosX(),g.GetCursorPosY()
    local stacked=width<280*scale
    local keyWidth=stacked and width or math.min(columnWidth or 166*scale,width*0.46)
    local keyText=self.capture==id and (self.pending and 'Конфликт сочетания' or 'Ожидание клавиши…') or self:name(id)
    local label,keyHeight=wrap(g,keyText,math.max(1,keyWidth-padding.x*2))
    local description,descriptionHeight=wrap(g,item.label,stacked and width or math.max(1,width-keyWidth-gap))
    local buttonHeight=math.max(32*scale,keyHeight+padding.y*2)
    local rowHeight=stacked and buttonHeight+gap+descriptionHeight or math.max(buttonHeight,descriptionHeight)
    local clicked=g.Button(label..'##bind_'..id,g.ImVec2(keyWidth,buttonHeight))
    if stacked then g.SetCursorPos(g.ImVec2(startX,startY+buttonHeight+gap))
    else g.SetCursorPos(g.ImVec2(startX+keyWidth+gap,startY+math.max(0,(buttonHeight-descriptionHeight)/2))) end
    g.TextWrapped(description)
    g.SetCursorPos(g.ImVec2(startX,startY+rowHeight))
    g.Dummy(g.ImVec2(0,4*scale))
    if clicked then
        self:cancelCapture();self.capture=id;self.capturePoll={}
        for key=1,255 do self.capturePoll[key]=self.api.isKeyDown(key)==true end
        -- The click that opens capture must not bind Mouse 1 on the same frame.
    else self:drawCapture(g,id) end
end

function Keys:drawAll(g)
    g.TextWrapped('Нажмите сочетание слева от действия, чтобы изменить его. Изменения сохраняются сразу.')
    g.Spacing()
    local scale=(tonumber(g.CalcTextSize('M').y) or 16)/16
    local width=150*scale
    for _,item in ipairs(self.order) do width=math.max(width,g.CalcTextSize(self:name(item.id)).x+24*scale) end
    width=math.min(width,210*scale)
    local columns=g.GetContentRegionAvailWidth()>=620*scale
    if columns then g.Columns(2,'shared_keybind_editor',false) end
    for _,item in ipairs(self.order) do
        self:draw(g,item.id,width)
        if columns then g.NextColumn() end
    end
    if columns then g.Columns(1) end
end

return Keys
