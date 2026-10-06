/* Local, bounded diagnostic observer. Never emits game events. */
(() => {
  'use strict';
  const endpoint = 'http://127.0.0.1:18765/__TOKEN__';
  const started = Date.now();
  let safe = false, bytes = 0, sequence = 0, failures = 0, busy = false;
  const queue = [];
  function record(event, data) {
    if (Date.now() - started > 1200000 || bytes > 8000000 || queue.length >= 100 || failures >= 3) return;
    const row = JSON.stringify({time:new Date().toISOString(),sequence:++sequence,event,data});
    if (row.length > 100000) return;
    bytes += row.length;
    queue.push(row);
  }
  window.__xtCefProbe = (event, args) => {
    try {
      if (event === 'cef:dialog') {
        safe = false;
        const input = Array.isArray(args) ? args[0] : args;
        const data = typeof input === 'string' ? JSON.parse(input) : input;
        if (!data || typeof data !== 'object') return;
        const title = String(data.DIALOG_HEADER || '');
        const type = Number(data.DIALOG_TYPE);
        safe = [0,2,4,5].includes(type) && !/парол|авториза|регистрац|код|auth|password|login/i.test(title);
        if (!safe) {record('dialog_redacted',{type});return;}
        const selected = {};
        for (const key of ['DIALOG_SHOW','DIALOG_TYPE','DIALOG_HEADER','DIALOG_KEYS','DIALOG_TEXT']) {
          const value = data[key];
          if (['string','number','boolean'].includes(typeof value)) selected[key] = typeof value === 'string' ? value.slice(0,60000) : value;
          else if (key === 'DIALOG_KEYS' && Array.isArray(value)) selected[key] = value.slice(0,4).map(v=>String(v).slice(0,256));
        }
        record('dialog', selected);
      } else if (event === 'cef:dialogtext') {
        if (safe) record('dialog_append',{text:String(args[0] || '').slice(0,60000)});
      } else if (event === 'cef:dialogForceClose') {
        safe=false;record('dialog_close',{});
      } else if (event === 'cef:dialogResponse') {
        record('dialog_response',{button:args[0],row:args[1],input:'[omitted]'});safe=false;
      }
    } catch (_) {safe=false;}
  };
  record('probe_ready',{version:1,transport:'CEF event relay'});
  const timer=setInterval(() => {
    if (Date.now()-started>1200000 || failures>=3) {clearInterval(timer);queue.length=0;return;}
    if (busy || !queue.length) return;
    busy=true;
    const controller=new AbortController();
    const timeout=setTimeout(()=>controller.abort(),3000);
    fetch(endpoint,{method:'POST',headers:{'Content-Type':'text/plain'},body:queue.splice(0,20).join('\n'),signal:controller.signal})
      .then(r=>{if(!r.ok)throw new Error('collector');failures=0;})
      .catch(()=>{failures++;})
      .finally(()=>{clearTimeout(timeout);busy=false;});
  },500);
})();
