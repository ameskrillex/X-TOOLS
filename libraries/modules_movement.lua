-- X-TOOLS | Project and integration: Casual_Alvarez | Module: modules/movement.lua
-- Original third-party credits, where present, are retained below.
-- Lua ports of AntiBH (AIR), MatrixJump and BackF; see integration/CLEO_PORTS.md.
local events=require('lib.samp.events')
local bit=require('bit')
local steps=integration.service('stunt_steps.lua')
local generation,busy,owned=0,false,nil
local cjMovement=integration.service('cj_movement.lua').new(_G)
local keyPatch=integration.service('function_key_patch.lua').new(_G,integration.message)
integration.keys:register('matrix_jump','Акробатический прыжок',{key=32,shift=true,second=0})
integration.keys:register('back_flip','Сальто назад',{key=32,second=67})
local function clean()
    if owned and doesCharExist(owned.ped) and getCharPointer(owned.ped)==owned.pointer then
        setCharRotation(owned.ped,0,0,owned.heading)
        if not owned.proof then
            local address=owned.pointer+0x42
            writeMemory(address,1,bit.band(readMemory(address,1,false),0xEF),false)
        end
    end
    owned=nil;busy=false
end
local function cancel() generation=generation+1;clean() end
local function available()
    return sampGetGamestate()==3 and doesCharExist(PLAYER_PED) and not isCharDead(PLAYER_PED)
        and not isCharInAnyCar(PLAYER_PED) and not isPauseMenuActive() and isGameWindowForeground()
        and not sampIsChatInputActive() and not sampIsDialogActive() and not sampIsCursorActive()
end
local function run(kind)
    busy=true;local token=generation;local ped=PLAYER_PED;local pointer=getCharPointer(ped)
    local heading=getCharHeading(ped)
    local flags=readMemory(pointer+0x42,1,false)
    owned={ped=ped,pointer=pointer,heading=heading,proof=bit.band(flags,0x10)~=0}
    -- CPhysical collision-proof bit only; keep the other protection flags intact.
    writeMemory(pointer+0x42,1,bit.bor(flags,0x10),false)
    setCharRotation(ped,0,0,heading)
    local x,y=getCharVelocity(ped)
    if kind=='matrix' then x,y=x*1.3*1.3,y*1.3*1.3 end
    setCharVelocity(ped,x,y,10)
    taskPlayAnimNonInterruptable(ped,kind=='matrix' and 'FALL_FALL' or 'FALL_SKYDIVE','PED',3,false,false,false,false,kind=='matrix' and 440 or 410)
    lua_thread.create(function()
        for _,step in ipairs(steps[kind]) do
            if step[1]>0 then wait(step[1]) end
            if token~=generation then return end
            if not integration.preferences.data.main[kind=='matrix' and 'matrixJump' or 'backFlip'] or not available() or PLAYER_PED~=ped or getCharPointer(ped)~=pointer then clean();return end
            setCharRotation(ped,step[2],0,heading)
        end
        if token==generation then
            clean()
            if kind=='backflip' then busy=true;wait(600);if token==generation then busy=false end end
        end
    end)
end
function events.onSendPlayerSync(data)
    if integration.preferences.data.main.antiBH and tonumber(data.keysData)==40 then data.keysData=32 end
end
integration.update=function()
    local prefs=integration.preferences.data.main
    keyPatch:update(prefs.blockF1F4==true)
    cjMovement:update(prefs.cjMovement==true)
    local matrixPressed=integration.keys:pressed('matrix_jump')
    local backPressed=integration.keys:pressed('back_flip')
    if busy or integration.flightActive() or (not prefs.matrixJump and not prefs.backFlip) or not available() then return end
    if isCharPlayingAnim(PLAYER_PED,'CLIMB_JUMP') then return end
    if prefs.matrixJump and matrixPressed then run('matrix')
    elseif prefs.backFlip and backPressed then run('backflip') end
end
integration.onDisconnect=function()cancel();cjMovement:stop()end
integration.stop=function()cancel();keyPatch:stop();cjMovement:stop()end
integration.prepareReload=function()keyPatch:stop();cjMovement:stop()end
local settingsExpanded={}
integration.drawSettings=function()
    local g=require('imgui')
    for _,item in ipairs({{'commandLayout','Исправлять русскую раскладку команд /'},{'cjMovement','Походка и бег CJ'},{'blockF1F4','Блокировать F1, F4, F5 и F7'},{'antiBH','Баннихоп (AntiBH)'},{'matrixJump','Акробатический прыжок'},{'backFlip','Сальто назад'}}) do
        local value=g.ImBool(integration.preferences.data.main[item[1]])
        if g.Checkbox(item[2],value) then integration.preferences.data.main[item[1]]=value.v;integration.preferences:save();cancel() end
        if item[1]=='matrixJump' or item[1]=='backFlip' then
            g.SameLine()
            if g.Button('Настройки##movement_'..item[1]) then settingsExpanded[item[1]]=not settingsExpanded[item[1]] end
        end
        if settingsExpanded[item[1]] then
        if item[1]=='matrixJump' then
            
            integration.keys:draw(g,'matrix_jump')
        elseif item[1]=='backFlip' then
            
            integration.keys:draw(g,'back_flip')
        end
        g.TextWrapped('Без назначенной клавиши трюк не запускается.')
        end
    end
end

-- Assigned keys replace the source combinations; an unassigned binding keeps them.
