from pathlib import Path
import json,os,sys,time,subprocess,shutil
root=Path(__file__).resolve().parent
config=json.loads((root/'cef-family-local.json').read_text('utf-8'))
folder=Path(config['directory'])
assets=Path(os.environ['APPDATA'])/'Advance RP Launcher/bin/plugins/cef/assets'
js=(root/'cef-family-bridge.js').read_text('utf-8').replace('__TOKEN__',config['token'])
temp=root/'managed.test-bundle.js';temp.write_text(js,encoding='utf-8')
subprocess.run([shutil.which('node'),'--check',str(temp)],check=True)
python=Path(sys.executable).with_name('pythonw.exe');assert python.is_file()
for source,dest in ((root.parent/'artifacts/cef-family-dev/X-TOOL.lua',folder.parents[1]/'X-TOOL.lua'),
                    (temp,assets/'xt-cef-family.js')):
 backup=dest.with_name(dest.name+'.managed-'+str(int(time.time()))+'.bak')
 backup.write_bytes(dest.read_bytes());dest.write_bytes(source.read_bytes())
(folder/'launcher.json').write_text(json.dumps({'python':str(python),'script':str(root/'cef_family_server.py')}),encoding='utf-8')
print('Installed managed bridge and dossier capture; backups saved.')
