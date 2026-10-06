from pathlib import Path
root=Path(__file__).resolve().parents[1]
code=(root/'X-TOOL.lua').read_text('utf-8')
def replace(old,new):
 global code
 assert code.count(old)==1,(old[:80],code.count(old))
 code=code.replace(old,new)
marker='    sources["streamed_players.lua"] = function()'
replace("function events.onSendCommand(command)\n    if internal then return end\n    if pending and command:lower():match('^/offst%s') then", "function events.onSendCommand(command)\n    if internal or integration.commandOwner()=='familia' then return end\n    if pending and command:lower():match('^/offst%s') then")
replace("local r=self.response;self.response=nil;stage(r.nextStage)", "local r=self.response;self.response=nil;stage(r.awaitCefMenu and 'cef_return' or r.nextStage)")
replace("if self.stage=='advance'and style==4 and title=='Семья'then", "if (self.stage=='advance'or self.stage=='cef_return')and style==4 and title=='Семья'then")
replace("nextStage=more and 'members'or 'advance'};stage('response',500)", "nextStage=more and 'members'or 'advance',awaitCefMenu=not more and id==32001};stage('response',500)")
replace(marker,'    sources["cef_family_bridge.lua"] = function()\n'+(root/'libraries/cef_family_bridge.lua').read_text('utf-8')+'\n    end\n'+marker)
replace('''        sampSendDialogResponse(id,1,-1,password)''','''        if integrationRuntime.cefFamily and integrationRuntime.cefFamily.authTarget then
            integrationRuntime.cefFamily:login(password)
        else sampSendDialogResponse(id,1,-1,password) end''')
replace('''        self.offban:track(text)
    end
    self:traceInspection(owner,arguments[1])''','''        if self.cefFamily and self.cefFamily:prepare(owner,apiName,arguments[1]) then return true end
        self.offban:track(text)
    end
    self:traceInspection(owner,arguments[1])''')
replace("    env.sampAddChatMessage=function(text,color) return self:chat(text,color) end", """    env.sampSendDialogResponse=function(...)return self:send(m.id,'sampSendDialogResponse',...)end
    env.sampCloseCurrentDialogWithButton=function(button)
        if self.cefFamily then
            local handled,result=self.cefFamily:close(m.id,button)
            if handled then return result end
        end
        return self.api.sampCloseCurrentDialogWithButton(button)
    end
    env.sampAddChatMessage=function(text,color) return self:chat(text,color) end""")
replace('''    local arguments=pack(...)
    if type(arguments[1])=='string' then''','''    local arguments=pack(...)
    if apiName=='sampSendDialogResponse' and self.cefFamily then
        local handled,result=self.cefFamily:respond(owner,...)
        if handled then return result end
    end
    if type(arguments[1])=='string' then''')
replace('''    env._G = env
    env.io = self:fileApi()''','''    env._G = env
    env.sampIsDialogActive=function(...)
        return self.api.sampIsDialogActive(...) or (self.cefFamily and self.cefFamily:active(m.id)) or false
    end
    env.io = self:fileApi()''')
replace("    if name=='onShowDialog' then\n        local id,style,title,b1,b2,body=...", "    if name=='onShowDialog' then\n        if self.cefFamily then self.cefFamily:nativeDialog()end\n        local id,style,title,b1,b2,body=...")
# Deferred sends must retain the same ownership semantics as synchronous ones.
replace("function events.onSendCommand(command)\n    if internal then return end\n    local text=tostring(u8(command or ''))", "function events.onSendCommand(command)\n    if internal or integration.commandOwner()=='weapon_skills' then return end\n    local text=tostring(u8(command or ''))")
replace("""            close_current_dialog_safely()
        end)
    end
end

function integration.start()""", """            close_current_dialog_safely()
        end)
        return false
    end
end

function integration.start()""")
# A history page for another account must not replace an in-progress preview.
replace('''    local target = extract_history_target(dialog.title)
    local page_key''','''    local target = extract_history_target(dialog.title)
    if history_collect and normalize_identity(target)~=history_collect.target then return end
    local page_key''')
# Lookup's native /log accepts broad windows; CEF routes only recorded semantic types.
replace('''    if context.kind == "baninfo" and looks_like_baninfo_dialog(dialog.title, dialog.text) then
        return "baninfo"''','''    if context.kind == "baninfo" and looks_like_baninfo_dialog(dialog.title, dialog.text) then
        local target=trim(context.value or '')
        if target~='' and not tonumber(target) and normalize_identity(dialog.title)~=normalize_identity(target)then return nil end
        return "baninfo"''')
