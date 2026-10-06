from pathlib import Path
import os,json,secrets,hashlib
root=Path(__file__).resolve().parent
assets=Path(os.environ['APPDATA'])/'Advance RP Launcher/bin/plugins/cef/assets'
main=assets/'static/js/main.a4f76ec4.js';index=assets/'index.html'
bundle=Path('D:/Launcher/Advance Games/moonloader/X-TOOL.lua')
folder=bundle.parent/'X-TOOL/cef-bridge'
text=main.read_text('utf-8');html=index.read_text('utf-8')
anchor='"showDialog",e=>{let t=JSON.parse(e,function(e,t){return t});'
assert text.count(anchor)==1 and '__xtCefDialogRespond' not in text
tag='<script src="./xt-cef-probe.js"></script>'
assert html.count(tag)==1
for p in (main,index,bundle):assert not p.with_name(p.name+'.cef-family-backup').exists()
folder.mkdir(parents=True,exist_ok=True)
token=secrets.token_hex(24)
(root/'cef-family-local.json').write_text(json.dumps({'token':token,'directory':str(folder)}),encoding='utf-8')
for p in (main,index,bundle):p.with_name(p.name+'.cef-family-backup').write_bytes(p.read_bytes())
(assets/'xt-cef-family.js').write_text((root/'cef-family-bridge.js').read_text('utf-8').replace('__TOKEN__',token),encoding='utf-8')
main.write_text(text.replace(anchor,anchor+'window.__xtCefDialogRespond=(b,r,guard)=>{if(!guard())return;if(b===1&&r>=0&&[2,4,5].includes(this.state.DIALOG_TYPE)){this.setState({DIALOG_ITEM:r},()=>{if(guard())this.responseDialog(b,r)})}else if(guard())this.responseDialog(b,r)};'),encoding='utf-8')
index.write_text(html.replace(tag,tag+'<script src="./xt-cef-family.js"></script>'),encoding='utf-8')
bundle.write_bytes((root.parent/'artifacts/cef-family-dev/X-TOOL.lua').read_bytes())
print('Installed local CEF family development build; backups retained.')
