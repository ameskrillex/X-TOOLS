"""Build the command updater fix from the immutable 3.5.210 release."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
base = ROOT / 'update/live/versions/3.5.210'
code = (base / 'X-TOOL.lua').read_text(encoding='utf-8')


def replace(old, new):
    global code
    assert code.count(old) == 1, (code.count(old), old[:100])
    code = code.replace(old, new)


replace("'update', function() self.updates:update() end)",
        "'update', function() self.updateCommandPending=true end)")
replace('function Runtime:checkUpdates(manual)', '''-- Chat callbacks only enqueue. Start updater work after the native callback returns.
function Runtime:processUpdateCommand()
    if not self.updateCommandPending then return end
    self.updateCommandPending=false
    if self.stopped then return end
    self:call(self:component('integration'),function() self.updates:update() end)
end

function Runtime:checkUpdates(manual)''')
replace('''    self.updateLoginPending=true
    self.api.lua_thread.create(function()
        while not self.stopped do
            self.api.wait(0)
            if self:checkSession()~=false then''', '''    self.updateLoginPending=true
    self.api.lua_thread.create(function()
        while not self.stopped do
            self.api.wait(0)
            self:processUpdateCommand()
            if self:checkSession()~=false then''')
replace('''    if rawget(self.api,'message') then self.api.message('Проверяем обновления X-Tools.''', '''    -- Match the menu's install action when startup/manual checking already found a release.
    -- Re-fetching the manifest here used a second worker and chained installation.
    if self:status().canInstall then
        if rawget(self.api,'message') then self.api.message('Устанавливаем найденное обновление X-Tools '..self.pending.version..'. Настройки сохранятся.') end
        return self:install()
    end
    if rawget(self.api,'message') then self.api.message('Проверяем обновления X-Tools.''')
replace("        hash=rt:service('sha256.lua'),", """        hash=function(bytes)
            return rt:service('sha256.lua')(bytes,function()
                api.wait(0)
                assert(not closed,'CasualTool stopped')
            end)
        end,
        log=function(text) api.print('[X-Tools Update] '..text) end,""")
replace('function Updates:verify(bytes,description)', '''function Updates:progress(text)
    if rawget(self.api,'log') then self.api.log(text) end
end
function Updates:verify(bytes,description)''')
replace('''        self.pending=nil
        local text=self.api.fetch''', '''        self.pending=nil
        self:progress('Checking manifest')
        local text=self.api.fetch''')
replace('''        local code=self:verify(self.api.fetch(base..manifest.script.file,manifest.script.bytes),manifest.script)''', '''        self:progress('Downloading script '..manifest.version)
        local code=self:verify(self.api.fetch(base..manifest.script.file,manifest.script.bytes),manifest.script)
        self:progress('Validating script '..manifest.version)''')
replace('''        local complete=true
        for _,file in ipairs(manifest.assets.files) do''', '''        self:progress('Checking installed resources')
        local complete=true
        for _,file in ipairs(manifest.assets.files) do''')
replace('''        if not complete then
            local pack=self:verify''', '''        if not complete then
            self:progress('Downloading resource pack')
            local pack=self:verify''')
replace('''            -- Verify every resource before writing the first resource file.''', '''            self:progress('Validating and installing resource pack')
            -- Verify every resource before writing the first resource file.''')
replace('''        self:commit(code)
        self.state,self.detail='installed',''', '''        self:progress('Committing verified release')
        self:commit(code)
        self:progress('Release committed; scheduling script reload')
        self.state,self.detail='installed',''')

code = code.replace('3.5.210', '3.5.211').encode('utf-8')
manifest = json.loads((base / 'manifest.json').read_text(encoding='utf-8'))
manifest.update(version='3.5.211', packagePath='versions/3.5.211/')
manifest['script'].update(bytes=len(code), sha256=hashlib.sha256(code).hexdigest())
encoded = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
for folder in (ROOT / 'update/live', ROOT / 'update/live/versions/3.5.211'):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'X-TOOL.lua').write_bytes(code)
    (folder / 'manifest.json').write_bytes(encoded)
    shutil.copyfile(base / 'assets.pack', folder / 'assets.pack')
(ROOT / 'X-TOOL.lua').write_bytes(code)
print(json.dumps(manifest['script']))
