local M={}
function M.draw(rt)
 local g=rt.imgui
 local state=rt.transferUi
 if not state then state={buffer=g.ImBuffer('',524289),status=rt.transferNotice or ''};rt.transferUi=state end
 local function attempt(fn)
  local ok,result=pcall(fn)
  if not ok then state.status=tostring(result):gsub('^.-:%d+: ','');return false end
  return true,result
 end
 local function copy()
  local ok,result=pcall(rt.api.setClipboardText,state.buffer.v)
  state.status=ok and result~=false and 'Код скопирован. Передайте его другому пользователю X-Tools.'or 'Не удалось скопировать. Выделите код и нажмите Ctrl+C.'
 end
 g.Text('Перенос настроек')
 g.TextWrapped('Оформление, клавиши, шаблоны и настройки модулей. Пароли, Google Auth, вебхуки и собранные данные не передаются.')
 if g.Button('Экспортировать настройки')then
  if attempt(function()
   assert(rt.preferences:save(),'Не удалось сохранить оформление')
   local code,count=rt.settingsTransfer:export();state.buffer.v=code;state.mode='export';state.count=count
   state.exportFile=rt.storage:write(rt.storage:path('data','settings-export.txt'),code)==true
  end)then copy();g.OpenPopup('Перенос настроек##settings_transfer')end
 end
 g.SameLine()
 if g.Button('Импортировать настройки')then
  state.mode='import';state.buffer.v='';state.status='';g.OpenPopup('Перенос настроек##settings_transfer')
 end
 if state.status~=''then g.TextWrapped(state.status)end
 local sw,sh=rt.api.getScreenResolution()
 g.SetNextWindowSize(g.ImVec2(math.min(720,sw-40),math.min(430,sh-40)),g.Cond.Appearing)
 if g.BeginPopupModal('Перенос настроек##settings_transfer',nil,g.WindowFlags.NoResize)then
  g.Text(state.mode=='export'and ('Код настроек · разделов: '..state.count)or 'Вставьте полученный код настроек')
  g.TextWrapped(state.mode=='export'and 'Скопируйте код целиком. Экспортируются сохранённые настройки.'or 'Импорт подготовит настройки для следующего запуска. После сохранения полностью перезапустите игру. Прежние настройки будут сохранены в резервную копию.')
  if state.mode=='export'and state.exportFile then g.TextWrapped('Для передачи файлом: moonloader/X-TOOL/data/settings-export.txt')end
  g.InputTextMultiline('##settings_transfer_code',state.buffer,g.ImVec2(-1,math.min(200,sh*.27)),state.mode=='export'and (g.InputTextFlags.ReadOnly or 0)or 0)
  if state.mode=='export'then
   if g.Button('Скопировать код')then copy()end
  else
   if g.Button('Вставить из буфера')then attempt(function()
    local value=rt.api.getClipboardText();assert(type(value)=='string'and #value<=524288,'Код слишком велик или буфер пуст');state.buffer.v=value
   end)end
   g.SameLine()
   if not state.importing and g.Button('Сохранить импорт')then
    if attempt(function()rt.settingsTransfer:stage(state.buffer.v)end)then
     state.importing=true
     state.status='Импорт сохранён. Полностью закройте и снова запустите игру для применения настроек.'
    end
   end
   if state.importing and g.Button('Отменить отложенный импорт')then
    if attempt(function()assert(rt.settingsTransfer:cancel(),'Не удалось отменить импорт')end)then
     state.importing=false;state.status='Отложенный импорт отменён.'
    end
   end
  end
  if state.status~=''then g.TextWrapped(state.status)end
  if g.Button('Закрыть##settings_transfer')then g.CloseCurrentPopup()end
  g.EndPopup()
 end
end
return M
