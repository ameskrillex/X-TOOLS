from pathlib import Path
import os,json,subprocess,shutil
root=Path(__file__).resolve().parent
assets=Path(os.environ['APPDATA'])/'Advance RP Launcher/bin/plugins/cef/assets'
main=assets/'static/js/main.a4f76ec4.js'
text=main.read_text('utf-8')
anchor='console.log(e),this.setState(O(O(O({},this.state),t)'
assert text.count(anchor)==1
hidden='''if(window.__xtCefHidden){const token=window.__xtCefHiddenToken;this.setState({...this.state,...t,DIALOG_SHOW:false,DIALOG_INPUT:"",DIALOG_ITEM:0});setTimeout(()=>{if(window.__xtCefHidden&&window.__xtCefHiddenToken===token){window.__xtCefHidden=false;this.setState({DIALOG_SHOW:true});window.cef.set_focus(true)}},8000);return;}'''
text=text.replace(anchor,hidden+anchor)
anchor='"showLogin",e=>{let t=JSON.parse(e,function(e,t){return t});'
assert text.count(anchor)==1
auth='''window.__xtCefAuthStatus=()=>({show:this.state.AUTH_SHOW&&this.state.PAGE===2,login:this.state.AUTH_LOGIN,manual:!!this.state.AUTH_PASS,error:!!(this.state.AUTH_PASS_error_text||this.state.AUTH_LOGIN_error_text)});window.__xtCefLogin=(login,password)=>{if(!this.state.AUTH_SHOW||this.state.PAGE!==2||this.state.AUTH_LOGIN!==login||this.state.AUTH_PASS||this.state.AUTH_PASS_error_text||this.state.AUTH_LOGIN_error_text||this.__xtLoginTried)return;this.__xtLoginTried=true;this.setState({AUTH_PASS:password},()=>{if(this.state.AUTH_SHOW&&this.state.PAGE===2&&this.state.AUTH_LOGIN===login)this.sendData(2);this.setState({AUTH_PASS:""})})};'''
text=text.replace(anchor,anchor+auth)
temp=root/'background.test-bundle.js';temp.write_text(text,encoding='utf-8')
subprocess.run([shutil.which('node'),'--check',str(temp)],check=True)
config=json.loads((root/'cef-family-local.json').read_text('utf-8'))
script=(root/'cef-family-bridge.js').read_text('utf-8').replace('__TOKEN__',config['token'])
temp2=root/'background-bridge.test-bundle.js';temp2.write_text(script,encoding='utf-8')
subprocess.run([shutil.which('node'),'--check',str(temp2)],check=True)
bundle=Path('D:/Launcher/Advance Games/moonloader/X-TOOL.lua')
for file in (main,assets/'xt-cef-family.js',bundle):
 backup=file.with_name(file.name+'.background-auth-backup')
 assert not backup.exists()
 backup.write_bytes(file.read_bytes())
main.write_text(text,encoding='utf-8')
(assets/'xt-cef-family.js').write_text(script,encoding='utf-8')
(Path(config['directory'])/'transport.json').write_text(json.dumps({'token':config['token']}),encoding='utf-8')
bundle.write_bytes((root.parent/'artifacts/cef-family-dev/X-TOOL.lua').read_bytes())
print('Installed background offst and saved-login bridge; previous files backed up.')
