-- Experimental launcher bridge. Transport files are local, not a server protocol.
local M={}
function M.text(s)
 return tostring(s or ''):gsub('<br%s*/?>','\n'):gsub('<tbl>','\t')
  :gsub('&emsp;',' '):gsub('&ensp;',' '):gsub('&nbsp;',' ')
  :gsub('&lt;','<'):gsub('&gt;','>'):gsub('&quot;','"'):gsub('&#39;',"'"):gsub('&amp;','&')
end
function M.decode(d)
 if type(d)~='table' then return end
 local title=M.text(d.DIALOG_HEADER):gsub('{%x+}','')
 local style=tonumber(d.DIALOG_TYPE)
 local owner,id,kind,others
 local body=M.text(d.DIALOG_TEXT)
 if title=='Оффлайн статистика игрока' and style==0 then owner,id='familia',0
 elseif title=='Семья'and style==4 then owner,id='family_registry',32001
 elseif title:find('Список игроков в семье',1,true)and style==5 then owner,id='family_registry',32001
 elseif title=='Лидеры'and style==5 then owner,id,kind='adm',424,'leaders'
 elseif title=='Администраторы S уровня'and style==5 then owner,id,kind='adm',0,'admins'
 elseif style==0 and title:match('^[%w_%.]+$')and body:find('Номер аккаунта',1,true)and not body:find('Ник забаненного',1,true)then
  owner,id,kind,others='adm',0,'account',{'lookup'}
 elseif style==0 and body:find('Ник забаненного',1,true)and body:find('Дней до конца бана',1,true)then owner,id,kind='lookup',32002,'baninfo'
 elseif style==0 and title:match('^%d+%.%d+%.%d+%.%d+$')then owner,id,kind='lookup',32002,'ip'
 elseif style==0 and title:match('^Последние админ действия с ')then owner,id,kind='lookup',32002,'log'
 elseif style==4 and title:match('^Прошлые имена ')then owner,id,kind='lookup',32002,'history'
 elseif title=='Статистика мероприятия «Квадрат»'and style==5 then owner,id,kind='family_registry',32001,'square'
 elseif title=='Сезоны'and style==2 then owner,id,kind='family_registry',32001,'season'
 elseif title=='Топ семей'and style==0 then owner,id,kind='family_registry',32001,'top'
 elseif title=='Точное время'and style==0 then owner,id,kind='online',32003,'time'
 elseif title=='Навыки владения оружием'and style==0 then owner,id,kind='weapon_skills',32004,'skills'
 elseif title:match('^LEGO%-локации')and style==5 then owner,id,kind='lego',688,'lego'
 elseif (title=='Что Вы хотите просмотреть?'or title=='Выберите подразделение')and style==2 then owner,id,kind='core',32005,'find_menu'
 elseif style==5 and (title:match('^В организации %d+ чел%.')or title:match('^В подразделении %d+ чел%.'))then owner,id,kind='core',63,'find'
 else return end
 if owner=='familia'then kind='offst';others={'lookup'}end
 local keys=d.DIALOG_KEYS or {}
 return {owner=owner,others=others,id=id,kind=kind,style=style,title=title,body=body,
  button1=M.text(keys[2]),button2=M.text(keys[1])}
