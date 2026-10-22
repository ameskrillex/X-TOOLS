-- X-TOOLS | Project and integration: Casual_Alvarez | Module: art.lua
-- Original third-party credits, where present, are retained below.
-- Local artwork only. No downloads and no repeated file I/O in a rendered frame.
local Art = {}
-- Generated monochrome glass panel, tinted with the active interface palette.
Art.__index = Art
local files = {['loading-title']={2172,724},['status-toast']={2172,724},observation={1254,1254},hero={2172,724},['xtools-background']={1586,992},['xtools-logo']={1254,1254}}
files['teleport-banner']={2172,724}
files['gameplay-icon']={1024,1024}
files['event-notice']={2172,724}
files['loading-frame']={2172,724}
files['profile-card']={2172,724}
files['dashboard-panel']={1254,1254}
files['lookup-header']={2048,768}
files['punishment-header']={2172,724}
files['adminzone-button']={2172,724}
files['legends-banner']={2172,724}
files['legends-directory']={2172,724}
for _,id in ipairs({'aurora','ember','jade','ruby','cosmos'}) do
    files['theme-'..id..'-loading']={2172,724}
    files['theme-'..id..'-logo']={1254,1254}
    files['theme-'..id..'-background']={1536,1024}
end
local instances={}
local frame=0
local refresh=false
local budget=64*1024*1024
function Art.new(imgui,base,api)
    local self=setmetatable({imgui=imgui,base=base,api=api,cache={},attempted={},retry={},failures={}},Art)
    instances[self]=true
    return self
end
-- Retire unused resources at frame boundaries; visible cards keep their handles.
function Art.shutdownAll()
    for self in pairs(instances) do self:shutdown() end
end
function Art.refreshAll() refresh=true end
function Art.beginFrame()
    frame=frame+1
    local total,candidates=0,{}
    for self in pairs(instances)do
        for name,item in pairs(self.cache)do
            local bytes=item.width*item.height*4
            total=total+bytes
            if refresh or (item.lastFrame or 0)<frame-2 then
                candidates[#candidates+1]={owner=self,name=name,item=item,bytes=bytes}
            end
        end
    end
    table.sort(candidates,function(a,b)return (a.item.lastFrame or 0)<(b.item.lastFrame or 0)end)
    for _,entry in ipairs(candidates)do
        if not refresh and total<=budget then break end
        local self=entry.owner
        pcall(self.imgui.ReleaseTexture,entry.item.texture)
        self.cache[entry.name]=nil;self.attempted[entry.name]=nil
        self.retry[entry.name]=nil;self.failures[entry.name]=nil
        total=total-entry.bytes
    end
    refresh=false
end
function Art:get(name)
    local now=type(self.api.getGameTimer)=='function' and self.api.getGameTimer()/1000 or os.clock()
    if self.retry[name] and now>=self.retry[name] then self.attempted[name]=nil;self.retry[name]=nil end
    if self.attempted[name] then
        if self.cache[name]then self.cache[name].lastFrame=frame end
        return self.cache[name]
    end
    self.attempted[name]=true
    local size=files[name]
    if not size then return end
    local ok,value=pcall(function()
        local file=self.api.io.open(self.base..'/art/'..name..'.png','rb')
        if not file then error('art file unavailable') end
        local bytes=file:read('*a'); file:close()
        local ffi=self.api.require('ffi')
        local data=ffi.new('uint8_t[?]',#bytes)
        ffi.copy(data,bytes,#bytes)
        local texture=self.imgui.CreateTextureFromMemory(tonumber(ffi.cast('uintptr_t',data)),#bytes)
        -- MoonImGui 1.1.2 returns lightuserdata NULL on D3DX failure. It is
        -- truthy and is neither Lua nil nor numeric zero; drawing it is a
        -- solid tint rectangle. Check the native address before caching it.
        if texture==nil or texture==false or texture==0 then error('texture creation returned no texture') end
        if type(texture)=='userdata' or type(texture)=='cdata' then
            assert(tonumber(ffi.cast('uintptr_t',texture))~=0,'texture creation returned NULL')
        end
        return {texture=texture,width=size[1],height=size[2],lastFrame=frame}
    end)
    if ok then
        self.cache[name]=value;self.failures[name]=nil
    else
        local count=(self.failures[name] or 0)+1;self.failures[name]=count
        self.retry[name]=now+math.min(60,10*count)
        if count==1 and type(self.api.print)=='function' then
            self.api.print('[X-Tools Art] '..name..': '..tostring(value)..'; retry in 10 seconds')
        end
    end
    return self.cache[name]
end
function Art:shutdown()
    for _,item in pairs(self.cache) do pcall(self.imgui.ReleaseTexture,item.texture) end
    self.cache={};self.attempted={};self.retry={};self.failures={}
    instances[self]=nil
end
return Art
