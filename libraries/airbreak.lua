-- X-TOOLS | Project and integration: Casual_Alvarez | Module: modules/airbreak.lua
-- Original third-party credits, where present, are retained below.
-- AirBreak controls reconstructed from AirBreak (2).cs; no camera resets or helper actors.
local g=require('imgui')
local cfg,path=integration.storage:loadIni({main={mode=2,enabled=true,mouse_turn=true}},integration.storage:path('settings','airbreak.ini')),integration.storage:path('settings','airbreak.ini')
local geometry=integration.service('flight_geometry.lua')
local mouseOffset=0
local active,ped,car,heading,speed,vertical,last=false,nil,nil,0,0,0,nil
local animationOwned=false
local function keepAnimation()
    if not car and ped and doesCharExist(ped) and not isCharPlayingAnim(ped,'Swim_Tread')then
        taskPlayAnimNonInterruptable(ped,'Swim_Tread','PED',4.1,true,false,false,false,-1)
        animationOwned=true
    end
end
-- Exact entity position: ped teleports clear animations; vehicle teleports
-- apply a placement offset that accumulates if fed back every frame.
local function movePreservingAnimation(x,y,z)
    local address
    if car then address=getCarPointer(car)else address=getCharPointer(ped)end
    if not address or address==0 then return false end
    local matrix=readMemory(address+0x14,4,false)
    if not matrix or matrix==0 then return false end
    for index,value in ipairs({x,y,z})do
        writeMemory(matrix+0x30+(index-1)*4,4,representFloatAsInt(value),false)
    end
    return true
end
local profiles={{0.1,5,0.01,1,1,0},{2,30,0.2,3,30,0.3},{50,200,1,50,50,0}}
local function stop()
    active=false
    if car and doesVehicleExist(car) then freezeCarPosition(car,false);setCarCollision(car,true) end
    if not car and ped and doesCharExist(ped) then
        freezeCharPosition(ped,false);setCharCollision(ped,true)
        if animationOwned and isCharPlayingAnim(ped,'Swim_Tread')then clearCharTasks(ped)end
    end
    animationOwned=false
    car=nil;ped=nil;last=nil
end
integration.stop=stop;integration.onDisconnect=stop;integration.onAccessChanged=stop;integration.isActive=function()return active end
integration.keys:register('airbreak','AirBreak: включить / выключить',{key=50,ctrl=true})
integration.keys:register('airbreak_stop','AirBreak: выключить',{key=51,ctrl=true})
local controls={
    {'forward','Вперёд',87},{'back','Назад',83},{'left','Влево',65},{'right','Вправо',68},
    {'up','Вверх',81},{'down','Вниз',69},
    {'slower','Скорость: уменьшить',0},{'faster','Скорость: увеличить',0},
    {'slow','Скорость: медленно',97},{'normal','Скорость: обычно',98},{'fast','Скорость: быстро',99},
    {'turn_left','Поворот влево',37},{'turn_right','Поворот вправо',39},
    {'car_up','Транспорт: вверх (дополнительно)',38},{'car_down','Транспорт: вниз (дополнительно)',40},
    {'ground','Пешком: опуститься на землю',40},
}
for _,c in ipairs(controls)do
    integration.keys:register('airbreak_'..c[1],'AirBreak: '..c[2],{key=c[3]},nil,function()return active end)
end
local speedHeld={}
local function held(action)
    if integration.keys:captureActive() or integration.keys:textInputActive()then return false end
    local b=integration.keys.data['airbreak_'..action]
    return b and b.key~=0 and isKeyDown(b.key)
        and (not b.second or b.second==0 or isKeyDown(b.second))
        and (not b.third or b.third==0 or isKeyDown(b.third))
        and (not b.ctrl or isKeyDown(17)) and (not b.alt or isKeyDown(18)) and (not b.shift or isKeyDown(16))
end
local function speedKeys(allowed)
    local mode=math.floor(math.max(1,math.min(3,tonumber(cfg.main.mode)or 2)))
    for _,action in ipairs({'slower','faster','slow','normal','fast'})do
        local down=held(action)==true
        if allowed and down and not speedHeld[action]then
            if action=='slower'then mode=math.max(1,mode-1)
            elseif action=='faster'then mode=math.min(3,mode+1)
            else mode=({slow=1,normal=2,fast=3})[action]end
        end
        speedHeld[action]=down
    end
    cfg.main.mode=mode
end
local saved=integration.keys.data.airbreak
if saved and saved.key==188 and not saved.ctrl and not saved.alt and not saved.shift and saved.second==0 then
    saved.key=50;saved.ctrl=true;integration.storage:saveIni(integration.keys.data,integration.keys.path)
end
local function usable()
    return sampGetGamestate()==3 and doesCharExist(PLAYER_PED) and not isCharDead(PLAYER_PED) and not integration.observation()
end
local function start()
    if active then stop();return end
    if cfg.main.enabled~=true then return end
    if not usable() or not integration.access:canUseTools() then return end
    integration.claimFlight()
    ped=PLAYER_PED;heading=getCharHeading(ped);speed=0;vertical=0;last=getGameTimer()
    if isCharInAnyCar(ped) then
        car=storeCarCharIsInNoSave(ped)
        if not car or not doesVehicleExist(car) then ped=nil;car=nil;return end
        heading=getCarHeading(car);freezeCarPosition(car,true);setCarCollision(car,false)
    else freezeCharPosition(ped,true);setCharCollision(ped,false) end
    mouseOffset=0
    active=true
