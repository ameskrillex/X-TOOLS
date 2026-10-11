-- X-TOOLS | Project and integration: Casual_Alvarez | Module: modules/zone_wall.lua
-- Original third-party credits, where present, are retained below.
local g=require('imgui');local bit=require('bit')
local events=require('lib.samp.events');local u8=require('encoding').UTF8
local styles=integration.service('zone_wall_styles.lua')
local barrier=integration.service('zone_barrier.lua')
local visibility=integration.service('zone_visibility.lua').new()
local Crossing=integration.service('zone_crossings.lua')
local Shots=integration.service('zone_shots.lua')
local shotWarnings={}
local unionTracker=Crossing.new();local previousZones={};local unionRegion
local function resetCrossings(id)
    unionTracker:reset(id)
    if id==nil then previousZones={};unionRegion=nil end
end
local serverModel=integration.serverZones()
local zoneClass=integration.service('zone_wall.lua')
-- Gang-zone colors are ABGR. Ignore opacity; include the gang palette used
-- by the server for both ownership and flashing attacker colors.
local gangColors={ [0xFF00CC]=true,[0xCD00CD]=true,[0xFF00FF]=true,
    [0x009900]=true,[0x00FF00]=true,[0x00CDFF]=true,[0x00FFFF]=true,
    [0xFF6666]=true,[0xFFCC00]=true }
local function gangColor(value)
    value=tonumber(value)
    return value and gangColors[value%16777216]==true
end
local filtered,filteredRevision={},-1
local model=setmetatable({}, {__index=function(_,key)
    if key=='revision' then return serverModel.revision end
    if key=='zones' then
        if filteredRevision~=serverModel.revision then
            filtered={};filteredRevision=serverModel.revision
            for id,z in pairs(serverModel.zones)do
                if not gangColor(z.color) and not gangColor(z.flashColor)then filtered[id]=z end
            end
        end
        return filtered
    end
    return zoneClass[key]
end})
local function currentRegion()
    local zones=model:activeZones();local changed=false
    for id,z in pairs(zones)do if previousZones[id]~=z then changed=true;break end end
    if not changed then for id in pairs(previousZones)do if not zones[id]then changed=true;break end end end
    if not changed then return unionRegion end
    previousZones=zones;unionTracker:reset();unionRegion=nil
    if not next(zones)then return end
    local boundary=model:boundary()
    local region={}
    function region.membership(x,y)
        local inside=false;local nearestId,nearest= nil,math.huge
        for id,z in pairs(zones)do
            local dx,dy=math.max(z[1]-x,x-z[3],0),math.max(z[2]-y,y-z[4],0)
            local distance=dx*dx+dy*dy
            if distance==0 then inside=true end
            if distance<nearest or distance==nearest and (not nearestId or id<nearestId)then nearestId,nearest=id,distance end
        end
        local definitive=true
        for _,edge in ipairs(boundary)do
            local dx,dy=math.max(edge[1]-x,x-edge[3],0),math.max(edge[2]-y,y-edge[4],0)
            if dx*dx+dy*dy<=.75*.75 then definitive=false;break end
        end
        return inside,definitive,nearestId
    end
    unionRegion=region;return region
end
local path=integration.storage:path('settings','zone-wall.ini')
local cfg=integration.storage:loadIni({main={enabled=false,height=12,range=200,step=6,color=0xB040E8E0,style=0,warn_enter=false,warn_exit=false,warn_return=true,warn_late=true,warn_shots=true}},path)
local c=cfg.main
local function clamp(v,lo,hi,default)v=tonumber(v);if not v or v~=v then return default end;return math.max(lo,math.min(hi,v))end
c.height=clamp(c.height,3,40,12);c.range=clamp(c.range,30,400,200);c.step=clamp(c.step,3,20,6)
c.barrier_height=clamp(c.barrier_height,20,300,150)
c.color=tonumber(c.color)or 0xB040E8E0
c.style=math.floor(clamp(c.style,0,13,13))
if not c.markerStylesVersion then c.style=10;c.markerStylesVersion=1;integration.storage:saveIni(cfg,path)end
if not c.barrierVersion then c.style=13;c.color=0xB0FF3434;c.height=18;c.barrierVersion=1;integration.storage:saveIni(cfg,path)end
local lines,panels={},{};local nextBuild=0;local revision=-1
local preview,buildEye,buildModel
local elevation
local native,attempted,lost,meshDirty,barrierStatus=nil,false,false,true,nil
local nativeFailure
local nativeStats,nextStats,traceUntil,nextTrace=nil,0,nil,0
local function startTrace()
    local now=getGameTimer();traceUntil=now+15000;nextTrace=now+1000
