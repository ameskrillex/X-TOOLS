script_name('XT Dialog Probe')
script_author('X-Tools')
script_version('1.0.0')
require 'lib.moonloader'
local events=require 'lib.samp.events'
local encoding=require 'encoding'
encoding.default='CP1251'
local u8=encoding.UTF8
local active=false
local queue,bytes,dropped,seq={},0,0,0
local started,path,lastCommand,lastSample,lastState
local MAX_BYTES,MAX_QUEUE,MAX_SECONDS=8*1024*1024,200,1200
local allowed={offst=true,get=true,admget=true,baninfo=true,iplog=true,ip=true,lip=true,
 log=true,history=true,leaders=true,admins=true,adms=true,family=true,fs=true,
 season=true,lego=true,askill=true,find=true,sp=true,c=true}
local function utf(value)
 local ok,result=pcall(u8,tostring(value or ''))
 return ok and tostring(result) or '[encoding error]'
end
local function text(value,limit)
 local s=utf(value);limit=limit or 16384
 -- Keep UTF-8 codepoints intact when truncating.
 if #s>limit then s=s:sub(1,limit):gsub('[\194-\244][\128-\191]*$','')..'[truncated]' end
 return s
end
local function say(s)sampAddChatMessage('[XT Probe] '..s,-1)end
local function push(kind,data)
 if not active then return end
 if #queue>=MAX_QUEUE then dropped=dropped+1;return end
 seq=seq+1
 queue[#queue+1]={seq=seq,event=kind,time=os.date('%Y-%m-%d %H:%M:%S'),
  tick=getGameTimer(),command=lastCommand,data=data or {}}
end
local function flush()
 if not path or #queue==0 then return end
 local file=io.open(path,'ab')
 if not file then active=false;queue={};say('Log write failed; stopped.');return end
 for _,row in ipairs(queue)do
  local ok,line=pcall(encodeJson,row)
  if ok then
   line=line..'\n'
   if bytes+#line>MAX_BYTES then active=false;break end
   local written=file:write(line)
   if not written then active=false;break end
   bytes=bytes+#line
  else dropped=dropped+1 end
 end
 file:close();queue={}
end
local function stop(reason)
 push('stop',{reason=reason,dropped=dropped});active=false;flush()
 say('Stopped. Logs: moonloader/XT-Dialog-Probe')
end
local function start()
 if active then say('Already recording.');return end
 local dir=getWorkingDirectory()..'\\XT-Dialog-Probe'
 if not doesDirectoryExist(dir)then createDirectory(dir)end
 local stem=dir..'\\probe-'..os.date('%Y%m%d-%H%M%S')
 local suffix=0;path=stem..'.jsonl'
 while doesFileExist(path)do suffix=suffix+1;path=stem..'-'..suffix..'.jsonl'end
 queue={};bytes=0;dropped=0;seq=0;lastCommand=nil;lastState=nil
 started=getGameTimer();lastSample=started;active=true
 push('start',{version='1.0.0',transport='SA-MP events only; CEF bridge not installed',
  duration_limit=MAX_SECONDS,byte_limit=MAX_BYTES,
  privacy='Input responses and command arguments omitted. Dialog bodies may contain account/IP data.'})
 flush();say('Recording for 20 minutes. /xtprobe mark offst, /xtprobe stop')
end
local function sensitive(id,style,title)
 local s=utf(title):lower()
 return id==1 or id==88 or style==1 or style==3 or s:find('Authenticator',1,true)
  or s:find('auth',1,true) or s:find('password',1,true)
  or s:find('парол',1,true) or s:find('Парол',1,true)
  or s:find('Авториза',1,true) or s:find('авториза',1,true)
  or s:find('Код с приложения',1,true)
end
function events.onShowDialog(id,style,title,b1,b2,body)
 if sensitive(id,style,title)then push('dialog_redacted',{id=id,style=style});return end
 push('dialog',{id=id,style=style,title=text(title,512),button1=text(b1,256),
  button2=text(b2,256),body=text(body),bytes=#tostring(body or '')})
end
function events.onSendDialogResponse(id,button,row,input)
 push('dialog_response',{id=id,button=button,row=row,input='[omitted]'})
end
function events.onSendCommand(command)
 if not active then return end
 local verb=tostring(command):lower():match('^/([%w_]+)')
 if allowed[verb]then
  lastCommand={verb=verb,tick=getGameTimer()};push('command',{verb=verb,args='[omitted]'})
 end
end
function events.onInitMenu(id,title,x,y,twoColumns,columns,rows,enabled)
 -- Tables are bounded by the SA-MP menu protocol; encode strings explicitly.
 local function clean(v,depth)
  if type(v)=='string'then return text(v,1024)end
  if type(v)~='table'then return v end
  if depth>5 then return '[depth limit]'end
  local result={};local count=0
  for k,item in pairs(v)do count=count+1;if count>128 then break end
   result[tostring(k)]=clean(item,depth+1)
  end
  return result
 end
 push('menu_init',{id=id,title=text(title,512),columns=clean(columns,0),rows=clean(rows,0),enabled=clean(enabled,0)})
end
function events.onShowMenu(id)push('menu_show',{id=id})end
function events.onHideMenu(id)push('menu_hide',{id=id})end
function events.onSendMenuSelect(row)push('menu_select',{row=row})end
function events.onConnectionClosed()if active then stop('connection closed')end end
function events.onConnectionLost()if active then stop('connection lost')end end
function main()
 repeat wait(250)until isSampAvailable()
 sampRegisterChatCommand('xtprobe',function(arg)
  local cmd,label=tostring(arg or ''):match('^(%S*)%s*(.*)$')
  if cmd=='start'then start()
  elseif cmd=='stop'then stop('manual')
  elseif cmd=='mark'then
   -- Labels are catalog keys only, never arbitrary pasted account credentials.
   if allowed[label]then push('mark',{label=label});say('Marked: '..label)
   else say('Use a command name: /xtprobe mark offst')end
  elseif cmd=='status'then say((active and 'Recording' or 'Stopped')..'; bytes='..bytes..'; dropped='..dropped)
  else say('/xtprobe start | mark offst | status | stop')end
 end)
 say('Ready. /xtprobe start (open dialogs after starting)')
 while true do
  wait(250)
  if active then
   local now=getGameTimer()
   if now<started or now-started>=MAX_SECONDS*1000 then stop('time limit')
   else
    local state={dialog=sampIsDialogActive(),chat=sampIsChatInputActive(),game=sampGetGamestate()}
    local encoded=encodeJson(state)
    if encoded~=lastState then lastState=encoded;push('ui_state',state)end
    if now-lastSample>=5000 then lastSample=now;push('heartbeat',{dropped=dropped})end
    flush()
    if not active then say('Recording stopped: size limit or write failure.')end
   end
  end
 end
end
function onScriptTerminate(script)
 if script==thisScript()and active then stop('script terminated')end
end
