from pathlib import Path
import hashlib
import json
import os
import secrets

root=Path(__file__).resolve().parent
assets=Path(os.environ['APPDATA'])/'Advance RP Launcher/bin/plugins/cef/assets'
main=assets/'static/js/main.a4f76ec4.js'
index=assets/'index.html'
old='let t=(...t)=>{S.emit(e,t)};window.cef.on(e,t)'
new='let t=(...t)=>{try{window.__xtCefProbe&&window.__xtCefProbe(e,t)}catch(_){}S.emit(e,t)};window.cef.on(e,t)'
reply='window.cef.emit("cef:dialogResponse",e,void 0!==t?t:this.state.DIALOG_ITEM,n)'
replacement='(function(){try{window.__xtCefProbe&&window.__xtCefProbe("cef:dialogResponse",[e,void 0!==t?t:this.state.DIALOG_ITEM])}catch(_){}}.call(this),'+reply+')'
text=main.read_text('utf-8');html=index.read_text('utf-8')
assert text.count(old)==1 and text.count(reply)==1,'Unrecognized or already modified bundle'
assert '<head>' in html
for file in (main,index):
    backup=file.with_name(file.name+'.xtprobe-original')
    assert not backup.exists(),'Backup already exists: inspect before reinstalling'
config=root/'cef-probe-local.json'
token=secrets.token_hex(24)
config.write_text(json.dumps({'token':token}),encoding='utf-8')
for file in (main,index):file.with_name(file.name+'.xtprobe-original').write_bytes(file.read_bytes())
(assets/'xt-cef-probe.js').write_text((root/'cef-probe.js').read_text('utf-8').replace('__TOKEN__',token),encoding='utf-8')
main.write_text(text.replace(old,new).replace(reply,replacement),encoding='utf-8')
index.write_text(html.replace('<head>','<head><script src="./xt-cef-probe.js"></script>',1),encoding='utf-8')
report={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in (main,index)}
(root/'cef-probe-install.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('Installed observer; original index and main bundle saved as .xtprobe-original')