end
local function closeNative()
    if native then pcall(native.close,native);native=nil end
    attempted=false;nativeFailure=nil;nativeStats=nil;nextStats=0
end
local function clear()lines={};panels={};nextBuild=0;buildEye=nil;elevation=nil;meshDirty=true;barrierStatus=nativeFailure;visibility:reset()end
local watchTime=0
local function reset()closeNative();preview=nil;clear();resetCrossings();shotWarnings={};watchTime=0;traceUntil=nil end
local function save()integration.storage:saveIni(cfg,path)end
local function enabled()return (c.enabled or preview~=nil) and integration.access:canUseTools() and sampGetGamestate()==3 end
local function watch()
    local discord=integration.squareWarningsEnabled()
    if not integration.access:can(1) or sampGetGamestate()~=3 or not(discord or c.warn_enter or c.warn_exit or c.warn_return or c.warn_late)
        or (getActiveInterior and getActiveInterior()~=0)then unionTracker:reset();return end
    local now=getGameTimer();if now<watchTime and watchTime-now<=250 then return end;watchTime=now+250
    local region=currentRegion();if not region then return end
    local seen={}
    -- Track the union, not each rectangle. Moving across an internal seam must
    -- neither create an exit nor reset a genuine exit/return timer.
    for id=0,math.min(1004,sampGetMaxPlayerId(false))do
        if sampIsPlayerConnected(id)then
            local found,ped=sampGetCharHandleBySampPlayerId(id)
            if found and ped and ped~=0 and ped~=PLAYER_PED and doesCharExist(ped)then
                local nick=sampGetPlayerNickname(id);local x,y=getCharCoordinates(ped)
                if model.finite(x)and model.finite(y)then
                    seen[id]=true
                    local change,elapsed=unionTracker:sample(id,nick,x,y,region,now)
                    if (c.warn_late or discord)and unionTracker:overdue(id,now)then
                        local text=tostring(u8(nick))..'['..id..'] вышел из квадрата и не вернулся за 5 с.'
                        if c.warn_late then integration.message(text)end
                        integration.squareWarning(text)
                    end
                    if change then
                        local _,_,zoneId=region.membership(x,y)
                        local text=tostring(u8(nick))..'['..id..'] '
                        if change=='exit'then text=text..'вышел из квадрата'
                        elseif elapsed then text=text..'вернулся в квадрат через '..string.format('%.1f',elapsed/1000)..' с.'
                        else text=text..'вошёл в квадрат'end
                        integration.squareWarning(text..' · Квадрат #'..zoneId)
                        if change=='enter' and c.warn_return and elapsed and elapsed>=0 and elapsed<=5000 then
                            integration.message(tostring(u8(nick))..'['..id..'] вышел и вернулся в квадрат за '..string.format('%.1f',elapsed/1000)..' с.')
                        elseif change=='enter' and c.warn_enter or change=='exit' and c.warn_exit then
                            integration.message('Внимание! '..tostring(u8(nick))..'['..id..'] '..(change=='enter' and 'вошёл на территорию квадрата' or 'покинул территорию квадрата')..' #'..zoneId..'.')
                        end
                    end
                end
            end
        end
    end
    for id in pairs(unionTracker.players)do if not seen[id]then unionTracker:reset(id)end end
end
function events.onPlayerStreamOut(id)resetCrossings(id)end
function events.onPlayerStreamIn(id)resetCrossings(id)end
function events.onPlayerQuit(id)resetCrossings(id)end
local function shot(id,data)
    if not (c.warn_shots or integration.squareWarningsEnabled()) or not integration.access:can(1) or sampGetGamestate()~=3
        or getActiveInterior and getActiveInterior()~=0 or not data or tonumber(data.targetType)~=1 then return end
    local target=tonumber(data.targetId)
    if not target or target==id or not sampIsPlayerConnected(id) or not sampIsPlayerConnected(target) then return end
    local found,ped=sampGetCharHandleBySampPlayerId(target)
    local own,localId=sampGetPlayerIdByCharHandle(PLAYER_PED)
    if own and target==localId then found,ped=true,PLAYER_PED end
    if not found or not ped or ped==0 or not doesCharExist(ped) or not data.origin then return end
    local x,y=getCharCoordinates(ped);local now=getGameTimer()
    local nick,victim=sampGetPlayerNickname(id),sampGetPlayerNickname(target)
    for key,row in pairs(shotWarnings)do if now<row.time or now-row.time>3000 then shotWarnings[key]=nil end end
    local region=currentRegion();if not region then return end
    local direction=Shots.direction(data.origin.x,data.origin.y,x,y,region)
    if direction then
        local key=id..':'..target..':'..direction
        local last=shotWarnings[key]
        if not last or last.zone~=region or last.nick~=nick or last.victim~=victim then
            shotWarnings[key]={time=now,zone=region,nick=nick,victim=victim}
            local text=tostring(u8(nick))..'['..id..'] стреляет '..
                (direction=='out' and 'из квадрата → ' or 'снаружи → ')..
                tostring(u8(victim))..'['..target..'] '..(direction=='out' and 'вне квадрата.' or 'в квадрате.')
            if c.warn_shots then integration.message(text)end
            integration.squareWarning(text)
        end
    end