replace("    if not online then return end\n    local paused,own=0,false", "    if not online then total,online=title:match('^В подразделении%s+(%d+)%s+чел%.%s*%(онлайн%s+(%d+)%)%s*$')end\n    if not online then return end\n    local paused,own=0,false")
# The captured launcher response has one complete group. Never synthesize values
# for an absent group, or enqueue /setskill for values that were not received.
replace('function Skills.parse(text)', 'function Skills.parse(text,allowBaseOnly)')
replace("    for group=1,2 do for id=1,11 do\n        if result[group][id]==nil", "    if allowBaseOnly and not text:find('Продвинутые навыки',1,true)then result[2]=nil end\n    for group=1,#result do for id=1,11 do\n        if result[group][id]==nil")
replace("    for group=1,2 do for id=1,11 do\n        if current[group][id]~=target", "    for group=1,#current do for id=1,11 do\n        if current[group][id]~=target")
replace("local values,err=parser.parse(u8(text or ''))", "local values,err=parser.parse(u8(text or ''),id==32004)")
replace("for group=1,2 do for skill=1,11 do current.edit[group][skill]", "for group=1,#values do for skill=1,11 do current.edit[group][skill]")
replace("    for group=1,2 do\n        g.Separator();g.Text(group==1", "    if not current.values[2]then g.TextWrapped('Сервер передал только базовые навыки. Продвинутые не изменяются.')end\n    for group=1,#current.values do\n        g.Separator();g.Text(group==1")
replace("            if p.dialogId and rt.api.sampSendDialogResponse then rt.api.sampSendDialogResponse(p.dialogId,0,0,'') end", """            if p.dialogId and rt.api.sampSendDialogResponse then
                local handled=rt.cefFamily and rt.cefFamily:respond('cef_offban',p.dialogId,0,0,'')
                if not handled then rt.api.sampSendDialogResponse(p.dialogId,0,0,'')end
            end""")
# Close the final list only after collection. Selection navigation still keeps
# the same CEF list alive until the module sends the selected original row.
replace("        state.ready=true;stop('Загружено локаций: '..#state.locations)", """        state.ready=true;stop('Загружено локаций: '..#state.locations)
        if integration.cefDialogOwned and integration.cefDialogOwned(ID)then sampSendDialogResponse(ID,0,0,'')end""")
replace("    env.sampSendDialogResponse=function(...)return self:send(m.id,'sampSendDialogResponse',...)end", """    env.sampSendDialogResponse=function(...)return self:send(m.id,'sampSendDialogResponse',...)end
    env.integration.cefDialogOwned=function(id)
        local c=self.cefFamily and self.cefFamily.claims[m.id]
        return c~=nil and c.id==id
    end""")
anchor='local integrationRuntime = casualSources["runtime.lua"]().new(integrationPath, thisScript(), casualSources, casualRelease)'
replace(anchor,anchor+'''
-- Local experimental CEF adapters for recorded launcher dialogs.
do
 local dir=getWorkingDirectory()..'/X-TOOL/cef-bridge'
 integrationRuntime.cefFamily=integrationRuntime:service('cef_family_bridge.lua').new(integrationRuntime,dir)
 lua_thread.create(function()
  repeat wait(100)until isSampAvailable()
  sampRegisterChatCommand('xtcef',function(arg)
   if arg=='capture' or arg=='stop' then
    local ok=integrationRuntime.cefFamily:capture(arg=='capture')
    sampAddChatMessage('[CEF] '..(ok and (arg=='capture' and 'Capture enabled: 20 minutes. Open dossier dialogs.' or 'Capture stopped.') or 'Cannot write capture configuration.'),-1)
   else sampAddChatMessage('[CEF] /xtcef capture | /xtcef stop',-1)end
  end)
  while true do
   wait(100)
   local started,reason=pcall(function()integrationRuntime.cefFamily:maintain()end)
   if not started then print('[CEF bridge] helper launch failed')end
   if isSampAvailable() then
    local ok,err=pcall(function()integrationRuntime.cefFamily:poll()end)
    if not ok then print('[CEF family bridge] '..tostring(err));return end
   end
  end
 end)
end
''')
code='-- Local experimental CEF family adapter; not a published release.\n'+code
out=root/'artifacts/cef-family-dev';out.mkdir(parents=True,exist_ok=True)
(out/'X-TOOL.lua').write_text(code,encoding='utf-8')
print(out/'X-TOOL.lua')
