-- CasualTool release: 3.5.203
-- CasualTool assets: b574811553794a3aacdf58a434ea5f91061940839d835db74ea6dd8a6530deac
local sources={}
sources["updates.lua"] = function()
-- X-TOOLS | Project and integration: Casual_Alvarez | Module: updates.lua
-- Original third-party credits, where present, are retained below.
-- One release, one transaction. Configuration and user data are never targets.
local Updates = {}
Updates.__index = Updates
local MAX_CODE,MAX_ASSETS,MAX_MANIFEST=8*1024*1024,96*1024*1024,512*1024
local function integer(n,limit) return type(n)=='number' and n>=0 and n<=limit and n==math.floor(n) end
local function digest(s) return type(s)=='string' and #s==64 and s:match('^[0-9a-f]+$') end
local function version(s)
    if type(s)~='string' then return end
    local a,b,c=s:match('^(%d+)%.(%d+)%.(%d+)$')
    if a and #a<=6 and #b<=6 and #c<=6 then return {tonumber(a),tonumber(b),tonumber(c)} end
end
local function newer(candidate,current)
    local a,b=version(candidate),version(current)
    if not a or not b then return false end
    for i=1,3 do if a[i]~=b[i] then return a[i]>b[i] end end
    return false
end
local function safePath(path)
    if type(path)~='string' or #path>180 or not path:match('^[%w_/%.-]+$') then return false end
    if path:sub(1,1)=='/' or path:sub(-1)=='/' or path:find('//',1,true) then return false end
    for part in path:gmatch('[^/]+') do
        if part=='.' or part=='..' or part:sub(-1)=='.' then return false end
        local stem=part:match('^[^.]+')
        if not stem then return false end
        stem=stem:upper()
        if stem=='CON' or stem=='PRN' or stem=='AUX' or stem=='NUL' or stem:match('^COM[1-9]$') or stem:match('^LPT[1-9]$') then return false end
    end
    local extension=path:match('%.([%w]+)$')
    -- Only this bundled, manifest-hashed native renderer is an executable asset.
    if path=='beautifulsky/xt_sky.dll' then return true end
    return extension=='png' or extension=='ttf' or extension=='pem' or extension=='json' or extension=='md' or extension=='txt'
end
local function endpoint(url)
    if type(url)~='string' or url:find('..',1,true) then return end
    return url:match('^(https://[%w%.%-]+/[%w%._/%-]*/)[%w_.%-]+%.json$') or
        url:match('^(https://[%w%.%-]+/)[%w_.%-]+%.json$')
end
local function descriptor(file,name,maxBytes)
    assert(type(file)=='table' and file.file==name and digest(file.sha256) and integer(file.bytes,maxBytes) and file.bytes>0,'Invalid release file descriptor')
