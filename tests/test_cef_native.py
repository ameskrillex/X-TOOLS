"""Exercise the real 32-bit DLL in a disposable host, never in GTA."""
from pathlib import Path
import copy,http.client,json,shutil,socket,subprocess,tempfile,time,unittest,sys
ROOT=Path(__file__).resolve().parents[1]
class Bridge(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory(prefix='test-',dir=ROOT/'artifacts/cef-native');cls.root=Path(cls.tmp.name).resolve()
  for name in ('bridge-host.exe','XToolsBridge.asi'):shutil.copy2(ROOT/'artifacts/cef-native'/name,cls.root/name)
  cls.folder=cls.root/'moonloader/X-TOOL/cef-bridge';cls.folder.mkdir(parents=True)
  with socket.socket() as s:s.bind(('127.0.0.1',0));cls.port=s.getsockname()[1]
  cls.token='a'*48
  (cls.folder/'transport.json').write_text(json.dumps({'token':cls.token,'port':cls.port}))
  cls.proc=subprocess.Popen([str(cls.root/'bridge-host.exe')],cwd=cls.root,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
  assert cls.proc.stdout.readline().strip()=='2','native worker failed to listen'
 @classmethod
 def tearDownClass(cls):
  out,_=cls.proc.communicate('\n',timeout=10);assert cls.proc.returncode==0 and 'stopped=1 status=0' in out
  assert cls.root.is_relative_to((ROOT/'artifacts/cef-native').resolve())
  cls.tmp.cleanup()
 def setUp(self):
  for name in ('response.json','intent.json','capture.json','dossier-capture.jsonl'):
   (self.folder/name).unlink(missing_ok=True)
  self.state={'session':'test','serial':1,'revision':2,'active':True,'ready':True,'captureReady':True,
   'auth':{'show':False,'login':'Test_User','manual':False,'error':False},
   'dialog':{'DIALOG_TYPE':0,'DIALOG_HEADER':'Test_User','DIALOG_TEXT':'Account data','DIALOG_KEYS':['','OK']}}
 def post(self,data,path=None):
  body=json.dumps(data) if not isinstance(data,bytes) else data
  conn=http.client.HTTPConnection('127.0.0.1',self.port,timeout=5)
  conn.request('POST',path or '/'+self.token,body,{'Content-Type':'text/plain'})
  try:r=conn.getresponse();out=r.read();status=r.status
  finally:conn.close()
  return status,json.loads(out) if out else None
 def write(self,name,data):(self.folder/name).write_text(json.dumps(data),encoding='utf-8')
 def test_snapshot_and_response_ownership(self):
  response={'session':'test','serial':1,'revision':2,'expires':time.time()+5,'kind':'hide'}
  self.write('response.json',response);status,out=self.post(self.state)
  self.assertEqual(status,200);self.assertEqual(out['response'],response)
  snap=json.loads((self.folder/'snapshot.json').read_text());self.assertEqual(snap['dialog'],self.state['dialog']);self.assertIn('time',snap)
  for field,value in [('session','other'),('serial',9),('revision',9),('expires',0)]:
   wrong={**response,field:value};self.write('response.json',wrong)
   self.assertIsNone(self.post(self.state)[1]['response'])
 def test_intent_ownership(self):
  self.write('intent.json',{'session':'wrong','expires':time.time()+5});self.assertIsNone(self.post(self.state)[1]['intent'])
  self.write('intent.json',{'session':'test','expires':time.time()+5});self.assertIsNotNone(self.post(self.state)[1]['intent'])
 def test_credential_single_delivery_and_no_disk(self):
  secret='native-test-password-SECRET'
  credential={'session':'test','login':'Test_User','password':secret,'expires':time.time()+3}
  self.assertEqual(self.post(credential,'/'+self.token+'/credential')[0],204)
  other={**self.state,'session':'other'};self.assertIsNone(self.post(other)[1]['credential'])
  self.assertEqual(self.post(self.state)[1]['credential']['password'],secret)
  self.assertIsNone(self.post(self.state)[1]['credential'])
  for p in self.folder.iterdir():self.assertNotIn(secret,p.read_text())
  credential['expires']=0;self.assertEqual(self.post(credential,'/'+self.token+'/credential')[0],400)
 def test_input_and_sensitive_dialog_filter(self):
  self.state['password']='secret';self.state['auth']['password']='secret';self.state['dialog']['DIALOG_INPUT']='secret'
  self.post(self.state);self.assertNotIn('secret',(self.folder/'snapshot.json').read_text())
  self.state['dialog']['DIALOG_TYPE']=3;self.post(self.state)
  self.assertIsNone(json.loads((self.folder/'snapshot.json').read_text())['dialog'])
 def test_real_lua_login_request(self):
  sys.path.insert(0,str(ROOT.parent/'.test-deps'))
  from lupa.luajit21 import LuaRuntime
  lua=LuaRuntime(unpack_returned_tuples=True)
  lua.globals().bridge=lua.execute((ROOT/'libraries/cef_family_bridge.lua').read_text('utf-8'))
  with socket.create_connection(('127.0.0.1',self.port),timeout=2) as client:
   stream=client.makefile('rb')
   def send(data):
    self.assertIn('HTTP/1.0\r\n',data)
    client.sendall(data.encode());return len(data.encode())
   lua.globals().send_native=send
   lua.globals().read_native=lambda:stream.readline().decode().rstrip('\r\n')
   lua.globals().encode_native=lambda t:json.dumps(dict(t.items()))
   lua.globals().epoch=int(time.time());lua.globals().token=self.token
   accepted=lua.execute('''
    local tcp={settimeout=function()end,connect=function()return true end,
     send=function(_,s)return send_native(s)end,receive=function()return read_native()end,close=function()end}
    local api={os={time=function()return epoch end},io={open=function()return {read=function()return ''end,close=function()end}end},
     decodeJson=function()return {token=token}end,encodeJson=encode_native,
     require=function(name)assert(name=='socket');return {tcp=function()return tcp end}end}
    local b=bridge.new({api=api},'unused');b.authTarget={session='lua-login',auth={login='Test_User'}}
    return b:login('lua-regression-secret')
   ''')
   stream.close()
  self.assertTrue(accepted,'real Lua login request must receive HTTP 204')
  state={**self.state,'session':'lua-login'}
  self.assertEqual(self.post(state)[1]['credential']['password'],'lua-regression-secret')
  self.assertIsNone(self.post(state)[1]['credential'])
  for p in self.folder.iterdir():self.assertNotIn('lua-regression-secret',p.read_text())
 def test_capture_dedup_and_cap(self):
  self.state['serial']=77;self.state['capture']=self.state['dialog']
  self.write('capture.json',{'expires':time.time()+100});self.post(self.state);self.post(self.state)
  path=self.folder/'dossier-capture.jsonl';self.assertEqual(len(path.read_text().splitlines()),1)
  path.write_bytes(b'x'*8388600);self.state['revision']+=1;self.post(self.state);self.assertEqual(path.stat().st_size,8388600)
 def test_bad_requests_do_not_kill_worker(self):
  for data in (b'{',b'[]',b'{"nested":'+b'['*40+b'0'+b']'*40+b'}'):
   self.assertEqual(self.post(data)[0],400)
  # Early rejection may reset TCP while the oversized body is still being sent.
  try:self.assertEqual(self.post(b'x'*300000)[0],400)
  except ConnectionResetError:pass
  self.assertEqual(self.post(self.state,'/wrong')[0],404)
  self.assertEqual(self.post(self.state)[0],200)
 def test_repeated_requests(self):
  for n in range(100):
   self.state['serial']=n;self.assertEqual(self.post(self.state)[0],200)
 def test_port_conflict_does_not_replace_listener(self):
  p=subprocess.run([str(self.root/'bridge-host.exe')],cwd=self.root,input='\n',capture_output=True,text=True,timeout=10)
  self.assertTrue(p.returncode==12 or p.stdout.startswith('-3\n'),p.stdout)
  self.assertEqual(self.post(self.state)[0],200)
if __name__=='__main__':unittest.main()
