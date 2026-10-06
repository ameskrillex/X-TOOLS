from pathlib import Path
from http.server import HTTPServer,BaseHTTPRequestHandler
import json,time,os
root=Path(__file__).resolve().parent
config=json.loads((root/'cef-family-local.json').read_text('utf-8'))
folder=Path(config['directory']);folder.mkdir(parents=True,exist_ok=True)
credential=None
last_seen=time.monotonic()
last_capture=None
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_POST(self):
  global credential,last_seen,last_capture
  if self.path=='/'+config['token']+'/credential':
   try:
    self.connection.settimeout(2)
    length=int(self.headers.get('Content-Length',0));assert 0<length<4096
    data=json.loads(self.rfile.read(length))
    assert isinstance(data.get('password'),str)and 0<len(data['password'])<1024
    assert time.time()-1<=data['expires']<=time.time()+4
    credential=data
   except Exception:self.send_error(400);return
   self.send_response(204);self.end_headers();return
  if self.path!='/'+config['token']:self.send_error(404);return
  try:
   length=int(self.headers.get('Content-Length',0));assert 0<length<300000
   self.connection.settimeout(2)
   state=json.loads(self.rfile.read(length));assert isinstance(state,dict)
   assert isinstance(state.get('session'),str)and len(state['session'])<100
   assert isinstance(state.get('serial'),int)and isinstance(state.get('revision'),int)
   last_seen=time.monotonic()
   capture=state.pop('capture',None)
   key=(state['session'],state['serial'],state['revision'])
   try:
    policy=json.loads((folder/'capture.json').read_text('utf-8'))
    if policy.get('expires',0)>=time.time() and state.get('captureReady') and isinstance(capture,dict) and key!=last_capture:
     log=folder/'dossier-capture.jsonl'
     if not log.exists() or log.stat().st_size<8388608:
      record={'time':time.time(),'session':key[0],'serial':key[1],'revision':key[2],'dialog':capture}
      with log.open('a',encoding='utf-8')as f:f.write(json.dumps(record,ensure_ascii=False)+'\n')
     last_capture=key
   except (OSError,ValueError,TypeError):pass
   state['time']=time.time()
   temp=folder/'snapshot.tmp';temp.write_text(json.dumps(state,ensure_ascii=False),encoding='utf-8')
   os.replace(temp,folder/'snapshot.json')
   response=None
   try:
    cmd=json.loads((folder/'response.json').read_text('utf-8'))
    if cmd['expires']>=time.time() and all(cmd[k]==state[k]for k in ('session','serial','revision')):response=cmd
   except (OSError,ValueError,KeyError,TypeError):pass
   intent=None
   try:
    item=json.loads((folder/'intent.json').read_text('utf-8'))
    if item['session']==state['session'] and item['expires']>=time.time():intent=item
   except (OSError,ValueError,KeyError,TypeError):pass
   login=None
   if credential:
    if credential.get('session')==state['session'] and credential.get('expires',0)>=time.time():login=credential
    credential=None
   payload=json.dumps({'kind':'envelope','response':response,'intent':intent,'credential':login}).encode()
  except Exception:self.send_error(400);return
  self.send_response(200);self.send_header('Access-Control-Allow-Origin','*')
  self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(payload)))
  self.end_headers();self.wfile.write(payload)
try:server=HTTPServer(('127.0.0.1',18766),Handler)
except OSError:raise SystemExit(0) # Existing listener owns the port; do not spawn duplicates.
server.timeout=1
while time.monotonic()-last_seen<120:
 server.handle_request()
 (folder/'heartbeat.txt').write_text(str(int(time.time())),encoding='ascii')
 if credential and credential.get('expires',0)<time.time():credential=None
server.server_close()
