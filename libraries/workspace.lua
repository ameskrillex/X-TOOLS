-- X-TOOLS | Project and integration: Casual_Alvarez | Module: workspace.lua
-- Original third-party credits, where present, are retained below.
-- CasualTool workspace. One root window; pages never own a second main window.
local Workspace = {}
local modules = {
    {'menu','Режим слежки','Панели, действия и отображение','eye'},
    {'core','Основные инструменты','Управление, игровые функции и общие настройки','tools'},
    {'aegis','Автовыдача','Запросы наказаний и защищённые списки','shield'},
    {'adm','Чекер','Администраторы, лидеры и друзья','checker'},
    {'capture','Гетто','Капты, Discord, наказания и контроль аптечек','territory'},
    {'familia','Семьи','Семейные команды и контроль аптечек','family'},
    {'queue','Очередь из файла','Подготовка и отправка наказаний','filequeue'},
    {'bullet','Траектории выстрелов','Свои и чужие выстрелы','target'},
    {'autoreply','Автоответ','Автоматические ответы на обращения по правилам','reply'},
    {'rephelp','Биндер','Редактируемые команды и ответы игрокам','keyboard'},
    {'reminders','Напоминание игрокам в msg','Наборы сообщений для игроков','megaphone'},
    {'joinquit','Входы и выходы','Журнал событий игроков','entry'}
}
Workspace.modules=modules
local function moduleById(id)
    for _,item in ipairs(modules) do if item[1]==id then return item end end
