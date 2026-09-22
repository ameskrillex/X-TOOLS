"""Reduce optional artwork retention and nearby statue load."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
base = ROOT / 'update/live/versions/3.5.211'
code = (base / 'X-TOOL.lua').read_text(encoding='utf-8')


def replace(old, new):
    global code
    assert code.count(old) == 1, (code.count(old), old[:80])
    code = code.replace(old, new)


replace('''function Art.new(imgui,base,api)
    return setmetatable({imgui=imgui,base=base,api=api,cache={},attempted={}},Art)
end
function Art:get(name)
    if self.attempted[name] then return self.cache[name] end''', '''local instances={}
local IDLE_MS=15000
function Art.new(imgui,base,api)
    local self=setmetatable({imgui=imgui,base=base,api=api,cache={},attempted={},lastUsed={}},Art)
    instances[self]=true
    return self
end
-- Run before a new ImGui frame, or while ImGui processing is disabled.
-- Never release a texture from get(): the current draw list may reference it.
function Art.collect(now)
    for self in pairs(instances) do
        for name,item in pairs(self.cache) do
            local used=self.lastUsed[name] or now
            if now<used then self.lastUsed[name]=now
            elseif now-used>=IDLE_MS then
                local ok,result=pcall(self.imgui.ReleaseTexture,item.texture)
                if ok and result~=false then
                    self.cache[name]=nil;self.attempted[name]=nil;self.lastUsed[name]=nil
                end
            end
        end
    end
end
function Art.shutdownAll()
    for self in pairs(instances) do self:shutdown() end
end
function Art:get(name)
    self.lastUsed[name]=self.api.getGameTimer()
    if self.attempted[name] then return self.cache[name] end''')
replace('''function Art:shutdown()
    for _,item in pairs(self.cache) do pcall(self.imgui.ReleaseTexture,item.texture) end
    self.cache={}
end''', '''function Art:shutdown()
    for _,item in pairs(self.cache) do pcall(self.imgui.ReleaseTexture,item.texture) end
    self.cache={};self.attempted={};self.lastUsed={}
    instances[self]=nil
end''')
replace("                if key == 'BeforeDrawFrame' then\n", "                if key == 'BeforeDrawFrame' then\n                    self:service('art.lua').collect(self.api.getGameTimer())\n")
replace('''            self:processUpdateCommand()
            if self:checkSession()~=false then''', '''            self:processUpdateCommand()
            if not self.imgui.Process then self:service('art.lua').collect(self.api.getGameTimer()) end
            if self:checkSession()~=false then''')
replace('    if self.art then self.art:shutdown() end', "    self:service('art.lua').shutdownAll()")
replace('limit=40,radius=450,count=0,failed=0', 'limit=20,radius=150,count=0,failed=0')
replace('    scene.radius=450\n', '    scene.radius=150\n')
replace('preload 450; ped limit 40', 'preload 150; ped limit 20')

code = code.replace('3.5.211', '3.5.212').encode('utf-8')
manifest = json.loads((base / 'manifest.json').read_text(encoding='utf-8'))
manifest.update(version='3.5.212', packagePath='versions/3.5.212/')
manifest['script'].update(bytes=len(code), sha256=hashlib.sha256(code).hexdigest())
encoded = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
for folder in (ROOT / 'update/live', ROOT / 'update/live/versions/3.5.212'):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'X-TOOL.lua').write_bytes(code)
    (folder / 'manifest.json').write_bytes(encoded)
    shutil.copyfile(base / 'assets.pack', folder / 'assets.pack')
(ROOT / 'X-TOOL.lua').write_bytes(code)
print(json.dumps(manifest['script']))