end
integration.update=function()
    local toggle=integration.keys:pressed('airbreak');local exit=integration.keys:pressed('airbreak_stop')
    local input=not integration.windowOpen() and isGameWindowForeground() and not isPauseMenuActive() and not sampIsChatInputActive() and not sampIsDialogActive() and not sampIsCursorActive()
    speedKeys(input and active)
    if input and exit then stop();return end
    if input and toggle then start() end
    if not active then return end
    if not usable() or ped~=PLAYER_PED or (car and (not doesVehicleExist(car) or not isCharInCar(ped,car))) or (not car and isCharInAnyCar(ped)) then stop();return end
    local now=getGameTimer();local dt=math.min(3,math.max(0,(now-(last or now))/16.6667));last=now
    if not input then keepAnimation();return end
    local mode=math.floor(math.max(1,math.min(3,tonumber(cfg.main.mode)or 2)));local p=profiles[mode]
    if car then p=mode==3 and {8,20,3,8,40,3}or {1,11,0.1,mode==1 and 0.5 or 1,11,0.1}end
    local forward=(held('forward')and 1 or 0)-(held('back')and 1 or 0)
    local side=(held('right')and 1 or 0)-(held('left')and 1 or 0)
    local up=((held('up')or(car and held('car_up')))and 1 or 0)-((held('down')or(car and held('car_down')))and 1 or 0)
    speed=(forward~=0 or side~=0)and math.min(p[2],math.max(p[1],speed)+p[3]*dt)or p[1]
    vertical=up~=0 and math.min(p[5],math.max(p[4],vertical)+p[6]*dt)or p[4]
    local turn=((held('turn_left')and 1 or 0)-(held('turn_right')and 1 or 0))*4*dt
    local camera=cfg.main.mouse_turn and geometry.cameraHeading(_G)
    if camera then mouseOffset=(mouseOffset+turn)%360;heading=(camera+mouseOffset)%360
    else heading=(heading+turn)%360 end
    local x,y,z;if car then x,y,z=getCarCoordinates(car)else x,y,z=getCharCoordinates(ped)end
    local a=math.rad(heading)
    x=x+(-math.sin(a)*forward+math.cos(a)*side)*speed*dt
    y=y+(math.cos(a)*forward+math.sin(a)*side)*speed*dt
    local climb=up*vertical
    if not car and mode==1 then climb=up>0 and 1.5 or (up<0 and -0.5 or 0)
    elseif not car and mode==3 then climb=up>0 and 11 or (up<0 and -39 or 0)end
    z=z+climb*dt
    if not car and held('car_down') then z=getGroundZFor3dCoord(x,y,z)+1 end
    if car then
        setCarHeading(car,heading)
        if forward~=0 or side~=0 or up~=0 then
            if not movePreservingAnimation(x,y,z)then stop();return end
        end
    else
        setCharHeading(ped,heading)
        if forward~=0 or side~=0 or up~=0 or held('ground')then
            if not movePreservingAnimation(x,y,z)then stop();return end
        end
    end
    keepAnimation()
end
local settingsExpanded=false
local controlsExpanded=false
integration.drawSettings=function()
    local value=g.ImBool(cfg.main.enabled==true)
    if g.Checkbox('AirBreak',value)then
        cfg.main.enabled=value.v
        integration.storage:saveIni(cfg,path)
        if not value.v then stop()end
    end
    g.SameLine()
    if g.Button('Настройки##airbreak_settings') then settingsExpanded=not settingsExpanded end
    if not settingsExpanded then return end
    g.TextDisabled('AirBreak '..(active and 'работает' or 'не запущен'))
    integration.keys:draw(g,'airbreak');integration.keys:draw(g,'airbreak_stop')
    local mode=g.ImInt((tonumber(cfg.main.mode)or 2)-1)
    if g.Combo('Скорость##airbreak',mode,{'Медленно','Обычно','Быстро'})then cfg.main.mode=mode.v+1;integration.storage:saveIni(cfg,path)end
    local mouse=g.ImBool(cfg.main.mouse_turn==true)
    if g.Checkbox('Поворачивать за мышью##airbreak_mouse',mouse)then cfg.main.mouse_turn=mouse.v;mouseOffset=0;integration.storage:saveIni(cfg,path)end
    if g.Button('Клавиши движения и скорости##airbreak_controls')then controlsExpanded=not controlsExpanded end
    if controlsExpanded then
        g.TextWrapped('Нажмите клавишу рядом с действием, чтобы изменить её. Назначения сохраняются сразу. Скорость меняется на один режим за нажатие.')
        for _,c in ipairs(controls)do integration.keys:draw(g,'airbreak_'..c[1])end
    end
    g.TextWrapped('Вверх: '..integration.keys:name('airbreak_up')..' · Вниз: '..integration.keys:name('airbreak_down')..' · Медленнее: '..integration.keys:name('airbreak_slower')..' · Быстрее: '..integration.keys:name('airbreak_faster'))
    
end