end
function events.onBulletSync(id,data)
    local ok,localId=sampGetPlayerIdByCharHandle(PLAYER_PED)
    if not ok or id~=localId then shot(id,data)end
end
function events.onSendBulletSync(data)
    local ok,id=sampGetPlayerIdByCharHandle(PLAYER_PED);if ok then shot(id,data)end
end
local function build()
    if not enabled()then clear();return end
    if getActiveInterior and getActiveInterior()~=0 then clear();return end
    if preview then
        local current=model.zones[preview.id];local old=preview.source
        if not current or current[1]~=old[1]or current[2]~=old[2]or current[3]~=old[3]or current[4]~=old[4]then preview=nil;clear()end
    end
    local source=preview and preview.model or model
    local x,y,z=getActiveCameraCoordinates()
    if not model.finite(x) or not model.finite(y) or not model.finite(z)then return end
    local now=getGameTimer()
    if buildEye and now<nextBuild and nextBuild-now<=2000 and revision==source.revision and buildModel==source
        and (x-buildEye[1])^2+(y-buildEye[2])^2+(z-buildEye[3])^2<64 then return end
    if revision~=source.revision or buildModel~=source then visibility:reset()end
    local sampleBoundary=c.style==13 and (not elevation or elevation.source~=source or elevation.revision~=source.revision)
    if sampleBoundary then elevation={source=source,revision=source.revision}end
    nextBuild=now+2000;revision=source.revision;buildModel=source;buildEye={x,y,z};lines={};panels={};meshDirty=true
    local cell=math.max(4,math.ceil(c.height/4))
    local ground={}
    local function point(px,py)
        local key=string.format('%.3f:%.3f',px,py)
        if ground[key]then return ground[key]end
        local ok,pz=pcall(getGroundZFor3dCoord,px,py,1000)
        if not ok or not model.finite(pz)then return end
        if c.style==13 then
            elevation.bottom=elevation.bottom and math.min(elevation.bottom,pz)or pz
            elevation.roof=elevation.roof and math.max(elevation.roof,pz)or pz
        end
        local p={px,py,pz+0.15};ground[key]=p;return p
    end
    if sampleBoundary then
        -- Sample the whole contour, independent of camera range. Bound the
        -- extra collision queries; subsequent builds only expand known bounds
        -- as streamed terrain becomes available, never shrink them on a turn.
        local edges=source:boundary();local length=0
        for _,edge in ipairs(edges)do length=length+math.abs(edge[3]-edge[1])+math.abs(edge[4]-edge[2])end
        local stride=math.max(10,length/512);local budget=1024
        for _,edge in ipairs(edges)do
            local n=math.max(1,math.ceil((math.abs(edge[3]-edge[1])+math.abs(edge[4]-edge[2]))/stride))
            for i=0,n do
                if budget<=0 then break end
                point(edge[1]+(edge[3]-edge[1])*i/n,edge[2]+(edge[4]-edge[2])*i/n)
                budget=budget-1
            end
            if budget<=0 then break end
        end
    end
    local beacons={}
    local function beacon(px,py,corner)
        if (px-x)^2+(py-y)^2>c.range*c.range or #lines>=7000 then return end
        local key=string.format('%.3f:%.3f',px,py)
        if beacons[key]then return end
        local p=point(px,py);if not p then return end
        beacons[key]=true;styles.beacon(p,corner,lines)
    end
    if c.style==10 or c.style==12 or c.style==13 then
        local corners={}
        for _,edge in ipairs(source:boundary())do
            for _,p in ipairs({{edge[1],edge[2]},{edge[3],edge[4]}})do
                local key=string.format('%.3f:%.3f',p[1],p[2])
                if not corners[key]then
                    corners[key]=true
                    if c.style==13 then
                        if (p[1]-x)^2+(p[2]-y)^2<=c.range*c.range then
                            local ground=point(p[1],p[2])
                            if ground then
                                local _,err=barrier.surfacePillar(ground,c.height,panels)
                                if err then panels={};barrierStatus='Слишком сложный контур территории. Уменьшите дальность границы.';return end
                            end
                        end
                    else beacon(p[1],p[2],true)end
                end
            end
        end
    end
    if c.style==12 then return end
    local segments,geometryError
    if c.style==13 then segments,geometryError=source:surfaceSegments(x,y,c.range+12,cell,2048)
    else segments=source:segments(x,y,c.range+12,c.step)end
    if geometryError then
        panels={};barrierStatus='Слишком сложный контур территории. Уменьшите дальность границы.';return
    end
    table.sort(segments,function(a,b)
        return ((a[1]+a[3])/2-x)^2+((a[2]+a[4])/2-y)^2<((b[1]+b[3])/2-x)^2+((b[2]+b[4])/2-y)^2
    end)
    for _,s in ipairs(segments)do
        local a,b=point(s[1],s[2]),point(s[3],s[4])
        if a and b then
            if c.style==13 then
                local _,err=barrier.surface(a,b,c.height,panels)
                if err then panels={};barrierStatus='Слишком сложный контур территории. Уменьшите дальность границы.';return end
            else styles.build(a,b,c.height,c.step,c.style+1,lines)end
            if c.style==10 then
                -- Anchor every ten metres to world coordinates, not the camera clip.
                local vertical=s[1]==s[3]
                local lo,hi=vertical and s[2]or s[1],vertical and s[4]or s[3]
                for v=math.ceil(lo/10)*10,hi,10 do
                    beacon(vertical and s[1]or v,vertical and v or s[2],false)
                end
            end
        end
    end
    if c.style==13 and elevation and elevation.bottom then
        local bottom,top=elevation.bottom,elevation.roof+c.barrier_height
        -- One shared vertical span for every wall and corner pillar. Roofs
        -- affect only the common ceiling, not individual sloping panels.
        for _,q in ipairs(panels)do
            q[1][3],q[2][3]=bottom,bottom
            q[3][3],q[4][3]=top,top
        end
    end