end
local navigation={{'home','Главная','','home'},{'gameplay','Игровые функции','','gameplay'},{'teleport','Телепорт','','target'}}
for _,item in ipairs(modules) do navigation[#navigation+1]=item end
Workspace.navigation=navigation
local pages = {
    {'gameplay','Игровые функции','Передвижение, отображение и игровые возможности','gameplay'},
    {'teleport','Телепорт','Каталог мест и интерьеров','target'},
    {'about','Об авторе','','users'},
    {'home','Главная','Всё для вашей смены','home'},
    {'core','Инструменты','Телепортация, мероприятия и управление сервером','tools'},
    {'aegis','Наказания','Запросы, проверка и подтверждение','shield'},
    {'adm','Чекер','Администраторы, лидеры и друзья','checker'},
    {'lookup','Проверка игрока','Аккаунт, история ников, IP и блокировки','users','Проверка'},
    {'menu','Наблюдение','Панели игрока и действия в слежке','eye'},
    {'capture','Капты','Ход капта, составы и отчёты','territory'},
    {'familia','Семьи','Информация о семье и семейные наказания','family'},
    {'joinquit','Входы и выходы','Журнал событий игроков','entry'},
    {'statistics','Статистика','Результаты работы администратора','chart'},
    {'settings','Настройки','Все переключатели и параметры CasualTool','settings'},
    {'commands','Справка','Команды, подсказки и ответы на частые вопросы','help'}
}
local tools = {
    {'Мероприятия','event_window',4},
    {'Лидерство и семья','templeader_window',3}, {'Погода сервера','weather_window',4}
}
local helpSections={reminders='reminders',autoreply='autoreply',home='start',core='tools',aegis='punishments',adm='checker',lookup='lookup',
    menu='observation',capture='capture',familia='families',joinquit='events',statistics='start',settings='system',commands='start',modules='start',queue='queue',
    schedule='schedule',online='online',gang='punishments',bullet='observation',stopsbiv='observation',environment='tools',hospital='tools',road='tools',killids='observation'}
local function pageById(id)
    if id=='schedule' then return {'schedule','Расписание мероприятий','Ежедневные события по московскому времени','chart'} end
    local module=moduleById(id)
    if module then return {module[1],module[2],module[3],module[4]} end
    if id=='settings' then return {'settings','Система X-Tools','Общие права, хранение данных и обновления','settings'} end
    for _, p in ipairs(pages) do if p[1] == id then return p end end
    return pages[1]
end

-- A small drawing vocabulary keeps spacing, type and hit areas identical.
local function painter(rt)
    local g, p = rt.imgui, rt.theme.palette
    local origin, draw = g.GetWindowPos(), g.GetWindowDrawList()
    origin=g.ImVec2(origin.x-g.GetScrollX(),origin.y-g.GetScrollY())
    local ui = {}
    local function point(x,y) return g.ImVec2(origin.x+x,origin.y+y) end
    local function color(hex) return g.GetColorU32(rt.theme.color(g,hex)) end
    function ui.rect(x,y,w,h,c,r)
        draw:AddRectFilled(point(x,y),point(x+w,y+h),color(c),r or 8,-1)
    end
    function ui.line(x,y,x2,y2,c,width)
        draw:AddLine(point(x,y),point(x2,y2),color(c),width or 1)
    end
    function ui.panel(x,y,w,h)
        -- Nine-slice keeps the generated corners crisp on tall and wide cards.
        draw:AddRectFilled(point(x+2,y+5),point(x+w+2,y+h+5),0x48000000,12)
        local art=rt.art and rt.art:get('dashboard-panel')
        if art then
            local edge=math.min(30,w/3,h/3)
            local xs,ys={0,edge,w-edge,w},{0,edge,h-edge,h}
            local uv={0,.10,.90,1}
            local tint=color(p.accent)
            for row=1,3 do for col=1,3 do
                draw:AddImage(art.texture,point(x+xs[col],y+ys[row]),point(x+xs[col+1],y+ys[row+1]),
                    g.ImVec2(uv[col],uv[row]),g.ImVec2(uv[col+1],uv[row+1]),tint)
            end end
        else
            ui.rect(x,y,w,h,p.surface,12)
            draw:AddRect(point(x,y),point(x+w,y+h),color(p.border),12)
        end
    end
    function ui.profileFrame(x,y,w,h,scale)
        local art=rt.art and rt.art:get('profile-card')
        ui.rect(x,y,w,h,p.surface,12*scale)
        if not art then return end
        -- The artwork includes transparent glow outside its frame. Map the
        -- frame itself, keeping its corners intact instead of cover-cropping.
        local edge=math.min(24*scale,w/3,h/3)
        local xs,ys={0,edge,w-edge,w},{0,edge,h-edge,h}
        local us,vs={.012,.065,.935,.99},{.105,.22,.74,.865}
        for row=1,3 do for col=1,3 do
            draw:AddImage(art.texture,point(x+xs[col],y+ys[row]),point(x+xs[col+1],y+ys[row+1]),
                g.ImVec2(us[col],vs[row]),g.ImVec2(us[col+1],vs[row+1]),color(p.accent))
        end end
    end
    function ui.font(size,bold)
        local f=rt.typography:get(size,bold)
        if f then g.PushFont(f) end
        return f
    end
    function ui.text(x,y,text,size,c,width,bold)
        local f=ui.font(size or 16,bold)
        text=rt.preferences:mask(tostring(text or ''))
        if width then text=rt:service('ui_components.lua').wrap(g,text,width) end
        local height=g.CalcTextSize(text).y
        g.SetCursorPos(g.ImVec2(x,y))
        g.TextColored(rt.theme.color(g,c or p.text),text)
        if f then g.PopFont() end
        return height
    end
    function ui.measure(text,size,width,bold)
        local f=ui.font(size or 16,bold)
        local value=rt:service('ui_components.lua').wrap(g,rt.preferences:mask(text),width)
        local height=g.CalcTextSize(value).y
        if f then g.PopFont() end
        return height
    end
    function ui.hit(id,x,y,w,h)
        g.SetCursorPos(g.ImVec2(x,y))
        local pressed=g.InvisibleButton(id,g.ImVec2(w,h))
        return pressed,g.IsItemHovered()
    end
    function ui.zoneButton(id,x,y,w,callback)
        local h=math.max(44,w/5)
        local pressed,hovered=ui.hit(id,x,y,w,h)
        local art=rt.art and rt.art:get('adminzone-button')
        if art then
            local tint=rt.theme.color(g,p.accent);tint.w=hovered and 1 or .82
            draw:AddImage(art.texture,point(x,y),point(x+w,y+h),g.ImVec2(0,.19),g.ImVec2(1,.77),g.GetColorU32(tint))
        else ui.rect(x,y,w,h,hovered and p.accent or p.button,10)end
        local f=ui.font(16,true)
        local label='Admin Zone (/az)'
        local size=g.CalcTextSize(label)
        draw:AddText(point(x+20,y+(h-size.y)/2),color(p.text),label)
        if f then g.PopFont()end
        if pressed then callback()end
        return h
    end
    function ui.icon(kind,x,y,c)
        local scale=rt.preferences.data.main.scale or 1
        local function l(a,b,d,e) ui.line(x+a*scale,y+b*scale,x+d*scale,y+e*scale,c,1.6*scale) end
        local function circle(a,b,r)
            draw:AddCircle(point(x+a*scale,y+b*scale),r*scale,color(c),24,1.6*scale)
        end
        if kind=='checker' then
            circle(6,5,3);l(1,15,1,12);l(1,12,4,10);l(4,10,8,10)
            circle(12,12,4);l(15,15,18,18)
        elseif kind=='territory' then
            l(2,17,2,2);l(2,3,9,1);l(9,1,16,4);l(16,4,16,12)
            l(16,12,9,9);l(9,9,2,11);l(9,1,9,9)
        elseif kind=='family' then
            circle(9,4,2.5);circle(3,7,2);circle(15,7,2)
            l(5,17,5,12);l(5,12,7,10);l(7,10,11,10);l(11,10,13,12);l(13,12,13,17)
            l(1,16,1,12);l(1,12,3,11);l(17,16,17,12);l(17,12,15,11)
        elseif kind=='filequeue' then
            l(3,1,11,1);l(11,1,16,6);l(16,6,16,17);l(16,17,3,17);l(3,17,3,1)
            l(11,1,11,6);l(11,6,16,6);l(6,9,12,9);l(6,12,12,12);l(6,15,10,15)
        elseif kind=='target' then
            circle(9,9,6);circle(9,9,2)
            l(9,0,9,4);l(9,14,9,18);l(0,9,4,9);l(14,9,18,9)
        elseif kind=='reply' then
            l(2,2,16,2);l(16,2,16,13);l(16,13,8,13);l(8,13,3,17);l(3,17,3,13);l(3,13,2,13);l(2,13,2,2)
            l(6,7,12,7);l(6,7,9,4);l(6,7,9,10)
        elseif kind=='keyboard' then
            l(1,4,17,4);l(17,4,17,15);l(17,15,1,15);l(1,15,1,4)
            for row=0,1 do for col=0,3 do l(4+col*3,7+row*3,4.5+col*3,7+row*3)end end
            l(6,13,12,13)
        elseif kind=='megaphone' then
            l(2,7,6,7);l(6,7,13,3);l(13,3,13,15);l(13,15,6,11);l(6,11,2,11);l(2,11,2,7)
            l(5,11,6,17);l(6,17,9,17);l(9,17,8,12);l(16,6,18,5);l(16,9,18,9);l(16,12,18,13)
        elseif kind=='entry' then
            l(3,6,3,2);l(3,2,13,2);l(13,2,13,16);l(13,16,3,16);l(3,16,3,12)
            l(0,9,9,9);l(6,6,9,9);l(9,9,6,12);l(16,6,18,9);l(18,9,16,12)
        elseif kind=='home' then
            l(1,8,9,1); l(9,1,17,8); l(4,7,4,17); l(4,17,14,17); l(14,17,14,7); l(8,17,8,11)
        elseif kind=='chart' then
            l(2,17,17,17); l(4,13,4,9); l(9,13,9,3); l(14,13,14,6)
        elseif kind=='shield' then
            l(2,3,9,1); l(9,1,16,3); l(2,3,3,12); l(3,12,9,17); l(9,17,15,12); l(15,12,16,3); l(6,8,8,10); l(8,10,12,6)
        elseif kind=='eye' then
            l(1,9,5,4); l(5,4,13,4); l(13,4,17,9); l(17,9,13,14); l(13,14,5,14); l(5,14,1,9); l(9,7,9,11)
        elseif kind=='users' then
            l(6,2,11,2); l(11,2,11,7); l(11,7,6,7); l(6,7,6,2); l(2,17,2,12); l(2,12,15,12); l(15,12,15,17)
        elseif kind=='settings' then
            for i=0,2 do l(1,3+i*6,17,3+i*6) end
            l(5,1,5,5); l(12,7,12,11); l(7,13,7,17)
        elseif kind=='tools' then
            l(2,2,16,16); l(16,2,2,16); l(11,1,16,1); l(16,1,17,6)
        elseif kind=='help' then
            l(5,4,5,2); l(5,2,13,2); l(13,2,13,7); l(13,7,9,10); l(9,10,9,12); l(9,16,9,17)
        elseif kind=='power' then
            l(9,1,9,9);l(4,4,2,7);l(2,7,2,13);l(2,13,6,17);l(6,17,12,17);l(12,17,16,13);l(16,13,16,7);l(16,7,14,4)
        elseif kind=='save' then
            l(2,2,14,2);l(14,2,17,5);l(17,5,17,17);l(17,17,2,17);l(2,17,2,2)
            l(6,2,6,7);l(6,7,12,7);l(12,7,12,2);l(6,16,6,11);l(6,11,13,11);l(13,11,13,16)
        elseif kind=='motion' then
            l(3,9,15,9);l(9,3,9,15);l(5,5,13,13);l(13,5,5,13)
        else
            for i=0,2 do l(5,3+i*6,17,3+i*6); l(1,3+i*6,2,3+i*6) end
        end
    end
    function ui.chevron(x,y,c)
        ui.line(x,y,x+5,y+5,c,1.7); ui.line(x+5,y+5,x,y+10,c,1.7)
    end
    -- Compact vector adaptation of the Advance RolePlay mark: sharp at HUD
    -- scale, with no opaque favicon tile or extra texture to load.
    function ui.advanceMark(x,y)
        local function vertex(a,b) return point(x+a/8,y+b/8) end
        local function triangle(a,b,c,d,e,f)
            draw:AddTriangleFilled(vertex(a,b),vertex(c,d),vertex(e,f),color(p.text))
        end
        local function arc(first,last,radius)
            local previous
            for i=0,24 do
                local angle=math.rad(first+(last-first)*i/24)
                local current=vertex(104+math.cos(angle)*radius,99+math.sin(angle)*radius)
                if previous then draw:AddLine(previous,current,color(0xF3CB58),1.6) end
                previous=current
            end
        end
        arc(-103,-194,59); arc(124,48,52)
        triangle(123,13,113,64,27,147)
        triangle(113,64,89,101,27,147)
        triangle(123,13,147,125,113,64)
        triangle(147,125,121,129,113,64)
        triangle(67,107,166,79,160,101)
        triangle(67,107,160,101,27,147)
        triangle(134,76,148,62,155,70)
        triangle(134,76,155,70,145,82)
    end
    function ui.image(name,x,y,w,h,radius,tint)
        local art=rt.art:get(name)
        if not art then return end
        local cropW,cropH=1,1
        local target=w/h; local aspect=art.width/art.height
        if aspect>target then cropW=target/aspect else cropH=aspect/target end
        local u0,v0=(1-cropW)/2,(1-cropH)/2
        local function strip(left,top,right,bottom)
            draw:AddImage(art.texture,point(x+left,y+top),point(x+right,y+bottom),
                g.ImVec2(u0+left/w*cropW,v0+top/h*cropH),g.ImVec2(u0+right/w*cropW,v0+bottom/h*cropH),tint or 0xFFFFFFFF)
        end
        local r=math.min(radius or 0,h/2,w/2)
        if r==0 then strip(0,0,w,h); return true end
        strip(0,r,w,h-r)
        for i=0,r-1 do
            local inset=r-math.sqrt(r*r-(r-i-0.5)^2)
            strip(inset,i,w-inset,i+1); strip(inset,h-i-1,w-inset,h-i)
        end
        return true
    end
    function ui.ambient(x,y,w,h,time,variant)
        if variant and variant>0 then
            local appearance=rt:service('appearance.lua')
            local tint=rt.theme.color(g,appearance.colors[variant])
            -- Bounded particles remain behind the controls and follow the selected artwork.
            for i=1,16 do
                local phase=(time*(variant==2 and .035 or .012)+i*.618)%1
                local px,py
                if variant==2 then px=(i*.173)%1;py=1-phase*.65
                elseif variant==3 then px=.55+.35*math.sin(i*2.4+time*.08);py=.70+.23*math.cos(i+time*.06)
                elseif variant==4 then px=phase;py=.80+.13*math.sin(phase*6.28+i)
                elseif variant==5 then px=.73+.23*math.cos(phase*6.28);py=.75+.19*math.sin(phase*6.28)
                else px=phase;py=.79+.13*math.sin(phase*5+i*.4) end
                tint.w=.10+.15*(.5+.5*math.sin(time+i))
                local pos=point(x+w*px,y+h*py)
                draw:AddCircleFilled(pos,3,g.GetColorU32(tint),10)
                tint.w=tint.w*1.8
                draw:AddCircleFilled(pos,1,g.GetColorU32(tint),8)
            end
            return
        end
        -- A bounded, non-interactive orbit. No timers, threads or per-frame I/O.
        local tint=rt.theme.color(g,p.accent);tint.w=0.16
        local previous
        for i=0,32 do
            local angle=math.pi*(0.12+i/32*0.83)
            local current=point(x+w*(0.66+0.32*math.cos(angle)),y+h*(0.90-0.23*math.sin(angle)))
            if previous then draw:AddLine(previous,current,g.GetColorU32(tint),1) end
            previous=current
        end
        for i=1,5 do
            local angle=math.pi*(0.12+((time*0.012+i/5)%1)*0.83)
            local pos=point(x+w*(0.66+0.32*math.cos(angle)),y+h*(0.90-0.23*math.sin(angle)))
            tint.w=0.12;draw:AddCircleFilled(pos,5,g.GetColorU32(tint),12)
            tint.w=0.38;draw:AddCircleFilled(pos,1.4,g.GetColorU32(tint),8)
        end
    end
    function ui.avatar(x,y,r)
        rt.avatar:draw(draw,origin.x+x,origin.y+y,r,color(p.surface),color(p.accent))
    end
    function ui.action(id,x,y,w,title,caption,icon,fn)
        local clicked,hover=ui.hit(id,x,y,w,76)
        ui.rect(x,y,w,76,hover and p.hover or p.surface,12)
        ui.rect(x+16,y+20,36,36,p.selection,10)
        ui.icon(icon,x+25,y+29,p.accent)
        ui.text(x+68,y+16,title,18,p.text,w-98,true)
        ui.text(x+68,y+44,caption,14,p.muted,w-86)
        ui.chevron(x+w-25,y+28,p.accent)
        if clicked then fn() end
    end
    function ui.buttonHeight(w,label)
        local scale=rt.preferences.data.main.scale or 1
        return math.max(32*scale,ui.measure(label,16,math.max(1,w-24*scale),true)+16*scale)
    end
    function ui.button(id,x,y,w,label,primary,fn)
        local scale=rt.preferences.data.main.scale or 1
        local h=ui.buttonHeight(w,label)
        local clicked,hover=ui.hit(id,x,y,w,h)
        ui.rect(x,y,w,h,primary and (hover and p.text or p.accent) or (hover and p.hover or p.button),5*scale)
        ui.text(x+12*scale,y+8*scale,label,16,primary and p.bg or p.text,w-24*scale,true)
        if clicked then fn() end
        return h
    end
    return ui
end

local function keyName(value)
    if type(value)~='string' then return '-' end
    return value:gsub('^VK_',''):gsub('LEFT','Left'):gsub('RIGHT','Right'):gsub('CONTROL','Ctrl'):gsub('MENU','Alt')
end

local function profile(rt)
    local api=rt.api
    local name,id='Игрок',nil
    if api.sampGetPlayerIdByCharHandle and api.PLAYER_PED then
        local ok,value=api.sampGetPlayerIdByCharHandle(api.PLAYER_PED)
        if ok then
            id=value
            if api.sampGetPlayerNickname then name=api.sampGetPlayerNickname(id) or name end
        end
    end
    local connected=api.isSampAvailable and api.isSampAvailable() and api.sampGetGamestate()==3
    return name,id,connected
end

local function dashboard(rt,ui,w,h)
    local p,g=rt.theme.palette,rt.imgui
    local scale=rt.preferences.data.main.scale or 1
    -- The generated frame occupies the outer 18 px. Keep every control inside it.
    local gap,pad=16*scale,30*scale
    local wide=w>=656*scale
    local leftW=wide and math.floor(math.min((w-gap)*0.62,w-gap-320*scale)) or w
    local rightW=wide and w-leftW-gap or w
    rt.homeSearch=rt.homeSearch or g.ImBuffer(128)
    local controls={}
    local core={}
    for _,item in ipairs(rt.homeControls or {}) do core[item.id]=item end
    local function addCore(id) if core[id] and (id~='skin_changer' or rt.access:can(4)) then controls[#controls+1]=core[id] end end
    local function addFeature(key,label)
        controls[#controls+1]={label=label,get=function() return rt.preferences.data.main[key] end,
            set=function(value) rt:setFeature(key,value) end}
    end
    local function addModule(id,key,label)
        if not rt.access:can(rt:service('permissions.lua').modules[id] or 1) then return end
        local m=rt.modules[id]
        if m and m.enabled and m.bridge and m.bridge.homeGet and m.bridge.homeSet then
            controls[#controls+1]={label=label,
                get=function() return rt:call(m,m.bridge.homeGet,key)==true end,
                set=function(value) rt:call(m,m.bridge.homeSet,key,value) end}
        end
    end
    addModule('adminzone','automatic','Телепорт в AdminZone при входе (/az)')
    addCore('autoLoginStatus')
    addFeature('families','Семейные функции')
    addFeature('ghetto','Гетто функции')
    addFeature('streamer','Режим стримера')
    addCore('skin_changer')
    addModule('mask_names','enabled','Свой цвет ников в маске')
    addModule('capture','skeletalBool','Показывать скелеты игроков')
    addModule('capture','customNametagsBool','Использовать свои подписи и полоски здоровья')
    addModule('capture','longRangeLabelsBool','Показывать 3D текст на большом расстоянии')
    local function match(label,query)
        local encoding=rt.api.require('encoding').UTF8
        local function lower(value)
            return tostring(encoding:decode(value)):lower():gsub('['..string.char(192)..'-'..string.char(223)..']',function(ch) return string.char(ch:byte()+32) end):gsub(string.char(168),string.char(184))
        end
        return lower(label):find(lower(query),1,true)~=nil
    end
    local query=tostring(rt.homeSearch.v or ''):match('^%s*(.-)%s*$')
    if query~=''then
        for _,binding in ipairs(rt.keys.order)do
            if match(binding.label,query)then controls[#controls+1]={label=binding.label..' · Горячие клавиши',open=function()rt:openSettings('keys')end}end
        end
        for _,entry in ipairs(rt:service('settings_index.lua'))do
            local target=entry
            local destination=({autostart='autostart',tempfamily='templeader_window',environment='environment',beautifulsky='environment',observer_extras='observer_extras'})[target.source]
            local page=target.source=='tpm' and 'teleport' or (target.page=='core' and target.tab==3 and not destination) and 'gameplay' or target.page
            local section=page=='teleport' and 'Телепорт' or page=='gameplay' and 'Игровые функции' or destination=='environment' and 'Локальные время и погода' or entry.section
            if match(entry.label..' '..section,query)then
                controls[#controls+1]={label=entry.label..' · '..section,open=function()
                    rt:open(page);rt.moduleMode=destination and 'functions' or 'settings'
                    if destination then rt.toolTarget=destination
                    elseif page=='core' and target.tab>0 then rt.coreSettingsTab=target.tab end
                    if page=='teleport' then
                        local search=rt:service('teleport_search.lua')
                        search.category=7;search.query=''
                        if search.buffer then search.buffer.v=''end
                    end
                    rt.restoreWorkspaceScroll=0
                end}
            end
        end
    end
    local leftInner=leftW-2*pad
    local titleH=ui.measure('ПОЛЕЗНЫЕ ФУНКЦИИ',16,leftInner,true)
    local searchY=pad+titleH+12*scale
    -- MoonImGui does not expose GetFrameHeight; use the same font/padding formula.
    local inputH=math.max(32*scale,g.GetTextLineHeight()+2*g.GetStyle().FramePadding.y)
    local rowsY=searchY+inputH+12*scale
    local rows={};local leftContentEnd=rowsY
    for _,item in ipairs(controls) do if match(item.label,tostring(rt.homeSearch.v or '')) then
        local rh=math.max(32*scale,ui.measure(item.label,16,leftW-2*pad-40*scale)+12*scale)
        rows[#rows+1]={item=item,height=rh};leftContentEnd=leftContentEnd+rh+4*scale
    end end
    if #rows==0 then leftContentEnd=leftContentEnd+ui.measure('Настройки не найдены',16,leftInner)+16*scale end
    local settingsY=leftContentEnd+8*scale
    local leftH=settingsY+ui.buttonHeight(leftInner,'Все настройки')+pad
    ui.panel(0,0,leftW,leftH)
    ui.text(pad,pad,'ПОЛЕЗНЫЕ ФУНКЦИИ',16,p.accent,leftInner,true)
    -- Keep the editor in its own native child, separate from manually placed cards.
    g.SetCursorPos(g.ImVec2(pad,searchY))
    g.PushStyleVar(g.StyleVar.WindowPadding,g.ImVec2(0,0))
    g.BeginChild('home_search_editor',g.ImVec2(leftInner,inputH),false,g.WindowFlags.NoScrollbar+g.WindowFlags.NoScrollWithMouse)
    g.PushItemWidth(math.max(1,leftInner-2))
    if g.IsWindowHovered() and g.IsMouseClicked(0) then g.SetKeyboardFocusHere() end
    g.InputText('##home_search',rt.homeSearch)
    if g.IsItemHovered() then g.SetTooltip('Поиск настроек: введите название') end
    g.PopItemWidth();g.EndChild();g.PopStyleVar()
    local y=rowsY
    for _,row in ipairs(rows) do
        local item=row.item;g.SetCursorPos(g.ImVec2(pad,y))
        if item.open then
            if g.Selectable(rt:service('ui_components.lua').wrap(g,item.label,leftW-2*pad-12*scale)..'##home_result_'..tostring(y),false,0,g.ImVec2(leftW-2*pad,row.height))then item.open()end
        else
            local value=g.ImBool(item.get())
            if rt:service('ui_components.lua').checkbox(g,item.label..'##home',value,scale,leftW-2*pad) then item.set(value.v) end
        end
        y=y+row.height+4*scale
    end
    if #rows==0 then ui.text(pad,y,'Настройки не найдены',16,p.muted,leftW-2*pad);y=y+48*scale end
    ui.button('home_settings',pad,settingsY,leftInner,'Все настройки',false,function() rt.page,rt.settingsPage='settings','core' end)
    local rx,ry=wide and leftW+gap or 0,wide and 0 or leftH+gap
    local name,id,connected=profile(rt);name=name:gsub('_',' ')
    local server=connected and (rt.api.sampGetCurrentServerName and rt.api.sampGetCurrentServerName() or 'Advance RolePlay') or 'Нет подключения'
    server=tostring(server):gsub('{%x%x%x%x%x%x}',''):match('^[^|]+') or 'Advance RolePlay'
    server=server:match('^%s*(.-)%s*$')
    local nameH=ui.measure(name,18,rightW-120*scale,true)
    local serverH=ui.measure(server,14,rightW-120*scale)
    local metadata=id and ('ID '..id..' · Уровень '..tostring(rt.access:displayLevel() or '—'))or 'Ожидание входа'
    local infoWidth=rightW-120*scale
    local badgeH=math.max(26*scale,ui.measure(metadata,13,infoWidth-16*scale)+10*scale)
    local profileH=math.max(142*scale,64*scale+nameH+serverH+badgeH)
    ui.profileFrame(rx,ry,rightW,profileH,scale)
    ui.avatar(rx+50*scale,ry+profileH/2,34*scale)
    ui.rect(rx+72*scale,ry+profileH/2+23*scale,12*scale,12*scale,p.bg,6*scale)
    ui.rect(rx+75*scale,ry+profileH/2+26*scale,6*scale,6*scale,connected and p.green or p.muted,3*scale)
    local px,py=rx+98*scale,ry+18*scale
    py=py+ui.text(px,py,'ПРОФИЛЬ X-TOOLS',11,p.accent,infoWidth,true)+7*scale
    py=py+ui.text(px,py,name,18,p.text,infoWidth,true)+5*scale
    py=py+ui.text(px,py,server,14,p.muted,infoWidth)+10*scale
    ui.rect(px,py,infoWidth,badgeH,p.selection,5*scale)
    ui.text(px+8*scale,py+5*scale,metadata,13,p.text,infoWidth-16*scale)
    ry=ry+profileH+gap
    local schedule=rt:service('schedule.lua');local timestamp=rt.api.os.time()
    local upcoming=rt.schedule:nextEvents(timestamp,true)
    local rightInner=rightW-2*pad
    local eventRowsY=pad+ui.measure('БЛИЖАЙШИЕ СОБЫТИЯ · МСК',14,rightInner,true)+16*scale
    local eventsEnd=eventRowsY
    for i=1,math.min(2,#upcoming) do
        local row=upcoming[i]
        eventsEnd=eventsEnd+ui.measure(row.name,16,rightInner,true)+4*scale+
            ui.measure(row.time..' · '..schedule.countdown(row.seconds),14,rightInner)+16*scale
    end
    if #upcoming==0 then eventsEnd=eventsEnd+ui.measure('Нет включённых событий',14,rightInner)+16*scale end
    local eventsH=eventsEnd+ui.buttonHeight(rightInner,'Расписание и редактор')+pad
    ui.panel(rx,ry,rightW,eventsH)
    ui.text(rx+pad,ry+pad,'БЛИЖАЙШИЕ СОБЫТИЯ · МСК',14,p.accent,rightInner,true)
    local ey=ry+eventRowsY
    for i=1,math.min(2,#upcoming) do
        local row=upcoming[i]
        ey=ey+ui.text(rx+pad,ey,row.name,16,p.text,rightW-2*pad,true)+4*scale
        ey=ey+ui.text(rx+pad,ey,row.time..' · '..schedule.countdown(row.seconds),14,p.muted,rightW-2*pad)+16*scale
    end
    if #upcoming==0 then ui.text(rx+pad,ey,'Нет включённых событий',14,p.muted,rightW-2*pad) end
    ui.button('home_schedule',rx+pad,ry+eventsEnd,rightInner,'Расписание и редактор',false,function() rt:open('schedule') end)
    ry=ry+eventsH+gap
    local keyRows={}
    local keyRowsY=pad+ui.measure('ГОРЯЧИЕ КЛАВИШИ',14,rightInner,true)+16*scale
    local keysEnd=keyRowsY
    local keyWidth=math.min(112*scale,rightInner*.36)
    local keyGap=12*scale
    local keyLabelWidth=rightInner-keyWidth-keyGap
    for _,item in ipairs(rt.keys.order) do
        if #keyRows<4 and rt.keys.data[item.id].key>0 and (not item.active or item.active()) then
            local key=rt.keys:name(item.id)
            local rowH=math.max(32*scale,ui.measure(item.label,14,keyLabelWidth)+12*scale,ui.measure(key,14,keyWidth-12*scale)+12*scale)
            keyRows[#keyRows+1]={key=key,label=item.label,height=rowH};keysEnd=keysEnd+rowH+4*scale
        end
    end
    keysEnd=keysEnd+8*scale
    local keysH=keysEnd+ui.buttonHeight(rightInner,'Все горячие клавиши')+pad
    ui.panel(rx,ry,rightW,keysH)
    ui.text(rx+pad,ry+pad,'ГОРЯЧИЕ КЛАВИШИ',14,p.accent,rightInner,true)
    local ky=ry+keyRowsY
    for _,row in ipairs(keyRows) do
        ui.rect(rx+pad,ky,keyWidth,row.height,p.button,3*scale)
        ui.text(rx+pad+6*scale,ky+6*scale,row.key,14,p.text,keyWidth-12*scale,true)
        ui.text(rx+pad+keyWidth+keyGap,ky+6*scale,row.label,14,p.text,keyLabelWidth)
        ky=ky+row.height+4*scale
    end
    ui.button('home_keys',rx+pad,ry+keysEnd,rightInner,'Все горячие клавиши',false,function() rt.page,rt.settingsPage='settings','keys' end)
    local zone=rt.modules.adminzone
    if zone and zone.enabled and zone.bridge and rt.access:can(3) then
        local zoneH=ui.zoneButton('home_adminzone',rx+pad,ry+keysH+8*scale,math.min(300*scale,rightW-2*pad),function()
            rt:call(zone,zone.bridge.enter)
        end)
        keysH=keysH+zoneH+16*scale

    end
    local bottom=(wide and leftH or ry+keysH)+gap
    local appearanceW=wide and leftW or w
    local appearanceH=320*scale
    ui.panel(0,bottom,appearanceW,appearanceH)
    ui.text(pad,bottom+pad,'ОФОРМЛЕНИЕ',14,p.accent,appearanceW-2*pad,true)
    local appearanceTop=bottom
    bottom=bottom+pad+30*scale
    local appearance=rt:service('appearance.lua')
    local preferences=rt.preferences.data.main
    g.SetCursorPos(g.ImVec2(pad,bottom))
    g.BeginChild('home_appearance_controls',g.ImVec2(appearanceW-2*pad,appearanceH-2*pad-30*scale),false)
    g.PushItemWidth(math.max(120,math.min(280*scale,appearanceW-90*scale)))
    local selected=g.ImInt(preferences.pendingThemeStyle or preferences.themeStyle or 0)
    if g.Combo('Тема',selected,appearance.choices())then
        preferences.pendingThemeStyle=selected.v~=preferences.themeStyle and selected.v or nil;rt.preferences:save()
    end
    g.PopItemWidth()
    g.TextWrapped('Тема объединяет логотип, фон, цвета интерфейса и уведомлений.')
    local wallpaper=g.ImBool(preferences.wallpaper~=false)
    if g.Checkbox('Фоновое изображение',wallpaper)then preferences.wallpaper=wallpaper.v;rt.preferences:save()end
    local motion=g.ImBool(preferences.motion~=false)
    if g.Checkbox('Анимация фона',motion)then preferences.motion=motion.v;rt.preferences:save()end
    g.PushItemWidth(math.max(120,math.min(280*scale,appearanceW-90*scale)))
    local font=g.ImInt((preferences.pendingFont or preferences.font)-1)
    if g.Combo('Шрифт',font,rt.typography:choices())then preferences.pendingFont=font.v+1~=preferences.font and font.v+1 or nil;rt.preferences:save()end
    g.TextWrapped('Тема и шрифт применяются после перезапуска игры.')
    if preferences.pendingThemeStyle~=nil or preferences.pendingFont~=nil then g.TextWrapped('Изменения сохранены. Ожидается перезапуск игры.')end
    g.PopItemWidth()
    g.EndChild()
    bottom=appearanceTop+appearanceH+gap
    g.SetCursorPos(g.ImVec2(0,math.max(bottom,ry+keysH)));g.Dummy(g.ImVec2(1,1))
end

local function drawCore(rt,callback,panel,level)
    local g=rt.imgui
    rt:selectCorePanel(panel)
    if level and not rt.access:can(level) then
        g.TextWrapped(rt.access:level()==nil and 'Уровень администратора пока не подтверждён сервером.' or 'Доступно с '..level..' уровня администратора.')
        return
    end
    rt.embeddedCore=true
    g.PushItemWidth(math.max(160,math.min(360,g.GetContentRegionAvailWidth()-40)))
    local ok,err=xpcall(callback,debug.traceback)
    g.PopItemWidth()
    rt.embeddedCore=false
    if not ok then error(err) end
end

local function modulePage(rt,id,settingsPage,method)
    if rt.access:displayLevel()=='S1' and not rt:featureAllowed(id) then return end
    local policy=rt:service('permissions.lua')
    local minimum=policy.pages[id] or policy.modules[id] or 1
    if rt.access:displayLevel()~='S1' and not rt.access:can(minimum) then rt.imgui.TextDisabled('Доступно с '..minimum..' уровня администратора.');return end
    local m=rt.modules[id]
    local fn=m and m.bridge and m.bridge[method or (settingsPage and 'drawSettings' or 'draw')]
    if m and m.enabled and fn then rt:call(m,fn)
    else
        rt.imgui.TextWrapped('Этот раздел не загрузился. Проверьте состояние: /atmodules.')
        if rt.imgui.Button('Как устранить ошибку##module_help') then rt:openHelp('troubleshooting') end
    end
end

local function tabs(rt,items,value,suffix)
    local g,p=rt.imgui,rt.theme.palette
    local width=g.GetContentRegionAvailWidth()
    local used=0
    for i,item in ipairs(items) do
        local label=item[1]
        local scale=rt.preferences.data.main.scale or 1
        local size=math.min(width,g.CalcTextSize(label).x+24*scale)
        if i>1 and used+size+8<=width then g.SameLine(); used=used+8 else used=0 end
        local active=value==i
        if active then g.PushStyleColor(g.Col.Button,rt.theme.color(g,p.selection)); g.PushStyleColor(g.Col.Text,rt.theme.color(g,p.accent)) end
        if g.Button(label..suffix,g.ImVec2(size,32*scale)) then value=i; g.SetScrollY(0) end
        if active then g.PopStyleColor(2) end
        used=used+size
    end
    g.Spacing()
    return value
end

local function drawGameplay(rt,callback)
    local g=rt.imgui
    _G.selected=3;drawCore(rt,callback,'settings_window')
    if rt.access:displayLevel()=='S1' then
        for _,id in ipairs({'movement','airbreak','broom','mask_names','zone_wall','death_effect','fisheye','fogdist','speed_boost','adm_tab'}) do modulePage(rt,id,true) end
        return
    end
                    local lego=g.ImBool(rt.preferences.data.main.legoReplace==true)
                    if g.Checkbox('Заменять /lego автоматически',lego) then rt.preferences.data.main.legoReplace=lego.v;rt.preferences:save() end
                    modulePage(rt,'movement',true);modulePage(rt,'airbreak',true);modulePage(rt,'broom',true);modulePage(rt,'mask_names',true)
                    modulePage(rt,'rvanka_warning',true)
                    modulePage(rt,'zone_wall',true)
                    modulePage(rt,'death_effect',true)
                    modulePage(rt,'fisheye',true);modulePage(rt,'fogdist',true)
                    
                    modulePage(rt,'speed_boost',true)
                    modulePage(rt,'clickwarp',true)
                    modulePage(rt,'adm_tab',true)
                    local capture=rt.modules.capture
                    if capture and capture.bridge.drawVisualSettings then rt:call(capture,capture.bridge.drawVisualSettings) end

end

local function drawModule(rt,callback,spec)
    local g=rt.imgui
    local module=rt.modules[spec[1]]
    if rt.access:displayLevel()=='S1' and spec[1]=='core' then
        rt.s1Tab=tabs(rt,{{'Локальная погода'},{'Клавиши'},{'Оформление чата'}},rt.s1Tab or 1,'##s1_tools')
        if rt.s1Tab==1 then modulePage(rt,'environment',true)
        elseif rt.s1Tab==2 then rt.keys:drawAll(g)
        else modulePage(rt,'chat_copy',true);modulePage(rt,'chat_appearance',true) end
        return
    end
    if spec[1]=='adm' and module and module.bridge then
        local entries={{'Настройки'},{'Админы'},{'Лидеры'},{'Друзья'}}
        if rt.access:can(3)then entries[5]={'Чистый онлайн'}elseif module.bridge.directoryPage==5 then module.bridge.directoryPage=2 end
        local current=rt.moduleMode=='settings' and 1 or (module.bridge.directoryPage or 2)
        local choice=tabs(rt,entries,current,'##checker_top')
        rt.moduleMode=choice==1 and 'settings' or 'functions'
        if choice>1 then module.bridge.directoryPage=choice end
        module.bridge.externalNavigation=true;modulePage(rt,'adm',choice==1);module.bridge.externalNavigation=false
        return
    end
    if spec[1]=='capture' or spec[1]=='familia' then
        local key=spec[1]=='capture' and 'ghetto' or 'families'
        local enabled=g.ImBool(rt.preferences.data.main[key])
        if g.Checkbox('Включить '..(key=='ghetto' and 'функции гетто' or 'семейные функции'),enabled) then rt:setFeature(key,enabled.v) end
        if not enabled.v then g.TextDisabled('Включите раздел для доступа к его функциям.');return end
    end
    if spec[1]=='familia' then
        modulePage(rt,'family_mask_warning',false)
        modulePage(rt,'family_weapon_warning',false)
        modulePage(rt,'familia',false,'drawTimerSettings')
        rt.familyPage=tabs(rt,{{'Семейные функции'},{'Реестр семей'},{'Discord'}},rt.familyPage or 1,'##family_sections')
        if rt.familyPage==2 then modulePage(rt,'family_registry',false);return end
        if rt.familyPage==3 then modulePage(rt,'family_registry',false,'drawDiscord');return end
    end
    local hasSettings=spec[1]=='core' or spec[1]~='bullet' and module and module.bridge and module.bridge.drawSettings
    local mode=rt.moduleMode=='settings' and hasSettings and 2 or 1
    if hasSettings then mode=tabs(rt,{{'Функции'},{'Настройки'}},mode,'##module_mode') end
    rt.moduleMode=mode==2 and 'settings' or 'functions'
    if spec[1]=='core' then
        if mode==2 then
            local tab=rt.coreSettingsTab==4 and 3 or rt.coreSettingsTab or 1
            rt.coreSettingsTab=({1,2,4})[tabs(rt,{{'Основные'},{'Клавиши'},{'Чат'}},tab,'##core_settings')]
            _G.selected=rt.coreSettingsTab
            if rt.coreSettingsTab==2 then rt.keys:drawAll(g)
            else
                drawCore(rt,callback,'settings_window')
                g.Separator()
                if rt.coreSettingsTab==1 then
                    rt.clock:draw(g)
                    local roadFollowup=g.ImBool(rt.preferences.data.main.roadFollowup==true)
                    if g.Checkbox('«Из воды» в меню: подбросить игрока и обновить слежку',roadFollowup) then rt.preferences.data.main.roadFollowup=roadFollowup.v;rt.preferences:save() end
                    local streamer=g.ImBool(rt.preferences.data.main.streamer)
                    if g.Checkbox('Режим стримера: скрывать IP',streamer) then rt.preferences.data.main.streamer=streamer.v;rt.preferences:save() end
                    if g.CollapsingHeader('Чистый онлайн') then modulePage(rt,'online',false);modulePage(rt,'online',true) end
                elseif rt.coreSettingsTab==4 then
                    modulePage(rt,'correction',true)
                    modulePage(rt,'chat_copy',true)
                    modulePage(rt,'chat_appearance',true)
                    local chatN=g.ImBool(rt.preferences.data.main.spectateChatN)
                    if g.Checkbox('Общение в слежке через /n',chatN) then rt.preferences.data.main.spectateChatN=chatN.v;rt.preferences:save() end
                    local invisibleChat=g.ImBool(rt.preferences.data.main.invisibleChatN)
                    if g.Checkbox('Общаться через /n в инвизе',invisibleChat) then rt.preferences.data.main.invisibleChatN=invisibleChat.v;rt.preferences:save() end
                    for _,item in ipairs({{'killidsKiller','ID убийцы в списке убийств'},{'killidsVictim','ID погибшего в списке убийств'}}) do
                        local ids=g.ImBool(rt.preferences.data.main[item[1]])
                        if g.Checkbox(item[2],ids) then rt:setFeature(item[1],ids.v) end
                    end
                end
            end
        else
            local choices={}
            for _,item in ipairs(tools) do choices[#choices+1]=item end
            choices[#choices+1]={'Статистика','statistic_window'}
            choices[#choices+1]={'Локальные время и погода','environment'}
            choices[#choices+1]={'Команды при старте','autostart'}
            choices[#choices+1]={'Варнинги','observer_extras'}
            if rt.access:can(4) then choices[#choices+1]={'Скиллы на оружие','weapon_skills'} end
            if rt.toolTarget then
                for index,choice in ipairs(choices)do if choice[2]==rt.toolTarget then rt.toolPage=index;break end end
                rt.toolTarget=nil
            end
            rt.toolPage=tabs(rt,choices,math.max(1,math.min(#choices,rt.toolPage or 1)),'##tool')
            local item=choices[rt.toolPage]
            if item[2]=='environment' then modulePage(rt,'environment',true)
            elseif item[2]=='observer_extras' then modulePage(rt,'observer_extras',false)
            elseif item[2]=='autostart' then modulePage(rt,'autostart',false)
            elseif item[2]=='weapon_skills' then modulePage(rt,'weapon_skills',false)

            else
                if item[2]=='templeader_window' then g.Text('Временное лидерство и работа');g.Separator()end
                if item[2]=='teleportation_window' and rt.access:can(3) then
                    modulePage(rt,'adminzone',false);g.Spacing();g.Separator()
                end
                drawCore(rt,callback,item[2],item[3])
                if item[2]=='templeader_window' then
                    g.Spacing();g.Separator();g.Text('Временная семья')
                    modulePage(rt,'tempfamily',false)
                end
                if item[2]=='teleportation_window' then modulePage(rt,'tpm',false) end
            end
        end
    elseif module and module.bridge and module.bridge[mode==2 and 'drawSettings' or 'draw'] then
        modulePage(rt,spec[1],mode==2)
        if spec[1]=='capture' or spec[1]=='familia' then
            if spec[1]=='capture' and mode==2 then g.Separator();modulePage(rt,'gang',true) end
            g.Separator()
            local key=spec[1]=='capture' and 'ghetto' or 'families'
            local checked=g.ImBool(rt.preferences.data.main.medkitMode==key)
            if g.Checkbox('Контроль аптечек: '..(key=='ghetto' and 'банды' or 'семьи'),checked) then
                rt.preferences.data.main.medkitMode=checked.v and key or 'none';rt.preferences:save()
                local m=rt.modules.stopsbiv;if m then rt:call(m,m.bridge.onDisconnect) end
            end
            if checked.v then modulePage(rt,'stopsbiv',mode==2) end
        end
    else
        g.TextWrapped(spec[3])
        
    end
end

function Workspace.draw(rt,callback)
    local g,p=rt.imgui,rt.theme.palette
    rt.settingsPage=rt.settingsPage or 'core'
    if rt.page=='statistics' then rt.page,rt.toolPage,rt.moduleMode='core',4,'functions' end
    if rt.page=='settings' and rt.settingsPage~='system' then
        local coreSection={core=1,keys=2,utilities=3,chat=4,menu=3,online=1,environment=1}
        if rt.settingsPage=='gang' or rt.settingsPage=='stopsbiv' then rt.settingsPage=rt.preferences.data.main.medkitMode=='families' and 'familia' or 'capture' end
        if rt.settingsPage=='aegis' or rt.settingsPage=='adm' then rt:openSettings(rt.settingsPage);rt.settingsPage='system' end
        local target=coreSection[rt.settingsPage] and 'core' or rt.settingsPage
        if moduleById(target) then
            rt.page,rt.moduleMode=target,'settings'
            if coreSection[rt.settingsPage] then rt.coreSettingsTab=coreSection[rt.settingsPage] end
        end
    end
    if rt.page=='core' and rt.moduleMode=='settings' and rt.coreSettingsTab==3 then rt.page='gameplay';rt.coreSettingsTab=1 end
    local preferences=rt.preferences.data.main
    local scale=preferences.scale or 1
    local accent=rt.preferences.colors[preferences.color] or rt.preferences.colors[1]
    rt.theme.apply(accent[2])
    local colorCount,varCount=rt.theme.push(g,scale)
    local sw,sh=rt.api.getScreenResolution()
    -- All workspace pages share the home geometry; modules only draw content.
    local width,height,x,y=rt:service('window_geometry.lua').resolve(preferences,sw,sh)
    local changedScreen=rt.uiScreenW~=sw or rt.uiScreenH~=sh
    local resetGeometry=rt.uiResetGeometry==true or rt.preferences.windowPresetPending==true
    local condition=(changedScreen or resetGeometry) and g.Cond.Always or g.Cond.FirstUseEver
    g.SetNextWindowSize(g.ImVec2(width,height),condition)
    g.SetNextWindowPos(g.ImVec2(x,y),condition)
    if g.SetNextWindowSizeConstraints then g.SetNextWindowSizeConstraints(g.ImVec2(math.min(sw-24,480*scale),math.min(sh-32,360*scale)),g.ImVec2(sw-24,sh-32)) end
    rt.uiScreenW,rt.uiScreenH=sw,sh
    local flags=g.WindowFlags.NoTitleBar+g.WindowFlags.NoScrollbar+g.WindowFlags.NoScrollWithMouse
    g.Begin('X-Tools###CasualTool##workspace-v4',_G.show_main_window,flags)
    local actual=g.GetWindowSize();width,height=actual.x,actual.y
    if not changedScreen and not resetGeometry and rt.uiActualWidth and
        (math.abs(width-rt.uiActualWidth)>1 or math.abs(height-rt.uiActualHeight)>1) then preferences.windowManual=true end
    rt.uiActualWidth,rt.uiActualHeight=width,height
    rt.uiResetGeometry=false
    rt.preferences.windowPresetPending=false
    local position=g.GetWindowPos()
    if not changedScreen and not resetGeometry and rt.uiActualX and
        (math.abs(position.x-rt.uiActualX)>1 or math.abs(position.y-rt.uiActualY)>1) then preferences.windowMoved=true end
    rt.uiActualX,rt.uiActualY=position.x,position.y
    local geometry=string.format('%.0f:%.0f:%.0f:%.0f',width,height,position.x,position.y)
    local now=rt.api.os.clock()
    preferences.windowWidth,preferences.windowHeight=width,height
    preferences.windowX,preferences.windowY=position.x,position.y
    if rt.uiGeometry~=geometry then rt.uiGeometry=geometry;rt.uiGeometryChangedAt=now
    elseif rt.uiSavedGeometry~=geometry and now-(rt.uiGeometryChangedAt or now)>0.5 then
        preferences.windowWidth,preferences.windowHeight=width,height
        preferences.windowX,preferences.windowY=position.x,position.y
        rt.preferences:save();rt.uiSavedGeometry=geometry
    end
    g.SetWindowFontScale(1)
    if not rt.art then rt.art=rt:service('art.lua').new(g,rt.base,rt.api) end
    if not rt.avatar then rt.avatar=rt:service('avatar.lua').new(g,rt.base,_G) end
    local ui=painter(rt);local bodyFont=ui.font(16)
    local compact=preferences.compactSidebar or width<900*scale
    local side=(compact and 60 or 232)*scale
    if rt.access:displayLevel()=='S1' and (rt.page=='home' or not rt:service('permissions.lua').s1Pages[rt.page or 'home']) then rt.page='core' end
    local page=pageById(rt.page or 'home');rt.page=page[1]
    if preferences.wallpaper~=false then
        local tint=rt.theme.color(g,p.text);tint.w=0.70
        ui.image(rt:service('appearance.lua').asset('background',preferences.backgroundStyle),side,0,width-side,height,0,g.GetColorU32(tint))
    end
    if preferences.motion~=false then ui.ambient(side,0,width-side,height,now,preferences.backgroundStyle) end
    ui.rect(0,0,side,height,p.sidebar,0);ui.line(side,0,side,height,p.border)
    local logoSize=(compact and 40 or 68)*scale
    if not ui.image(rt:service('appearance.lua').asset('logo',preferences.logoStyle),10*scale,12*scale,logoSize,logoSize,0) then
        ui.rect(12*scale,16*scale,32*scale,32*scale,p.accent,5*scale)
        ui.text(19*scale,20*scale,'X',18,p.bg,28*scale,true)
    end
    if not compact then
        ui.text(86*scale,20*scale,'X-Tools',22,p.text,side-96*scale,true)
        ui.text(86*scale,48*scale,'by Casual Alvarez',12,p.muted,side-96*scale)
        ui.text(86*scale,66*scale,'v'..tostring(rt.host.version or ''),12,p.muted,side-96*scale)
    end
    local quickActions={
        {'hide','power',rt.powered==false and 'Включить X-Tools' or 'Выключить X-Tools',function()rt:setPowered(rt.powered==false)end},
        {'save','save','Сохранить оформление',function()
            local saved=rt.preferences:save()
            rt.uiQuickNotice=saved and 'Оформление сохранено' or 'Ошибка сохранения'
            rt.uiQuickNoticeUntil=now+3
        end},
        {'motion','motion','Анимация фона',function() preferences.motion=preferences.motion==false;rt.preferences:save() end},
        {'about','users','Об авторе',function()rt:open('about')end},
        {'help','help','Справка',function() rt:openHelp('start') end},
        {'system','settings','Система и обновления',function() rt:open('settings');rt.settingsPage='system' end}
    }
    local quickTop=(compact and 62 or 94)*scale
    for i,item in ipairs(quickActions) do
        local qx=(compact and 16 or 14+(i-1)*34)*scale
        local qy=quickTop+(compact and (i-1)*32*scale or 0)
        local clicked,over=ui.hit('quick_'..item[1],qx,qy,28*scale,28*scale)
        local active=item[1]=='motion' and preferences.motion~=false
        if over or active then ui.rect(qx,qy,28*scale,28*scale,over and p.hover or p.selection,4*scale) end
        ui.icon(item[2],qx+5*scale,qy+5*scale,active and p.accent or p.text)
        if over then g.SetTooltip(item[3]) end
        if clicked then item[4]() end
    end
    local navTop=(compact and 260 or 146)*scale
    if not compact and rt.uiQuickNotice and now<(rt.uiQuickNoticeUntil or 0) then
        ui.text(14*scale,128*scale,rt.uiQuickNotice,12,p.accent,side-28*scale)
    end
    g.SetCursorPos(g.ImVec2(0,navTop))
    g.BeginChild('workspace_navigation',g.ImVec2(side,math.max(40,height-navTop-60*scale)),false)
    local nav=painter(rt)
    local navWidth=math.min(side,g.GetContentRegionAvailWidth())
    local ny=0
    for _,item in ipairs(navigation) do
        if rt.access:displayLevel()~='S1' or rt:service('permissions.lua').s1Pages[item[1]] then
        local label=item[5] or item[2]
        local rowH=compact and 38*scale or math.max(38*scale,nav.measure(label,16,navWidth-56*scale,true)+16*scale)
        local active=rt.page==item[1] or rt.overlay==item[1] and rt.overlayVisible and rt.overlayVisible.v
        local clicked,hover=nav.hit('nav_'..item[1],6*scale,ny,navWidth-12*scale,rowH)
        if active or hover then nav.rect(6*scale,ny,navWidth-12*scale,rowH,active and p.selection or p.hover,4*scale) end
        if active then nav.rect(6*scale,ny+6*scale,3*scale,rowH-12*scale,p.accent,1) end
        local iconX=(compact and 21 or 16)*scale
        if item[1]=='gameplay' then
            local tint=g.GetColorU32(rt.theme.color(g,active and p.accent or p.muted))
            if not nav.image('gameplay-icon',iconX-3*scale,ny+7*scale,24*scale,24*scale,0,tint)then nav.icon('tools',iconX,ny+10*scale,active and p.accent or p.muted)end
        else nav.icon(item[4],iconX,ny+10*scale,active and p.accent or p.muted)end
        if not compact then nav.text(44*scale,ny+8*scale,label,16,active and p.text or p.muted,navWidth-56*scale,active)
        elseif hover then g.SetTooltip(item[2]) end
        if clicked then
            rt:open(item[1]);if item[1]=='settings' then rt.settingsPage='system' end
        end
        ny=ny+rowH+4*scale
        end
    end
    g.SetCursorPos(g.ImVec2(0,ny));g.Dummy(g.ImVec2(1,1))
    g.EndChild()
    ui.button('sidebar_compact',8*scale,height-48*scale,side-16*scale,compact and '>' or '<  Свернуть',false,function()
        preferences.compactSidebar=not preferences.compactSidebar;rt.preferences:save()
    end)
    local bodyX=side+16*scale;local bodyW=width-bodyX-16*scale
    local titleH=ui.text(bodyX,16*scale,page[2],24,p.text,bodyW-78*scale,true)
    local headerH=math.max(60*scale,titleH+32*scale)
    if compact and rt.uiQuickNotice and now<(rt.uiQuickNoticeUntil or 0) then
        local noticeH=ui.text(bodyX,headerH-8*scale,rt.uiQuickNotice,12,p.accent,bodyW)
        headerH=headerH+noticeH+12*scale
    end
    local close,hover=ui.hit('workspace_close',width-40*scale,12*scale,28*scale,28*scale)
    if hover then ui.rect(width-40*scale,12*scale,28*scale,28*scale,p.hover,5*scale) end
    ui.line(width-32*scale,20*scale,width-20*scale,32*scale,p.muted,1.5*scale)
    ui.line(width-20*scale,20*scale,width-32*scale,32*scale,p.muted,1.5*scale)
    if close then
        _G.show_main_window.v=false
        if rt.keys.cancelCapture then rt.keys:cancelCapture() end
    end
    if page[1]~='commands' then
        local help,over=ui.hit('page_help',width-76*scale,12*scale,28*scale,28*scale)
        ui.icon('help',width-70*scale,18*scale,p.muted)
        if over then g.SetTooltip('Справка по разделу') end
        if help then rt:openHelp(helpSections[page[1]]) end
    end
    ui.line(bodyX,headerH-8*scale,width-16*scale,headerH-8*scale,p.border)
    rt:selectCorePanel(nil)
    local currentModule=moduleById(page[1])
    local bodyY=headerH
    g.SetCursorPos(g.ImVec2(bodyX,bodyY))
    g.PushStyleColor(g.Col.ChildWindowBg,g.ImVec4(0,0,0,0))
    local contentId='workspace_page_'..page[1]..'_'..tostring(rt.moduleMode or 'functions')..'_'..tostring(rt.settingsPage)
    local childFlags=page[1]=='commands' and (g.WindowFlags.NoScrollbar+g.WindowFlags.NoScrollWithMouse) or 0
    g.BeginChild(contentId,g.ImVec2(bodyW,height-bodyY-16*scale),false,childFlags)
    if rt.restoreWorkspaceScroll then g.SetScrollY(rt.restoreWorkspaceScroll);rt.restoreWorkspaceScroll=nil end
    rt.workspaceScroll=g.GetScrollY()
    g.PushItemWidth(math.min(300*scale,bodyW*0.48))
    rt.drawingWorkspace=true
    if rt.powered==false then
        g.TextWrapped('X-Tools выключен. Функции, HUD и автоматические команды остановлены.')
    elseif page[1]=='home' then dashboard(rt,painter(rt),math.max(1,bodyW-16*scale),height-bodyY-16*scale)
    elseif currentModule then
        if page[1]=='menu' then
            modulePage(rt,'menu',true)
            modulePage(rt,'observer_extras',true)
            if rt.drawObservationPing then rt.drawObservationPing()end
            if g.Button('Настроить отображаемое')then rt:call(rt.modules.display_layout,rt.modules.display_layout.bridge.openEditor)end
        else drawModule(rt,callback,currentModule)end
        if page[1]=='autoreply' and rt.moduleMode=='settings' then modulePage(rt,'report_assist',true)end
    elseif page[1]=='teleport' then
        if rt.access:can(1) then
            local tp=painter(rt);local bannerW=g.GetContentRegionAvailWidth()
            local bx,by=g.GetCursorPosX(),g.GetCursorPosY()
            local artW=bannerW*.70;local bannerH=math.max(150*scale,artW/3)
            tp.rect(bx,by,bannerW,bannerH,p.bg,8*scale)
            tp.image('teleport-banner',bx+bannerW-artW,by,artW,artW/3,8*scale,g.GetColorU32(rt.theme.color(g,p.accent)))
            local textW=bannerW-artW-24*scale
            tp.text(bx+22*scale,by+28*scale,'ТЕЛЕПОРТ',24,p.text,textW,true)
            tp.text(bx+22*scale,by+70*scale,'Выберите категорию или найдите место по названию',14,p.muted,textW)
            g.SetCursorPos(g.ImVec2(bx,by+bannerH+12*scale))
            drawCore(rt,callback,'teleportation_window',1)
            modulePage(rt,'tpm',false)
            g.Spacing();g.Separator();g.Spacing()
            local zone=rt.modules.adminzone
            if zone and zone.enabled and zone.bridge and rt.access:can(3) then
                local zx,zy=g.GetCursorPosX(),g.GetCursorPosY()
                local zh=tp.zoneButton('teleport_adminzone',zx,zy,math.min(340*scale,bannerW),function()rt:call(zone,zone.bridge.enter)end)
                g.SetCursorPos(g.ImVec2(zx,zy+zh+12*scale));g.Dummy(g.ImVec2(1,1))
            end
        else g.TextWrapped('Доступно с 1 уровня администратора.')end
    elseif page[1]=='gameplay' then drawGameplay(rt,callback)
    elseif page[1]=='schedule' then rt:service('schedule_ui.lua').draw(rt)
    elseif page[1]=='settings' then
        rt:drawSystemSettings()
    elseif page[1]=='about' then rt:service('about_author.lua').draw(rt)
    elseif page[1]=='commands' then rt:drawHelp() end
    rt.drawingWorkspace=false
    g.PopItemWidth();g.EndChild();g.PopStyleColor()
    if bodyFont then g.PopFont() end
    g.End();rt.theme.pop(g,colorCount,varCount)
end
return Workspace
