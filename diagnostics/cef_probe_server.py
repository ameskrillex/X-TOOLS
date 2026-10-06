"""Loopback-only recorder, max 8 MB, exits after one hour. No game control API."""
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import json
import time
import secrets

root=Path(__file__).resolve().parent
config=json.loads((root/'cef-probe-local.json').read_text('utf-8'))
logs=root/'cef-logs'
logs.mkdir(exist_ok=True)
path=logs/('cef-'+time.strftime('%Y%m%d-%H%M%S')+'-'+secrets.token_hex(3)+'.jsonl')
total=0
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_POST(self):
        global total
        if self.path != '/'+config['token']:
            self.send_error(404);return
        try:length=int(self.headers.get('Content-Length','0'))
        except ValueError:self.send_error(400);return
        if not 0<length<=2000000 or total+length>8388608:
            self.send_error(413);return
        self.connection.settimeout(3)
        try:
            body=self.rfile.read(length).decode('utf-8')
            rows=[json.loads(line) for line in body.splitlines()]
            allowed={'probe_ready','dialog','dialog_append','dialog_response','dialog_close','dialog_redacted'}
            if any(not isinstance(r,dict) or r.get('event') not in allowed for r in rows):raise ValueError()
        except Exception:self.send_error(400);return
        with path.open('a',encoding='utf-8') as file:
            for row in rows:file.write(json.dumps(row,ensure_ascii=False)+'\n')
        total+=length
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin','*')
        self.end_headers()

server=HTTPServer(('127.0.0.1',18765),Handler)
server.timeout=1
(root/'cef-probe-server-status.json').write_text(json.dumps({'log':str(path),'port':18765,'started':time.time()}),encoding='utf-8')
deadline=time.monotonic()+3600
while time.monotonic()<deadline:server.handle_request()
server.server_close()