end
local function project(p)
    local visible,x,y,depth=convert3DCoordsToScreenEx(p[1],p[2],p[3],true,false)
    if visible and model.finite(x) and model.finite(y) and model.finite(depth) and depth>1 then return x,y end
end
local function visibleFrame()
    return enabled()and not isPauseMenuActive()and (not getActiveInterior or getActiveInterior()==0)
        and isGameWindowForeground()and not integration.layoutEditing()
end
local function camera()
    local x,y,z=getActiveCameraCoordinates()
    if model.finite(x)and model.finite(y)and model.finite(z)then return {x,y,z}end
end
local function updateNative()
    if c.style~=13 or not enabled()then if native then closeNative()end;return end
    local eye=camera()
    local active=not lost and visibleFrame()and #panels>0 and eye~=nil
    if not active and not native then return end
    if not native then
        if attempted or lost then return end
        attempted=true
        local ok,result=pcall(function()
            return integration.service('zonebarrier/native.lua').new(getD3DDevicePtr(),integration.base..'/zonebarrier')
        end)
        if not ok then
            barrierStatus='3D-барьер недоступен. Подробности в moonloader.log; можно выбрать другой вид границы.'
            nativeFailure=barrierStatus
            print('[X-Tools / Zone barrier] '..tostring(result));return
        end
        native=result;meshDirty=true
    end
    local ok,err=pcall(function()
        assert(native:error()==0,'Native error '..tostring(native:error()))
        if meshDirty then native:mesh(panels);meshDirty=false end
        native:update(eye or {0,0,0},c.range,c.color,active)
    end)
    if not ok then
        closeNative();attempted=true;barrierStatus='Отрисовка барьера остановлена после ошибки. Можно повторить запуск.'
        nativeFailure=barrierStatus
        print('[X-Tools / Zone barrier] '..tostring(err))
    end
