"""Reproducible final changes on top of the streamed-overlay 3.5.305 source."""
def transform(code):
    def replace(old,new):
        nonlocal code
        assert code.count(old)==1,(old[:100],code.count(old))
        code=code.replace(old,new)
    for name in ('modules/crimelegends.lua','modules/legends_browser.lua','legends_art.lua','legends_server.lua'):
        start=code.index('    sources["'+name+'"] = function()')
        end=code.index('    sources[',start+20)
        code=code[:start]+code[end:]
    start=code.index('integration.visitLegend=function(entry)')
    end=code.index('integration.homeGet=',start)
    code=code[:start]+code[end:]
    start=code.index('        legendsDirectory=function()')
    end=code.index('        drawSkySettings=',start)
    code=code[:start]+code[end:]
    replace("local names={crimelegends='Land of Legends',",'local names={')
    replace("    self:load('crimelegends','crimelegends.lua')\n",'')
    replace("    self:load('legends_browser','legends_browser.lua')\n",'')
    replace("cached.retry_at and os.clock() >= cached.retry_at", "cached.retry_at and os.time() >= cached.retry_at")
    replace("if result.success == false then result.retry_at = os.clock() + 60 end", "if result.success == false then result.retry_at = os.time() + 60 end")
    replace("    if pending_geo[clean_ip] then return ipwho_cache[clean_ip] end\n    local state = {generation = lookup_generation, started = os.clock()}", """    local previous=pending_geo[clean_ip]
    if previous then
        if not force_refresh or os.time()-previous.started<2 then return ipwho_cache[clean_ip]end
        previous.finish(false,'Запрос перезапущен пользователем')
    end
    local state = {generation = lookup_generation, started = os.time()}""")
    replace('if file then raw = file:read("*a"); file:close() end', 'if file then raw = file:read(1024 * 1024 + 1); file:close() end')
    replace("source = 'network', retry_at = os.clock() + 60", "source = 'network', retry_at = os.time() + 60")
    replace('local ok = pcall(downloadUrlToFile, IPWHO_ENDPOINT:format(clean_ip)', 'local ok,handle = pcall(downloadUrlToFile, IPWHO_ENDPOINT:format(clean_ip)')
    replace('if tonumber(status) == 58 then state.completed = true end', """if tonumber(status) == 58 then state.completed = true
        elseif tonumber(status)==53 then state.failed='Ошибка защищённого HTTPS-соединения с ipwho.is'
        elseif tonumber(status)==59 then state.failed='Загрузчику не хватает ресурсов для запроса ipwho.is' end""")
    replace("if not ok then finish(false, 'Не удалось запустить HTTPS-загрузку ipwho.is') end", "if not ok or handle==false then finish(false, 'Не удалось запустить HTTPS-загрузку ipwho.is') end")
    replace("""        if state.completed then state.finish(true)
        elseif os.clock() - state.started > 12 then state.finish(false, 'ipwho.is не ответил за 12 секунд') end""", """        if state.failed then state.finish(false,state.failed)
        elseif state.completed then state.finish(true)
        elseif os.time() - state.started >= 12 or os.time()<state.started then state.finish(false, 'ipwho.is не ответил за 12 секунд; нажмите «Обновить геоданные IP»') end""")
    return code
