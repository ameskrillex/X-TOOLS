"""Prepare by default; --apply installs the reviewed local adapter with backups."""
from pathlib import Path
import os,json,sys,subprocess,shutil,time,hashlib
root=Path(__file__).resolve().parent
config=json.loads((root/'cef-family-local.json').read_text('utf-8'))
assets=Path(os.environ['APPDATA'])/'Advance RP Launcher/bin/plugins/cef/assets'
main=assets/'static/js/main.a4f76ec4.js'
text=main.read_text('utf-8')
anchor='window.__xtCefDialogRespond=(b,r,guard)=>'
assert text.count(anchor)==1
hide='window.__xtCefDialogHide=()=>{window.cef.set_focus(false);this.setState({DIALOG_SHOW:false})};'
if '__xtCefDialogHide' not in text:text=text.replace(anchor,hide+anchor)
else:assert text.count(hide)==1
prepared=root/'adapters.test-bundle.js'
prepared.write_text(text,encoding='utf-8')
subprocess.run([shutil.which('node'),'--check',str(prepared)],check=True)
js=root/'adapters-bridge.test-bundle.js'
js.write_text((root/'cef-family-bridge.js').read_text('utf-8').replace('__TOKEN__',config['token']),encoding='utf-8')
subprocess.run([shutil.which('node'),'--check',str(js)],check=True)
bundle=root.parent/'artifacts/cef-family-dev/X-TOOL.lua'
targets=[(prepared,main),(js,assets/'xt-cef-family.js'),(bundle,Path(config['directory']).parents[1]/'X-TOOL.lua')]
if '--apply' in sys.argv:
    stamp=time.strftime('%Y%m%d-%H%M%S')
    for src,dst in targets:
        backup=dst.with_name(dst.name+'.adapters-'+stamp+'.bak')
        assert not backup.exists()
        backup.write_bytes(dst.read_bytes())
        tmp=dst.with_name(dst.name+'.adapters-tmp')
        tmp.write_bytes(src.read_bytes());os.replace(tmp,dst)
        assert hashlib.sha256(dst.read_bytes()).digest()==hashlib.sha256(src.read_bytes()).digest()
    print('Installed CEF adapters; all three destination hashes match, backups retained.')
else:
    print('Prepared and syntax-checked launcher bridge patch; no game files changed.')