end
local function diagnostics()
    local now=getGameTimer()
    if native and native.stats and now>=nextStats then
        nextStats=now+1000
        local ok,result=pcall(native.stats,native)
        if ok then nativeStats=result end
    end
    if not traceUntil then return end
    if now>traceUntil then traceUntil=nil;return end
    if now<nextTrace then return end
    nextTrace=now+1000
    local data={style=c.style,height=c.style==13 and c.barrier_height or c.height,range=c.range,color=c.color,panels=#panels,lines=#lines,
        visible=visibleFrame(),eye=camera(),preview=preview and preview.id or nil,native=nativeStats,
        nativeFailure=nativeFailure,revision=revision,rayChecks=visibility.used,queued=visibility.tail-visibility.head+1}
    if preview then data.bounds={preview.source[1],preview.source[2],preview.source[3],preview.source[4]}end
    local lo,hi
    for _,q in ipairs(panels)do for i=1,4 do local z=q[i][3];lo=lo and math.min(lo,z)or z;hi=hi and math.max(hi,z)or z end end
    data.minZ,data.maxZ=lo,hi
    local ok,value=pcall(encodeJson,data)
    if ok then print('[X-Tools / Zone trace] '..value)end
end
integration.update=function()watch();build();updateNative();diagnostics()end
sampRegisterChatCommand('atwall',function()
    startTrace()
    integration.message('Диагностика границы включена на 15 секунд. Включите нужный вид границы и поверните камеру. Состояние запишется в moonloader.log.')
end)
integration.onD3DDeviceLost=function()
    lost=true
    if native then native:lost()end
end
integration.onD3DDeviceReset=function()
    lost=false
    if native then
        local ok,err=pcall(native.reset,native)
        if not ok then closeNative();attempted=true;barrierStatus='Не удалось восстановить 3D-барьер. Повторите запуск.';nativeFailure=barrierStatus;print('[X-Tools / Zone barrier] '..tostring(err))end
    end
end
integration.onD3DPresent=function()
    if not visibleFrame()or c.style==13 then return end
    local eye=camera();if not eye then return end
    visibility:begin(eye,getGameTimer(),isLineOfSightClear)
    local color=c.color
    if c.style==9 then
        local alpha=math.floor(bit.band(bit.rshift(color,24),255)*(.65+.35*math.sin(getGameTimer()/350)))
        color=bit.bor(bit.band(color,0xFFFFFF),bit.lshift(alpha,24))
    end
    -- Subdivide legacy lines too, so an occluded endpoint does not hide an entire side.
    for _,line in ipairs(lines)do
        local a,b=line[1],line[2]
        local n=math.ceil(math.max(math.abs(b[1]-a[1]),math.abs(b[2]-a[2]),math.abs(b[3]-a[3]))/2)
        n=math.max(1,n)
        for i=1,n do
            local p,q={},{}
            for axis=1,3 do p[axis]=a[axis]+(b[axis]-a[axis])*(i-1)/n;q[axis]=a[axis]+(b[axis]-a[axis])*i/n end
            local x,y=project(p);local bx,by=project(q)
            if x and bx and visibility:line(p,q)then
                local tint=line.glow and bit.bor(bit.band(color,0xFFFFFF),0x30000000)or color
                renderDrawLine(x,y,bx,by,line[3]or 1,tint)
            end
        end
    end