end
function Updates.validate(manifest,hash)
    assert(type(manifest)=='table' and manifest.schema==1 and manifest.product=='CasualTool' and version(manifest.version),'Invalid CasualTool manifest')
    assert(manifest.packagePath==nil or manifest.packagePath=='versions/'..manifest.version..'/','Invalid release package path')
    descriptor(manifest.script,'X-TOOL.lua',MAX_CODE)
    descriptor(manifest.assets,'assets.pack',MAX_ASSETS)
    local assets=manifest.assets
    assert(digest(assets.id) and type(assets.files)=='table' and #assets.files>0 and #assets.files<=2048,'Invalid resources')
    local seen,offset,identity={},6,{}
    for _,file in ipairs(assets.files) do
        assert(type(file)=='table' and safePath(file.path) and not seen[file.path:lower()],'Invalid or duplicate resource path')
        seen[file.path:lower()]=true
        assert(digest(file.sha256) and integer(file.bytes,MAX_ASSETS) and file.offset==offset,'Invalid resource span')
        offset=offset+file.bytes
        identity[#identity+1]=file.path..'\0'..string.format('%.0f',file.bytes)..'\0'..file.sha256..'\n'
        assert(offset<=assets.bytes,'Resource exceeds pack')
    end
    assert(offset==assets.bytes,'Incomplete resource pack')
    assert(hash(table.concat(identity)..assets.sha256)==assets.id,'Resource identity mismatch')
    return manifest
end
function Updates.new(api,host,release)
    api,host,release=api or {},host or {},release or {}
    local source=release.updateUrl
    if source=='' then source=nil end
    local current=tostring(host.version or '')
    if current:match('^%s*$') then current='не указана' end
    local self=setmetatable({api=api,host=host,version=current,source=source,release=release,
        state=source and 'idle' or 'unconfigured',settings={automatic=true}},Updates)
    if rawget(api,'loadSettings') then self.settings=api.loadSettings() end
    self.backupAvailable=release.bundled and host.path and rawget(api,'read') and api.read(host.path..'.bak')~=nil or false
    return self
end
function Updates:status()
    local titles={unconfigured='Источник обновлений не настроен',idle='Можно проверить обновления',
        checking='Проверка обновлений…',available='Доступна новая версия',current='Установлена актуальная версия',
        installing='Подготовка обновления…',installed='Обновление установлено',error='Обновление не выполнено',
        reload_required='Требуется перезапуск',restored='Предыдущая версия восстановлена',stopped='X-Tools остановлен'}
    return {state=self.state,version=self.version,source=self.source,automatic=self.settings.automatic==true,
        canReload=self.awaitingReload and not self.reloadRunning and not self.stopped,
        canCheck=not self.awaitingReload and not self.busy and not self.stopped and endpoint(self.source)~=nil,
        canInstall=not self.stopped and not self.awaitingReload and self.state=='available' and not self.busy and self.release.bundled==true,
        title=titles[self.state] or self.state,detail=self.detail or (self.source and 'Настройки и журналы сохраняются при обновлении.' or
        'Адрес публикации пока оставлен пустым. Фоновых запросов и скачивания нет.'),
        candidate=self.pending and self.pending.version,
        instructions={'Для первой установки распакуйте полный архив X-Tools в moonloader.',
            'В выпуске один X-TOOL.lua; изображения и шрифты находятся в resource/X-TOOL.',
            'При обновлении сохраняются настройки и журналы в X-TOOL.',
            'Предыдущий Lua-файл сохраняется рядом как X-TOOL.lua.bak; прежние ресурсы сохраняются для отката.'}}
end
function Updates:retryReload()
    if self.stopped or not self.awaitingReload or self.reloadRunning then return false end
    self.reloadRunning=true
    local function finished(ok,err)
        self.reloadRunning=false
        if self.stopped then return end
        self.state='reload_required'
        self.detail='Файлы установлены. Если скрипт не перезапустился, нажмите «Повторить перезапуск».'
        if not ok then
            if rawget(self.api,'errorReason')then self.api.errorReason(err)end
            self.detail='Файлы установлены, но скрипт не перезапустился. Нажмите «Повторить перезапуск» или полностью перезапустите игру. Подробности: moonloader.log.'
        end
    end
    local ok,result=pcall(function()
        assert(type(rawget(self.api,'reload'))=='function','Перезапуск недоступен')
        return self.api.reload(finished)
    end)
    if not ok then finished(false,result)
    elseif result~='pending' then
        self.reloadRunning=false
        if result==false then finished(false,'Перезапуск отклонён') end
    end
    return ok
end
function Updates:job(state,fn,onSuccess)
    if self.busy or self.stopped or self.awaitingReload then return false end
    self.busy,self.state,self.detail=true,state,nil
    local function run()
        if self.stopped then self.busy=false; return end
        local ok,err=xpcall(fn,function(e) return tostring(e) end)
        self.busy=false
        if not ok and not self.stopped then
            self.state,self.detail='error','Не удалось завершить обновление.\n'..(rawget(self.api,'errorReason')and self.api.errorReason(err)or 'Подробности записаны в moonloader.log.\nПовторите попытку или перезапустите игру.')
            if rawget(self.api,'message') then self.api.message(self.detail) end
        elseif ok and not self.stopped and onSuccess then
            onSuccess()
        end
    end
    local ok,err=pcall(self.api.run,run)
    if not ok then self.busy=false; self.state='error'; self.detail='Не удалось запустить обновление. '..(rawget(self.api,'errorReason')and self.api.errorReason(err)or 'Перезапустите игру и повторите попытку.') end
    return ok
end
function Updates:check(manual,installAfterCheck)
    if not self.source then
        if manual~=false and rawget(self.api,'message') then self.api.message('X-Tools '..self.version..': источник обновлений не настроен.\nУстановите полный архив X-Tools с GitHub.') end
        return self:status()
    end
    if not endpoint(self.source) then self.state='error'; self.detail='Нужен прямой HTTPS-адрес manifest.json.'; return self:status() end
    self:job('checking',function()
        self.pending=nil
        local text=self.api.fetch(self.source,MAX_MANIFEST)
        assert(#text<=MAX_MANIFEST,'Manifest is too large')
        local manifest=Updates.validate(self.api.decode(text),self.api.hash)
        assert(version(self.version),'Installed version is invalid')
        if newer(manifest.version,self.version) then
            self.pending=manifest; self.state='available'
            if rawget(self.api,'message') then
                self.api.message('Ваша версия: '..self.version..'. Доступно обновление: '..manifest.version..'.\n'..
                    (installAfterCheck and 'Начинается установка обновления.' or 'Введите /update для установки или откройте /casualupdate.'))
            end
        else
            self.state='current'
            if manifest.version==self.version and (manual~=false or self.settings.automatic) and rawget(self.api,'message')then
                self.api.message('Вы используете актуальную версию X-Tools '..self.version..'.')
            end
        end
        if manual==false and rawget(self.api,'onStartupResult')then
            pcall(self.api.onStartupResult,self.state,self.version,manifest.version)
        end
    end,installAfterCheck and function() self:install() end or nil)
    return self:status()
end
function Updates:update()
    if self.stopped then return false end
    if self.awaitingReload then return self:retryReload() end
    if self.busy then
        if rawget(self.api,'message') then self.api.message('Проверка или установка уже выполняется. Дождитесь завершения и повторите /update.') end
        return false
    end
    if rawget(self.api,'message') then self.api.message('Проверяем обновления X-Tools. Новая версия будет установлена автоматически; настройки сохранятся.') end
    return self:check(true,true)
end
function Updates:start()
    if endpoint(self.source) then self:check(false) end
end
function Updates:stop()
    self.stopped=true
    if rawget(self.api,'cancel') then self.api.cancel() end
    self.state='stopped'
end
function Updates:pause()
    assert(not self.stopped,'CasualTool stopped')
    if rawget(self.api,'yield') then self.api.yield() end
    assert(not self.stopped,'CasualTool stopped')
end
function Updates:verify(bytes,description)
    assert(type(bytes)=='string' and #bytes==description.bytes and self.api.hash(bytes)==description.sha256,'Release integrity check failed')
    return bytes
end
function Updates:write(path,bytes)
    assert(self.api.write(path,bytes),'Cannot write '..path)
    assert(self.api.read(path)==bytes,'Write verification failed: '..path)
end
function Updates:commit(bytes)
    local path=self.host.path
    assert(type(path)=='string' and path:match('[/\\][^/\\]+%.lua$'),'Invalid script path')
    local old=assert(self.api.read(path),'Installed script is missing')
    assert(self.api.compile(old),'Cannot back up invalid installed Lua')
    local nextPath,previous=path..'.update-new',path..'.previous'
    self.cleanupWarning=nil
    local stale=self.api.read(previous)
    if stale~=nil then
        -- A completed commit leaves the same old bytes in .bak and .previous.
        -- Unknown recovery files must never be discarded automatically.
        assert(stale==self.api.read(path..'.bak') and self.api.compile(stale),
            'An interrupted transaction exists; restore the .previous file first')
        assert(self.api.remove(previous) and self.api.read(previous)==nil,
            'Cannot remove completed transaction .previous; close programs locking it and retry')
    end
    self:write(nextPath,bytes)
    self:write(path..'.bak',old)
    self.backupAvailable=true
    self:pause()
    assert(self.api.rename(path,previous),'Cannot preserve installed script')
    -- No yields between removing the old filename and committing/restoring it.
    local ok,reason=pcall(function()
        assert(self.api.rename(nextPath,path),'Cannot install staged script')
        assert(self.api.read(path)==bytes,'Installed script verification failed')
    end)
    if not ok then
        local removed=self.api.read(path)==nil or self.api.remove(path)
        local restored=removed and self.api.rename(previous,path)
        restored=restored and self.api.read(path)==old
        assert(restored,'Commit and rollback failed. Restore '..path..'.bak manually')
        error(reason)
    end
    local cleaned=self.api.remove(previous)
    if not cleaned or self.api.read(previous)~=nil then
        self.cleanupWarning=' Не удалось удалить .previous; резервная копия сохранена. Очистка повторится при следующей установке или откате.'
    end
end
function Updates:install()
    if not self:status().canInstall then return false end
    local manifest=self.pending
    return self:job('installing',function()
        local base=assert(endpoint(self.source))..(manifest.packagePath or '')
        local code=self:verify(self.api.fetch(base..manifest.script.file,manifest.script.bytes),manifest.script)
        assert(code:sub(1,3)~='\27LJ','Invalid release Lua: bytecode is not supported')
        local compiled,compileError=self.api.compile(code)
        assert(compiled,'Invalid release Lua: '..tostring(compileError or 'compiler returned no details'))
        compiled=nil
        assert(code:find('-- CasualTool release: '..manifest.version..'\n',1,true)==1,'Release version mismatch')
        assert(code:find('-- CasualTool assets: '..manifest.assets.id..'\n',1,true),'Resource version mismatch')
        local root=assert(self.host.path:match('^(.*)[/\\]'))..'/resource/X-TOOL/'..manifest.assets.id
        local complete=true
        for _,file in ipairs(manifest.assets.files) do
            local bytes=self.api.read(root..'/'..file.path)
            if not bytes or #bytes~=file.bytes or self.api.hash(bytes)~=file.sha256 then complete=false end
            self:pause()
        end
        if not complete then
            local pack=self:verify(self.api.fetch(base..manifest.assets.file,manifest.assets.bytes),manifest.assets)
            assert(pack:sub(1,6)=='CTAS1\n','Invalid resource pack')
            -- Verify every resource before writing the first resource file.
            for _,file in ipairs(manifest.assets.files) do
                self:verify(pack:sub(file.offset+1,file.offset+file.bytes),file); self:pause()
            end
            for _,file in ipairs(manifest.assets.files) do
                local path=root..'/'..file.path
                assert(self.api.ensure(path:match('^(.*)/[^/]+$')))
                self:write(path,pack:sub(file.offset+1,file.offset+file.bytes)); self:pause()
            end
        end
        self:commit(code)
        self.state,self.detail='installed','Установлена версия '..manifest.version..'. X-Tools перезагрузится; настройки сохранены. После обновления рекомендуется полностью перезапустить игру, даже если скрипт работает нормально.'
        self.detail=self.detail..(self.cleanupWarning or '')
        self.awaitingReload=true
        self:retryReload()
    end)
end
function Updates:rollback()
    if self.busy or self.stopped or not self.release.bundled then return false end
    return self:job('installing',function()
        local bytes=assert(self.api.read(self.host.path..'.bak'),'No previous release')
        assert(bytes:match('^%-%- CasualTool release: %d+%.%d+%.%d+\n') and self.api.compile(bytes),'Invalid backup')
        self:commit(bytes)
        self.state,self.detail='restored','Предыдущая версия восстановлена. X-Tools перезагрузится.'
        self.detail=self.detail..(self.cleanupWarning or '')
        self.awaitingReload=true
        self:retryReload()
    end)
end
function Updates:draw(g,rt)
    if rawget(self.api,'drawDependencies') then self.api.drawDependencies(g) end
    local state=self:status()
    if rt then
        local pos=g.GetCursorScreenPos();local width=math.min(600,g.GetContentRegionAvailWidth());local height=math.max(130,width/3)
        rt:service('loading_card.lua').draw(rt,pos.x,pos.y,width,height,'X-TOOLS · '..state.version,state.title,1,self.busy)
        g.Dummy(g.ImVec2(width,height));g.Spacing()
    end
    g.TextWrapped('Версия X-Tools: '..state.version)
    g.TextWrapped(state.title); g.TextWrapped(state.detail)
    if state.candidate then g.TextWrapped('Новая версия: '..state.candidate) end
    g.Spacing()
    g.TextWrapped('После каждого обновления X-Tools рекомендуется полностью перезапускать игру, даже если установка прошла успешно и скрипт работает нормально.')
    g.TextWrapped('Если обновление не удалось или после него игра вылетела, запустите игру заново. Если игра осталась открытой — полностью закройте её и зайдите снова.')
    if self.source and rawget(self.api,'saveSettings') then
        self.automaticBox=self.automaticBox or g.ImBool(self.settings.automatic==true)
        if g.Checkbox('Сообщать в чате об актуальной версии при запуске##release_auto',self.automaticBox) then
            local wanted=self.automaticBox.v
            if self.api.saveSettings({automatic=wanted}) then self.settings.automatic=wanted
            else self.automaticBox.v=self.settings.automatic==true end
        end
        g.TextWrapped('Версия проверяется при каждом запуске. Результат появляется в центре экрана на 2 секунды. Предупреждение об устаревшей версии показывается всегда. Галочка управляет только сообщением об актуальной версии в чате. Установка — по кнопке ниже или командой /update.')
    end
    g.Spacing()
    if g.CollapsingHeader('Установка и восстановление##release_instructions') then
        for i,text in ipairs(state.instructions) do g.TextWrapped(i..'. '..text) end
    end
    if not self.busy and not self.awaitingReload and g.Button('Проверить обновления##casual_updates_status') then self:check(true) end
    if state.canReload and g.Button('Повторить перезапуск##release_retry_reload') then self:retryReload() end
    if state.canInstall and g.Button('Установить и перезагрузить##release_install') then self:install() end
    if self.backupAvailable and not self.busy and not self.awaitingReload and
        g.Button('Вернуть предыдущую версию##release_rollback') then self:rollback() end
end
return Updates

end
sources["update_adapter.lua"] = function()
-- X-TOOLS | Project and integration: Casual_Alvarez | Module: update_adapter.lua
-- Original third-party credits, where present, are retained below.
-- Updater I/O. Workers return bytes only; only the app commits a release.
local Adapter = {}
function Adapter.new(rt)
    local api,storage=rt.api,rt.storage
    local settingsPath=storage:path('settings','release.ini')
    local worker,closed
    local function read(path)
        local file=api.io.open(path,'rb')
        if not file then return nil end
        local bytes=file:read('*a'); file:close(); return bytes
    end
    local function write(path,bytes)
        local file,err=api.io.open(path,'wb')
        if not file then return nil,err end
        local ok,why=file:write(bytes)
        local done,closeError=file:close()
        if not ok or not done then return nil,why or closeError end
        return read(path)==bytes,'Written bytes failed verification'
    end
    local function ensure(path)
        if api.doesDirectoryExist(path) then return true end
        local parent=path:match('^(.*)[/\\][^/\\]+$')
        if parent then assert(ensure(parent)) end
        api.createDirectory(path)
        assert(api.doesDirectoryExist(path),'Cannot create resource directory: '..path)
        return true
    end
    return {
        message=function(text) rt:message(text) end,
        onStartupResult=function(state,version,candidate)rt.updateNotice:show(state,version,candidate)end,
        errorReason=function(err)
            api.print('[X-Tools Update ERROR] '..tostring(err))
            return rt:service('user_messages.lua').reason(err)
        end,
        drawDependencies=function(g)
            if not rt.dependencies then
                local raw=read(rt.base..'/assets/dependencies.json')
                if not raw then g.TextWrapped('Каталог библиотек отсутствует. Установите полный архив X-Tools.');return end
                local catalog=api.decodeJson(raw)
                local sha=rt:service('sha256.lua')
                rt.dependencies=rt:service('dependencies.lua').new(api,catalog,function(bytes)return sha(bytes,api.wait)end,function(text)rt:message(text)end)
            end
            rt.dependencies:draw(g)
        end,
        read=read, write=write, ensure=ensure,
        remove=function(path) if read(path)==nil then return true end; return api.os.remove(path) end,
        rename=function(from,to) return api.os.rename(from,to) end,
        compile=function(bytes) return loadstring(bytes,'@CasualTool/update-validation') end,
        hash=rt:service('sha256.lua'),
        decode=function(text) return api.decodeJson(text) end,
        loadSettings=function() return storage:loadIni({release={automatic=true}},settingsPath).release end,
        saveSettings=function(values) return storage:saveIni({release=values},settingsPath) end,
        run=function(fn) api.lua_thread.create(function() api.wait(0); if not closed then fn() end end) end,
        yield=function() api.wait(0); assert(not closed,'CasualTool stopped') end,
        cancel=function()
            closed=true
            if worker then pcall(function() worker:cancel() end); worker=nil end
        end,
        reload=function(finished)
            api.lua_thread.create(function()
                api.wait(500)
                if closed then return end
                local ok,result=pcall(function()
                    assert(type(rt.host.reload)=='function','Перезапуск недоступен')
                    rt:prepareReload()
                    -- Let MoonImGui's cursor coroutine observe the disabled flags before unload.
                    api.wait(0)
                    if closed then return false end
                    rt:releaseReloadInput(rt.reloadOwnedInput)
                    return rt.host:reload()
                end)
                if not ok or result==false then rt.reloading=false;rt:syncGui()end
                if finished then finished(ok and result~=false,ok and 'Перезапуск отклонён' or result) end
            end)
            return 'pending'
        end,
        fetch=function(url,limit)
            assert(not closed,'CasualTool stopped')
            -- The mutable manifest must not reuse GitHub's five-minute CDN cache.
            if url:match('/manifest%.json$')then url=url..'?xt='..tostring(api.os.time())..'-'..tostring(api.getGameTimer()) end
            local effil=api.require('effil')
            local transport=string.dump(assert(rt:source('discord_transport.lua')))
            worker=effil.thread(function(code,address,caFile,maxBytes)
                local client=assert(loadstring(code,'@CasualTool/release-https'))()
                return client.get(address,caFile,maxBytes)
            end)(transport,url,rt.base..'/assets/cacert.pem',limit)
            local deadline=api.os.time()+90
            while not closed do
                local state=worker:status()
                if state=='completed' then
                    local ok,status,body,_,err=worker:get()
                    worker=nil
                    assert(ok and status==200,'HTTPS '..tostring(status)..': '..tostring(err or 'download failed'))
                    assert(type(body)=='string' and #body<=limit,'Invalid release response')
                    return body
                end
                if state=='failed' or state=='canceled' or state=='cancelled' or api.os.time()>deadline then
                    pcall(function() worker:cancel() end); worker=nil
                    error('Release download failed or timed out')
                end
                api.wait(50)
            end
            error('CasualTool stopped')
        end
    }
end
return Adapter

end
sources["sha256.lua"] = function()
-- X-TOOLS | Project and integration: Casual_Alvarez | Module: sha256.lua
-- Original third-party credits, where present, are retained below.
-- SHA-256 over byte strings. LuaJIT bit operations; no external hashing package.
local bit = require 'bit'
local band, bxor, bnot, rshift, ror = bit.band, bit.bxor, bit.bnot, bit.rshift, bit.ror
local constants = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
}
local function word(n)
    return string.char(band(rshift(n,24),255),band(rshift(n,16),255),band(rshift(n,8),255),band(n,255))
end
return function(bytes, yield)
    local length=#bytes
    bytes=bytes..'\128'..string.rep('\0',(55-length)%64)..word(math.floor(length/536870912))..word(length*8)
    local hash={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
    local words={}
    for offset=1,#bytes,64 do
        if yield and offset % 65536 == 1 then yield(0) end
        for i=0,15 do
            local a,b,c,d=bytes:byte(offset+i*4,offset+i*4+3)
            words[i]=bit.tobit(((a*256+b)*256+c)*256+d)
        end
        for i=16,63 do
            local x,y=words[i-15],words[i-2]
            words[i]=bit.tobit(words[i-16]+bxor(ror(x,7),ror(x,18),rshift(x,3))+words[i-7]+bxor(ror(y,17),ror(y,19),rshift(y,10)))
        end
        local a,b,c,d,e,f,g,h=unpack(hash)
        for i=0,63 do
            local first=bit.tobit(h+bxor(ror(e,6),ror(e,11),ror(e,25))+bxor(band(e,f),band(bnot(e),g))+constants[i+1]+words[i])
            local second=bit.tobit(bxor(ror(a,2),ror(a,13),ror(a,22))+bxor(band(a,b),band(a,c),band(b,c)))
            h,g,f,e,d,c,b,a=g,f,e,bit.tobit(d+first),c,b,a,bit.tobit(first+second)
        end
        local final={a,b,c,d,e,f,g,h}
        for i=1,8 do hash[i]=bit.tobit(hash[i]+final[i]) end
    end
    local result={}
    for i=1,8 do result[i]=bit.tohex(hash[i]) end
    return table.concat(result)
end

end
sources["discord_transport.lua"] = function()
-- X-TOOLS | Project and integration: Casual_Alvarez | Module: discord_transport.lua
-- Original third-party credits, where present, are retained below.
-- LuaSec 0.6-compatible HTTPS with chain AND DNS identity validation.
-- Primary API: https://github.com/lunarmodules/luasec/wiki/LuaSec-0.6
-- SAN layout: cert:extensions()['2.5.29.17'].dNSName (LuaSec src/x509.c).
local M = {}

function M.hostnameMatches(host, name)
    if type(host) ~= 'string' or type(name) ~= 'string' or name:find('%z') then return false end
    host, name = host:lower(), name:lower()
    if host == name then return true end
    local suffix = name:match('^%*%.([%w%-]+%.[%w%.%-]+)$')
    if not suffix then return false end
    local label, rest = host:match('^([%w%-]+)%.(.+)$')
    return label ~= nil and rest == suffix
end

function M.verifyHostname(certificate, host)
    if not certificate then return false end
    local ok, extensions = pcall(function() return certificate:extensions() end)
    if not ok or type(extensions) ~= 'table' then return false end
    local san = extensions['2.5.29.17']
    if type(san) ~= 'table' or type(san.dNSName) ~= 'table' then return false end
    for _, name in ipairs(san.dNSName) do
        if M.hostnameMatches(host, name) then return true end
    end
    -- Public Discord certificates must contain DNS SANs; no CN fallback.
    return false
end

function M.request(method, address, headers, payload, caFile)
    local host = type(address) == 'string' and address:match('^https://([^/]+)/api/webhooks/%d+/[%w_%-]+$')
    if host ~= 'discord.com' and host ~= 'discordapp.com' then
        return false, 0, '', '', 'Only HTTPS Discord webhooks are supported'
    end
    return M.perform(method,address,headers,payload,caFile,host,4*1024*1024)
end

-- The release service supplies a configured, direct HTTPS URL. Redirects are
-- deliberately not followed, so certificate and host checks cover every byte.
function M.get(address, caFile, maxBytes)
    local host,path
    if type(address)=='string' then
        local base=address
        if address:find('?',1,true) then
            base=address:match('^(https://[%w%.%-]+/[%w%._/%-]*manifest%.json)%?xt=%d+%-%d+$')
            if not base then return false,0,'','','Invalid release URL' end
        end
        host,path=base:match('^https://([%w%.%-]+)(/[%w%._/%-]+)$')
    end
    if not host or not path or path:find('..',1,true) then return false,0,'','','Invalid release URL' end
    if type(maxBytes)~='number' or maxBytes<1 or maxBytes>96*1024*1024 then return false,0,'','','Invalid download limit' end
    return M.perform('GET',address,{['User-Agent']='CasualTool'},'',caFile,host,maxBytes)
end

function M.perform(method, address, headers, payload, caFile, host, maxBytes)
    local socket = require('socket')
    local ssl = require('ssl')
    local http = require('socket.http')
    local ltn12 = require('ltn12')
    if http.PROXY then return false, 0, '', '', 'HTTPS proxy is not supported' end
    local response,received = {},0
    local function sink(chunk,err)
        if err then return nil,err end
        if chunk then
            received=received+#chunk
            if received>maxBytes then return nil,'Response exceeds release size limit' end
            response[#response+1]=chunk
        end
        return 1
    end
    local function create()
        local conn = {sock = socket.try(socket.tcp())}
        local checked = false
        local try = socket.newtry(function() pcall(function() conn.sock:close() end) end)
        function conn:settimeout() return self.sock:settimeout(12) end
        function conn:close() return self.sock:close() end
        function conn:connect(connectHost, port)
            try(connectHost == host and tonumber(port) == 443, 'Unexpected HTTPS endpoint')
            try(self.sock:connect(host, 443))
            self.sock = try(ssl.wrap(self.sock, {
                mode = 'client', protocol = 'tlsv1_2', verify = 'peer', cafile = caFile,
                options = {'all', 'no_sslv2', 'no_sslv3', 'no_tlsv1', 'no_tlsv1_1'}
            }))
            try(self.sock:settimeout(12))
            self.sock:sni(host)
            try(self.sock:dohandshake())
            try(M.verifyHostname(self.sock:getpeercertificate(), host), 'TLS certificate hostname mismatch')
            checked = true
            return 1
        end
        setmetatable(conn, {__index = function(_, name)
            return function(self, ...)
                try(checked, 'TLS identity has not been verified')
                return self.sock[name](self.sock, ...)
            end
        end})
        return conn
    end
    local ok, code, _, status = http.request({url = address, port = 443, method = method,
        headers = headers, source = ltn12.source.string(payload), sink = sink,
        create = create, redirect = false})
    local body = table.concat(response)
    if ok then return true, tonumber(code) or 0, body, tostring(status or ''), '' end
    return false, tonumber(code) or 0, body, tostring(status or ''), tostring(code or 'HTTPS failed')
end

return M

end
sources["user_messages.lua"] = function()
-- X-TOOLS | Casual_Alvarez | Dependency-free Russian setup messages.
local M={}
function M.cp1251(text)
 return tostring(text):gsub('[\194-\244][\128-\191]+',function(ch)
  local a,b=ch:byte(1,2);local code=(a-192)*64+(b-128)
  if #ch==2 and code>=1040 and code<=1103 then return string.char(code-848)end
  if code==1025 then return string.char(168)end
  if code==1105 then return string.char(184)end
  return ({['—']='-',['–']='-',['…']='...',['«']='"',['»']='"'})[ch]or '?'
 end)
end
function M.reason(err)
 local s=tostring(err):lower()
 if s:find('checksum',1,true)or s:find('sha256',1,true)then return 'Скачанный файл не прошёл проверку целостности.\nПовторите скачивание.'end
 if s:find('timed out',1,true)or s:find('timeout',1,true)then return 'Сервер загрузки не ответил вовремя.\nПроверьте интернет и повторите попытку.'end
 if s:find('https',1,true)or s:find('download',1,true)then return 'Не удалось скачать файлы.\nПроверьте интернет и доступность GitHub.'end
 if s:find('permission',1,true)or s:find('access denied',1,true)or s:find('cannot create',1,true)then return 'Не удалось записать файлы.\nПроверьте доступ к папке игры и свободное место.'end
 if s:find('url',1,true)then return 'Некорректный адрес обновления.\nУстановите полный архив X-Tools с GitHub.'end
 return 'Не удалось подготовить файлы X-Tools.\nТочная причина записана в moonloader.log.'
end
function M.chat(api,root,text)
 local accent=0xC080FF
 local f=api.io.open(root..'/X-TOOL/settings/interface.ini','rb')
 if f then
  local bytes=f:read('*a')or '';f:close()
  local theme=tonumber(bytes:match('themeStyle%s*=%s*(%d+)')or bytes:match('backgroundStyle%s*=%s*(%d+)'))or 0
  accent=({0x59DFFF,0xFFAB51,0x62E9AB,0xFF6086,0xAA91FF})[theme]or accent
 end
 for line in tostring(text):gmatch('[^\r\n]+')do
  local prefix=string.format('{%06X}[X-TOOLS] {F0EDF8}',accent)
  local row=''
  for word in M.cp1251(line):gmatch('%S+')do
   if #row+#word+1>85 and row~=''then api.sampAddChatMessage(prefix..row,-1);row=''end
   while #word>85 do
    api.sampAddChatMessage(prefix..word:sub(1,85),-1);word=word:sub(86)
   end
   row=row..(row~=''and ' 'or '')..word
  end
  if row~=''then api.sampAddChatMessage(prefix..row,-1)end
 end
end
return M

end

script_name('X-Tools Update')
script_author('Casual Alvarez')
script_version('3.5.203')
local updater
function main()
    repeat wait(100) until isSampAvailable()
    local host=thisScript()
    local root=assert(host.path:match('^(.*)[/\\]'))
    local messages=sources['user_messages.lua']()
    local cache={}
    local rt={api=_G,host=host,base=root..'/resource/X-TOOL/b574811553794a3aacdf58a434ea5f91061940839d835db74ea6dd8a6530deac'}
    function rt:source(name)return sources[name]end
    function rt:service(name)
        if not cache[name]then cache[name]=assert(sources[name])()end
        return cache[name]
    end
    function rt:message(text)messages.chat(_G,root,text)end
    function rt:prepareReload()end
    function rt:releaseReloadInput()end
    function rt:syncGui()end
    rt.updateNotice={show=function()end}
    rt.storage={path=function(_,a,b)return root..'/X-TOOL/'..a..'/'..b end,
        loadIni=function(_,defaults)return defaults end,
        saveIni=function()return true end}
    -- Preserve the application backup before the second update transaction.
    local previous=io.open(host.path..'.pre-bridge.bak','rb')
    if previous then previous:close()else
        local backup=io.open(host.path..'.bak','rb')
        if backup then
            local bytes=backup:read('*a');backup:close()
            local output=io.open(host.path..'.pre-bridge.bak','wb')
            if output then output:write(bytes);output:close()end
        end
    end
    local adapter=rt:service('update_adapter.lua').new(rt)
    adapter.hash=function(bytes)return rt:service('sha256.lua')(bytes,wait)end
    updater=rt:service('updates.lua').new(adapter,{version='3.5.203',path=host.path},
        {bundled=true,updateUrl='https://raw.githubusercontent.com/ameskrillex/X-TOOLS/main/update/live/manifest.json'})
    sampRegisterChatCommand('update',function()updater:update()end)
    rt:message('Переход на новый загрузчик. Сейчас автоматически установится актуальная версия X-Tools; настройки сохранятся. При ошибке повторите /update.')
    updater:update()
    while true do wait(1000)end
end
function onScriptTerminate(script)
    if script==thisScript() and updater then updater:stop()end
end
