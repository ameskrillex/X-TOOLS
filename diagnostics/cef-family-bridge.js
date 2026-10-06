/* Local CEF adapter. Responses use the original React handler and window identity. */
(() => {
 const url='http://127.0.0.1:18766/__TOKEN__';
 const session=Date.now()+'-'+Math.random().toString(36).slice(2);
 let serial=0,revision=0,active=false,dialog=null,changed=0,busy=false,lastNonce=null;
 let intent=null,intentAck=null,auth={show:false},authTried=false;
 let capture=null;
 const previous=window.__xtCefProbe;
 const clean=s=>String(s||'').replace(/\{[a-f\d]+\}/gi,'').replace(/&emsp;|&ensp;|&nbsp;/g,' ');
 function classify(d,title){
  const s=d.DIALOG_TYPE,b=clean(d.DIALOG_TEXT);
  if(s===0&&title==='Оффлайн статистика игрока')return 'offst';
  if(s===4&&title==='Семья'||s===5&&title.includes('Список игроков в семье'))return 'family';
  if(s===5&&title==='Лидеры')return 'leaders';
  if(s===5&&title==='Администраторы S уровня')return 'admins';
  if(s===0&&/^[\w.]+$/.test(title)&&b.includes('Номер аккаунта')&&!b.includes('Ник забаненного'))return 'account';
  if(s===0&&b.includes('Ник забаненного')&&b.includes('Дней до конца бана'))return 'baninfo';
  if(s===0&&/^\d+\.\d+\.\d+\.\d+$/.test(title))return 'ip';
  if(s===0&&title.startsWith('Последние админ действия с '))return 'log';
  if(s===4&&title.startsWith('Прошлые имена '))return 'history';
  if(s===5&&title==='Статистика мероприятия «Квадрат»')return 'square';
  if(s===2&&title==='Сезоны')return 'season';
  if(s===0&&title==='Топ семей')return 'top';
  if(s===0&&title==='Точное время')return 'time';
  if(s===0&&title==='Навыки владения оружием')return 'skills';
  if(s===5&&title.startsWith('LEGO-локации'))return 'lego';
  if(s===2&&['Что Вы хотите просмотреть?','Выберите подразделение'].includes(title))return 'find_menu';
  if(s===5&&/^В (организации|подразделении) \d+ чел\./.test(title))return 'find';
  return null;
 }
 function matches(arm,kind,title,body){
  if((arm.kind||'offst')!==kind)return false;
  const name=String(arm.name||'').toLowerCase();
  if(kind==='offst'){const m=clean(body).match(/Имя:\s*([A-Za-z0-9_.]+)/);return !!m&&m[1].toLowerCase()===name;}
  if(['account','baninfo','ip'].includes(kind))return title.toLowerCase()===name;
  if(kind==='history')return title.slice('Прошлые имена '.length).toLowerCase()===name;
  if(kind==='log')return title.slice('Последние админ действия с '.length).toLowerCase()===name;
  return true;
 }
 window.__xtCefProbe=function(event,args){
  if(previous)previous(event,args);
  try {
   if(event==='cef:dialog'){
    window.__xtCefHidden=false;
    serial++;revision=0;changed=Date.now();active=true;dialog=null;
    const d=JSON.parse(String(args[0]));
    const title=String(d.DIALOG_HEADER||'').replace(/\{[a-f\d]+\}/gi,'');
    const kind=classify(d,title);
    capture=null;
    if([0,2,4,5].includes(d.DIALOG_TYPE)&&!/парол|авториза|регистрац|код|auth|password|login/i.test(title))
     capture={DIALOG_TYPE:d.DIALOG_TYPE,DIALOG_HEADER:String(d.DIALOG_HEADER||'').slice(0,512),
      DIALOG_KEYS:Array.isArray(d.DIALOG_KEYS)?d.DIALOG_KEYS.slice(0,2):[],DIALOG_TEXT:String(d.DIALOG_TEXT||'').slice(0,100000)};
    if(intent&&Date.now()<=intent.expires*1000){
     if(matches(intent,kind,title,d.DIALOG_TEXT)){window.__xtCefHidden=true;window.__xtCefHiddenToken=serial;}
     intent=null;
    }
    if(kind)
      dialog={DIALOG_TYPE:d.DIALOG_TYPE,DIALOG_HEADER:d.DIALOG_HEADER,
       DIALOG_KEYS:d.DIALOG_KEYS,DIALOG_TEXT:String(d.DIALOG_TEXT||'')};
   }else if(event==='cef:dialogtext'){
    if(capture)capture.DIALOG_TEXT=(capture.DIALOG_TEXT+String(args[0]||'')).slice(0,100000);
    revision++;changed=Date.now();if(dialog)dialog.DIALOG_TEXT+=String(args[0]||'');
    if(dialog&&dialog.DIALOG_TEXT.length>150000)dialog=null;
   }else if(event==='cef:dialogResponse'||event==='cef:dialogForceClose'){
    window.__xtCefHidden=false;
    capture=null;
    active=false;dialog=null;revision++;changed=Date.now();
   }else if(event==='cef:login'){
    const d=JSON.parse(String(args[0]));
    auth={show:d.AUTH_SHOW!==false,login:String(d.AUTH_LOGIN||auth.login||''),error:auth.error||false};
   }else if(event==='cef:loginerror'){auth.error=true;}
  }catch(_){dialog=null;capture=null;revision++;}
 };
 const timer=setInterval(()=>{
  if(busy)return;
  busy=true;
  const ctrl=new AbortController(),timeout=setTimeout(()=>ctrl.abort(),1500);
  if(window.__xtCefAuthStatus){const s=window.__xtCefAuthStatus();auth={...auth,...s,error:!!(auth.error||s.error)};}
  const state={session,serial,revision,active,dialog,capture,auth,intentAck,ready:!!dialog&&Date.now()-changed>=500,captureReady:!!capture&&Date.now()-changed>=500};
  fetch(url,{method:'POST',headers:{'Content-Type':'text/plain'},body:JSON.stringify(state),signal:ctrl.signal})
   .then(r=>r.ok?r.json():null).then(cmd=>{
    if(cmd&&cmd.kind==='envelope'){
     const arm=cmd.intent;
     if(arm&&arm.session===session&&Date.now()<=arm.expires*1000&&arm.nonce!==intentAck){intent=arm;intentAck=arm.nonce;}
     const login=cmd.credential;
     if(login&&!authTried&&login.session===session&&Date.now()<=login.expires*1000&&auth.show&&!auth.error&&!auth.manual&&login.login===auth.login&&window.__xtCefLogin){
      authTried=true;window.__xtCefLogin(login.login,login.password);login.password='';
     }
     cmd=cmd.response;
    }
    if(!cmd||cmd.nonce===lastNonce||!active||!dialog||Date.now()-changed<500||
     cmd.session!==session||cmd.serial!==serial||cmd.revision!==revision||Date.now()>cmd.expires*1000)return;
    if(cmd.kind==='hide'){
     if(typeof window.__xtCefDialogHide==='function'){
      lastNonce=cmd.nonce;window.__xtCefHidden=false;window.__xtCefDialogHide();
     }
     return;
    }
    if(![0,1].includes(cmd.button)||!Number.isInteger(cmd.row))return;
    const lines=dialog.DIALOG_TEXT.split('<br>');
    const max=lines.length-(dialog.DIALOG_TYPE===5?1:0);
    if(cmd.button===1&&[2,4,5].includes(dialog.DIALOG_TYPE)&&(cmd.row<0||cmd.row>=max))return;
    if(typeof window.__xtCefDialogRespond!=='function')return;
    lastNonce=cmd.nonce;
    window.__xtCefDialogRespond(cmd.button,cmd.row,()=>active&&dialog&&
      cmd.session===session&&cmd.serial===serial&&cmd.revision===revision&&Date.now()<=cmd.expires*1000);
   }).catch(()=>{}).finally(()=>{clearTimeout(timeout);busy=false;});
 },150);
})();
