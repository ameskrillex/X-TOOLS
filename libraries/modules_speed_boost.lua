-- X-TOOLS | Project and integration: Casual_Alvarez | Module: modules/speed_boost.lua
-- Original third-party credits, where present, are retained below.
-- sh.cs: original 04BA speed boost, rewritten without a CLEO thread.
local g=require('imgui')
local settings=integration.service('combo_settings.lua')
local cfg,path=settings.load(integration,'speed-boost',{main={enabled=false}})
local nextAt=0
integration.keys:register('speed_boost','Ускорение транспорта — удерживать',{key=87,shift=true,second=0})
integration.update=function()
    if integration.flightActive() or integration.observation()then return end
    if not cfg.main.enabled or not integration.access:canUseTools() or sampGetGamestate()~=3 then return end
    if not isGameWindowForeground() or isPauseMenuActive() or sampIsChatInputActive() or sampIsDialogActive() or sampIsCursorActive() then return end
    if not integration.keys:down('speed_boost') or getGameTimer()<nextAt then return end
    if not doesCharExist(PLAYER_PED) or not isCharInAnyCar(PLAYER_PED)then return end
    local car=storeCarCharIsInNoSave(PLAYER_PED)
    if getDriverOfCar(car)~=PLAYER_PED then return end
    local speed=getCarSpeed(car)
    if type(speed)~='number' or speed~=speed then return end
    setCarForwardSpeed(car,speed<190 and speed*1.15+4 or 61)
    nextAt=getGameTimer()+50
end
integration.onDisconnect=function()nextAt=0 end
local settingsExpanded=false
integration.drawSettings=function()
    if settings.toggle(g,'Ускорение транспорта',cfg.main,'enabled')then integration.storage:saveIni(cfg,path)end
    g.SameLine()
    if g.Button('Настройки##speed_boost_settings')then settingsExpanded=not settingsExpanded end
    if not settingsExpanded then return end
    integration.keys:draw(g,'speed_boost')
    
end