end
-- The filled barrier is drawn in GTA's world pass, never in ImGui's HUD pass.
integration.hudActive=function()return false,false,false end
integration.drawHud=function()end
integration.drawSettings=function()
    local value=g.ImBool(c.enabled)
    if g.Checkbox('Граница активного квадрата капта',value)then c.enabled=value.v;closeNative();clear();integration.storage:saveIni(cfg,path)end
    if c.enabled then
    local style=g.ImInt(c.style)
    if g.Combo('Вид границы',style,styles.names,#styles.names)then c.style=style.v;closeNative();clear();save()end
    if c.style==13 then
        local height=g.ImInt(c.barrier_height)
        if g.SliderInt('Запас высоты над контуром',height,20,300)then c.barrier_height=height.v;clear();save()end
        g.TextWrapped('Ровное основание по нижней точке. Общий верх — выше самой высокой точки контура. По умолчанию запас 150 м.')
    end
    for _,row in ipairs({{'height','Высота границы',3,40},{'range','Дальность границы',30,400},{'step','Размер ячейки',3,20}})do
        if c.style<10 or row[1]=='range' then
        local v=g.ImInt(c[row[1]])
        if g.SliderInt(row[2],v,row[3],row[4])then c[row[1]]=v.v;clear();integration.storage:saveIni(cfg,path)end
        end
    end
    local ref=g.ImFloat4(g.ImColor(bit.band(bit.rshift(c.color,16),255),bit.band(bit.rshift(c.color,8),255),bit.band(c.color,255),bit.band(bit.rshift(c.color,24),255)):GetFloat4())
    if g.ColorEdit4('Цвет границы',ref)then
        c.color=bit.bor(bit.lshift(math.floor(ref.v[4]*255),24),bit.lshift(math.floor(ref.v[1]*255),16),bit.lshift(math.floor(ref.v[2]*255),8),math.floor(ref.v[3]*255));integration.storage:saveIni(cfg,path)
    end
    end
    if g.Button('Выделить ближайшую территорию для проверки')then
        if not integration.access:canUseTools()or sampGetGamestate()~=3 or getActiveInterior()~=0 then
            integration.message('Для проверки войдите в игру и выйдите из интерьера.')
        else
            local x,y=getActiveCameraCoordinates();local id,zone=model:nearest(x,y)
            if not id then integration.message('Сервер ещё не передал видимые территории. Может потребоваться переподключение.')
            else
                local isolated=integration.service('zone_wall.lua').new()
                isolated:observe('onCreateGangZone',id,{x=zone[1],y=zone[2]},{x=zone[3],y=zone[4]},zone.color)
                isolated:observe('onGangZoneFlash',id,0x80FFFFFF)
                preview={id=id,source=zone,model=isolated};clear();startTrace()
                integration.message('Тест границы территории #'..id..' включён. Предупреждения и отчёты используют только настоящий квадрат.')
            end
        end
    end
    if preview then
        if g.Button('Убрать тестовое выделение')then preview=nil;clear()end
        if preview then g.TextWrapped('Тест территории #'..preview.id..' · Только отображение, без событий квадрата.')end
    end
    if c.enabled or preview then
        if c.style==13 then
            if barrierStatus then
                g.TextWrapped(barrierStatus)
                if g.Button('Повторить запуск барьера')then closeNative();clear()end
            else
                g.TextDisabled('Поверхностей: '..#panels..' · Объёмная граница с перекрытием зданиями')
                if preview and nativeStats then
                    if nativeStats.drawSuccess==0 then g.TextWrapped('Геометрия построена, но пока нет отрисованных кадров. Диагностика проверки сохраняется в moonloader.log.')
                    else g.TextDisabled('Проверка: 3D-проход выполнен · Результат диагностики — в moonloader.log')end
                end
            end
        else g.TextDisabled('Проверок препятствий за кадр: '..visibility.used..'/192')end
    end
    if g.CollapsingHeader('Контроль входа и выхода из квадрата капта')then
        for _,row in ipairs({{'warn_enter','Предупреждать о входе в квадрат'},{'warn_exit','Предупреждать о выходе из квадрата'},{'warn_return','Предупреждать о возвращении за 5 секунд'},{'warn_late','Предупреждать, если не вернулся за 5 секунд'},{'warn_shots','Предупреждать о стрельбе через границу квадрата'}})do
            local flag=g.ImBool(c[row[1]])
            if g.Checkbox(row[2],flag)then c[row[1]]=flag.v;resetCrossings();save()end
        end
        g.TextWrapped('Только вне гетто: территории банд исключены из границ и предупреждений. Контролируется активная мигающая зона капта.')
        g.TextWrapped('Не вернулся за 5 секунд — отдельное предупреждение, один раз за выход. Если игрок вернулся, пропал из прорисовки или вышел из игры, ожидание отменяется.')
        g.TextWrapped('Отслеживаются другие игроки в прорисовке. Появление, исчезновение и выход из игры не считаются пересечением. Вход и выход работают независимо от видимости стенки.')
        g.TextWrapped('Стрельба: по полученным пакетам с указанным игроком-целью. Повтор для той же пары — раз в 3 секунды. Предупреждение требует проверки ситуации.')
    end
    local n=0;for _ in pairs(model:activeZones())do n=n+1 end
    g.Text('Активных зон капта: '..n)
    if n==0 then g.TextWrapped('Нет активной зоны капта. Обычную территорию можно выделить кнопкой проверки; контроль границ использует только настоящий квадрат.')end
    g.TextWrapped('Красный барьер повторяет внешний контур активной зоны: полупрозрачная поверхность и яркие столбы на углах. Участки за зданиями и объектами скрываются. Высота и прозрачность регулируются; столкновений нет.')
end
integration.stop=reset;integration.onDisconnect=reset;integration.onAccessChanged=reset
