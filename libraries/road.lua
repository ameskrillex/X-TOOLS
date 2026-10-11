-- X-TOOLS | Project and integration: Casual_Alvarez | Module: modules/road.lua
-- Original third-party credits, where present, are retained below.
-- CasualTool road placement, adapted from bart4RoadTP (source in integration/sources).
-- One explicit action; no background loop, second UI window or startup message.
local ffi = require 'ffi'
local SEARCH_RADIUS, HEIGHT_OFFSET = 10000, 0.2
local fallback_roads = {{x=-151, y=-373, z=1, radius=1000}}

local function tell(text)
    integration.message(text)
end

local function finite(value)
    return type(value)=='number' and value==value and value~=math.huge and value~=-math.huge
end

local function find_road(ped)
    local x,y,z = getCharCoordinates(ped)
    if not (finite(x) and finite(y) and finite(z)) then return end
    -- Opcode 04B9 returns node1 XYZ, node2 XYZ, angle (no boolean prefix).
    local rx,ry,rz = getClosestStraightRoad(x,y,z,0,SEARCH_RADIUS)
    if finite(rx) and finite(ry) and finite(rz) and (rx~=0 or ry~=0 or rz~=0) then
        return rx,ry,rz+HEIGHT_OFFSET
    end
    local nearest, distance
    for _, point in ipairs(fallback_roads) do
        local squared = (x-point.x)^2+(y-point.y)^2+(z-point.z)^2
        if squared<=point.radius^2 and (not distance or squared<distance) then
            nearest,distance = point,squared
        end
    end
    if nearest then return nearest.x,nearest.y,nearest.z+HEIGHT_OFFSET end
end

local function send_position(local_id,x,y,z)
    local stream
    local ok,err = pcall(function()
        local sf = require 'lib.sampfuncs'
        require 'samp.synchronization'
        -- Retain the owned array until its bytes have been copied into the stream.
        local data = ffi.new('struct PlayerSyncData[1]')
        local pointer = tonumber(ffi.cast('uintptr_t',data))
        sampStorePlayerOnfootData(local_id,pointer)
        data[0].position.x,data[0].position.y,data[0].position.z = x,y,z
        stream = raknetNewBitStream()
        assert(stream and stream~=0, 'Cannot allocate road sync bitstream')
        raknetBitStreamWriteInt8(stream,sf.PACKET_PLAYER_SYNC)
        raknetBitStreamWriteBuffer(stream,pointer,ffi.sizeof(data))
        local sent = raknetSendBitStreamEx(stream,sf.HIGH_PRIORITY,sf.UNRELIABLE_SEQUENCED,1)
        assert(sent~=false, 'Road sync send failed')
    end)
    if stream and stream~=0 then
        local freed,free_error = pcall(raknetDeleteBitStream,stream)
        if not freed then ok,err=false,free_error end
    end
    return ok,err
end

local followupGeneration=0
local events=require 'samp.events'
local function cancelFollowup() followupGeneration=followupGeneration+1 end
integration.onDisconnect=cancelFollowup
function events.onSendCommand(command)
    if tostring(command):lower():match('^/sp%s') or tostring(command):lower()=='/sp' then cancelFollowup() end
end
-- Any server transition invalidates the previous action, even if the same
-- player is selected again. Never reopen a session the user has just left.
events.onTogglePlayerSpectating=cancelFollowup
events.onSpectatePlayer=cancelFollowup
events.onSpectateVehicle=cancelFollowup
local function move_to_road(argument)
    cancelFollowup()
    if not integration.access:require(3, tell) then return end
    local text = tostring(argument or ''):match('^%s*(%d+)%s*$')
    local target_id = text and tonumber(text)
    if not target_id or target_id<0 or target_id>1003 then
        tell('Укажите ID игрока: /tr ID.')
        return
    end
    if not isSampAvailable() or sampGetGamestate()~=3 then
        tell('Для перемещения на дорогу подключитесь к серверу.')
        return
    end
    local found,local_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if not found or not finite(local_id) then
        tell('Не удалось определить ваш ID. Дождитесь входа в игру и повторите перемещение.')
        return
    end
    if target_id==local_id then
        tell('Укажите ID другого игрока для перемещения на дорогу.')
        return
    end
    if not sampIsPlayerConnected(target_id) then
        tell('Этот игрок не подключён к серверу. Проверьте ID.')
        return
    end
    local streamed,ped = sampGetCharHandleBySampPlayerId(target_id)
    if not streamed or not ped or ped==0 then
        tell('Игрок вне зоны прорисовки. Приблизьтесь к нему или начните слежку.')
        return
    end
    if getActiveInterior()~=0 then
        tell('Перемещение на дорогу доступно только вне интерьеров.')
        return
    end
    local ok,x,y,z = pcall(find_road,ped)
    if not ok then
        tell('Не удалось найти координаты дороги. '..tostring(x))
        return
    end
    if not x then
        tell('Поблизости нет подходящей точки для перемещения на дорогу.')
        return
    end
    local sent,err = send_position(local_id,x,y,z)
    if not sent then
        tell('Не удалось отправить запрос перемещения на дорогу. '..tostring(err))
        return
    end
    -- Preserve source ordering: one position update, then the server command.
    sampSendChat('/gethere '..target_id..' 1')
    integration.releaseSpectateInput()
    -- Only the action menu requests follow-up here. Typed /tr stays standalone;
    -- Aegis already queues its own slap and observation refresh.
    if integration.preferences.data.main.roadFollowup and integration.commandOwner()=='menu' then
        followupGeneration=followupGeneration+1
        local generation=followupGeneration
        local nickname=sampGetPlayerNickname(target_id)
        local function valid()
            local observed=integration.observation()
            return observed and observed.id==target_id and generation==followupGeneration and integration.preferences.data.main.roadFollowup
                and integration.access:can(1) and sampGetGamestate()==3
                and sampIsPlayerConnected(target_id) and sampGetPlayerNickname(target_id)==nickname
        end
        lua_thread.create(function()
            wait(350)
            if not valid() then return end
            sampSendChat('/slap '..target_id)
            wait(350)
            if valid() then sampSendChat('/sp '..target_id) end
        end)
    end
end

sampRegisterChatCommand('tr',move_to_road)