end
function M.new(rt,dir)
 local a=rt.api
 local self={claims={},seen={},last=nil,nextPoll=0,snapshot=nil,sequence=0}
 function self:maintain()
  local now=a.os.time()
  if self.healthAt and now-self.healthAt<10 then return end
  self.healthAt=now
  local f=a.io.open(dir..'/heartbeat.txt','rb')
  local stamp=f and tonumber(f:read('*a'));if f then f:close()end
  if stamp and math.abs(now-stamp)<15 then return end
  if self.launchAt and now-self.launchAt<30 then return end
  self.launchAt=now
  local file=a.io.open(dir..'/launcher.json','rb');if not file then return end
  local raw=file:read('*a');file:close()
  local ok,c=pcall(a.decodeJson,raw);if not ok or type(c)~='table' then return end
  if type(c.python)~='string'or type(c.script)~='string'or c.python:find('"',1,true)or c.script:find('"',1,true)then return end
  local ffi=a.require('ffi')
  pcall(ffi.cdef,[[int __stdcall MultiByteToWideChar(unsigned int,unsigned long,const char*,int,wchar_t*,int);
   void* __stdcall ShellExecuteW(void*,const wchar_t*,const wchar_t*,const wchar_t*,const wchar_t*,int);]])
  local kernel=ffi.load('kernel32');local shell=ffi.load('shell32')
  local function wide(s)
   local n=kernel.MultiByteToWideChar(65001,0,s,-1,nil,0)
   if n<=0 then error('CEF launch path encoding')end
   local w=ffi.new('wchar_t[?]',n);kernel.MultiByteToWideChar(65001,0,s,-1,w,n);return w
  end
  local result=shell.ShellExecuteW(nil,wide('open'),wide(c.python),wide('"'..c.script..'"'),nil,0)
  if a.print then a.print('[CEF bridge] helper launch result='..tonumber(ffi.cast('intptr_t',result)))end
 end
 function self:capture(enabled)
  local f=a.io.open(dir..'/capture.json','wb');if not f then return false end
  local ok=f:write(a.encodeJson({expires=enabled and a.os.time()+1200 or 0}));f:close();return ok~=nil
 end
 local function read()
  local f=a.io.open(dir..'/snapshot.json','rb');if not f then return end
  local raw=f:read(300000);f:close()
  local ok,d=pcall(a.decodeJson,raw or '')
  if ok and type(d)=='table' and type(d.time)=='number' and math.abs(a.os.time()-d.time)<4 then return d end
 end
 function self:nativeDialog()
  self.claims={};self.seen={}
 end
 local function writeAction(c,kind,button,row)
  self.sequence=self.sequence+1
  local action={session=c.session,serial=c.serial,revision=c.revision,kind=kind,button=button,row=row,
   expires=a.os.time()+2,nonce=tostring(a.getGameTimer())..':'..self.sequence}
  local f=a.io.open(dir..'/response.json','wb');if not f then return false end
  local ok=f:write(a.encodeJson(action));f:close();return ok~=nil
 end
 function self:close(owner,button)
  local c=self.claims[owner]
  if c then return self:respond(owner,c.id,button or 0,0,'')end
  if self.seen[owner]then return true,false end
  return false
 end
 function self:prepare(owner,apiName,command)
  if self.sending or (apiName~='sampSendChat'and apiName~='sampProcessChatInput') then return false end
  local allowed={familia=true,lookup=true,adm=true,family_registry=true,online=true,weapon_skills=true,lego=true}
  if not allowed[owner]or self.queued then return false end
  local verb,name=tostring(command):match('^/([%w]+)%s*(.-)%s*$')
  local kinds={offst='offst',get='account',baninfo='baninfo',ip='ip',lip='ip',log='log',history='history',leaders='leaders',admins='admins',adms='admins',family='family',fs='square',season='season',askill='skills',lego='lego'}
  local kind=kinds[verb];if verb=='c'and name=='60'then kind='time'end
  local d=read();if not kind or not d then return false end
  self.sequence=self.sequence+1
  local intent={session=d.session,name=name,kind=kind,nonce=tostring(a.getGameTimer())..':'..self.sequence,expires=a.os.time()+3}
  local f=a.io.open(dir..'/intent.json','wb');if not f then return false end
  local ok=f:write(a.encodeJson(intent));f:close();if not ok then return false end
  self.queued={intent=intent,owner=owner,apiName=apiName,command=command,access=rt.access:revision()}
  return true
 end
 function self:login(password)
  local d=self.authTarget;if not d then return false end
  -- Plaintext exists only in memory and on the loopback connection, never in files.
  local f=a.io.open(dir..'/transport.json','rb');if not f then return false end
  local raw=f:read('*a');f:close();local ok,c=pcall(a.decodeJson,raw)
  if not ok or type(c)~='table' or type(c.token)~='string' then return false end
  local okSocket,socket=pcall(a.require,'socket');if not okSocket then return false end
  local tcp=socket.tcp();tcp:settimeout(0.2)
  local connected=tcp:connect('127.0.0.1',18766);if not connected then tcp:close();return false end
  local body=a.encodeJson({session=d.session,login=d.auth.login,password=password,expires=a.os.time()+2})
  local sent=tcp:send('POST /'..c.token..'/credential HTTP/1.0\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: '..#body..'\r\n\r\n'..body)
  local status=sent and tcp:receive('*l');tcp:close()
  return status and status:find('204',1,true)~=nil or false
 end
 function self:active(owner)
  local d=self.snapshot
  if not d or math.abs(a.os.time()-d.time)>=4 or d.active~=true then return false end
  -- Native handlers return false to hide their owned dialog before their next tick.
  -- CEF remains visible until response; reproduce that ownership semantics only
  -- for the accepting module, never for other modules or a replacement window.
  local c=owner and self.claims[owner]
  if c and c.session==d.session and c.serial==d.serial and c.revision==d.revision
   and c.access==rt.access:revision() and a.getGameTimer()-c.at<=120000 then return false end
  return true
 end
 function self:poll()
  local now=a.getGameTimer();if now<self.nextPoll and self.nextPoll-now<1000 then return end
  self.nextPoll=now+100
  local d=read();self.snapshot=d
  if d and d.auth and d.auth.show and not d.auth.error and not d.auth.manual and rt.loginDialog and rt:serverSupports() then
   local found,id=a.sampGetPlayerIdByCharHandle(a.PLAYER_PED)
   local nick=found and a.sampGetPlayerNickname(id)
   if nick and nick:lower()==tostring(d.auth.login):lower() and self.authSession~=d.session then
    self.authSession=d.session;self.authTarget=d
    local ok=pcall(rt.loginDialog,1,1,'Авторизация','')
    self.authTarget=nil
    if a.print then a.print('[CEF login] saved-login handler checked; credentials omitted')end
   end
  end
  if rt.powered==false or not rt.access:canUseTools()or a.sampGetGamestate()~=3 then self.claims={};self.last=nil;self.queued=nil;return end
  local q=self.queued
  if q then
   if not d or d.session~=q.intent.session or q.access~=rt.access:revision() or a.os.time()>q.intent.expires then self.queued=nil
   elseif d.intentAck==q.intent.nonce then
    self.queued=nil;self.sending=true
    local ok,result=pcall(rt.send,rt,q.owner,q.apiName,q.command)
    self.sending=false
    if a.print then a.print('[CEF bridge] '..q.owner..' request released: '..tostring(ok and result~=false))end
   end
  end
  if not d or not d.active or not d.ready then return end
  local key=tostring(d.session)..':'..tostring(d.serial)..':'..tostring(d.revision)
  if self.last==key then return end
  local row=M.decode(d.dialog);if not row then self.last=key;return end
  self.last=key
  local u8=a.require('encoding').UTF8
  if row.kind=='baninfo'and rt.offban then
   local claim={session=d.session,serial=d.serial,revision=d.revision,id=row.id,access=rt.access:revision(),at=now}
   self.claims.cef_offban=claim
   if rt.offban:observe('onShowDialog',row.id,row.style,u8:decode(row.title),u8:decode(row.button1),u8:decode(row.button2),u8:decode(row.body))==false then
    self.seen.cef_offban=row.id;writeAction(claim,'hide',0,0);return
   end
   self.claims.cef_offban=nil
  end
  local owners={row.owner};for _,owner in ipairs(row.others or {})do owners[#owners+1]=owner end
  for _,owner in ipairs(owners)do
   local m=rt.modules[owner]
   if (owner=='core'and rt.organizationFindWaiting)or (m and m.events and rt:featureAllowed(owner))then
    local claim={session=d.session,serial=d.serial,revision=d.revision,id=row.id,access=rt.access:revision(),at=now}
    self.claims[owner]=claim
    local accepted
    if owner=='core'then
     if row.kind=='find_menu'then
      local wanted=row.title=='Выберите подразделение'and 'Все подразделения'or 'Список членов организации (подразделения) онлайн'
      local index=0
      for line in (row.body..'\n'):gmatch('(.-)\n')do
       if line:gsub('{%x+}',''):find(wanted,1,true)then self:respond(owner,row.id,1,index,'');accepted=false;break end
       index=index+1
      end
     elseif row.kind=='find'then
      local ok,myId=a.sampGetPlayerIdByCharHandle(a.PLAYER_PED)
      local parser=rt:service('organization_find.lua')
      local page=parser.parse(63,row.style,row.title,row.body,ok and myId or nil)
      if page then
       local pages,complete,nextPage=parser.collect(rt.organizationFindPages,page,row.button2,ok and myId or nil)
       rt.organizationFindPages=pages;rt.organizationFindReply=complete
       rt.organizationFindNext=nil
       self:respond(owner,row.id,0,0,'');accepted=false
      end
     end
    else
     accepted=rt:call(m,m.events.onShowDialog,row.id,row.style,u8:decode(row.title),
      u8:decode(row.button1),u8:decode(row.button2),u8:decode(row.body))
    end
    if accepted==false then
     self.seen[owner]=row.id
     if self.claims[owner]then
      -- Read-only consumers have no server response in the native path.
      -- Navigation consumers keep their claim for their scheduled response.
      if owner=='lookup'or owner=='online'or (owner=='adm'and row.kind=='account')then
       self:respond(owner,row.id,0,0,'')
      else writeAction(claim,'hide',0,0)end
     end
     if a.print then a.print('[CEF bridge] '..owner..' accepted '..tostring(row.kind or 'family')..' window='..d.serial)end
     break
    end
    self.claims[owner]=nil
   end
  end
 end
 function self:respond(owner,id,button,row,input)
  local c=self.claims[owner]
  if not c or c.id~=id then
   if self.seen[owner]==id or (type(id)=='number'and id>=32001 and id<=32005)then return true,false end
   return false
  end
  self.claims[owner]=nil
  self.seen[owner]=id
  local d=read()
  if not d or not d.active or not d.ready or d.session~=c.session or d.serial~=c.serial or d.revision~=c.revision
   or rt.access:revision()~=c.access or a.getGameTimer()-c.at>120000 or rt.powered==false then return true,false end
  -- CEF's original handler derives list input from the selected row.
  if input and input~=''and (d.dialog.DIALOG_TYPE~=2 and d.dialog.DIALOG_TYPE~=4 and d.dialog.DIALOG_TYPE~=5)then return true,false end
  return true,writeAction(c,'response',button,row)
 end
 return self
end
return M
