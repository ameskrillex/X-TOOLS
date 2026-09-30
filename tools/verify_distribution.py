"""Verify immutable payloads and both legacy migration steps before publishing."""
import hashlib,json
from pathlib import Path
from lupa.luajit21 import LuaRuntime
r=Path(__file__).resolve().parents[1]
lua=LuaRuntime(encoding=None)

def table(x):
 if isinstance(x,dict):return lua.table_from({k.encode():table(v) for k,v in x.items()})
 if isinstance(x,list):return lua.table_from([table(v) for v in x])
 return x.encode() if isinstance(x,str) else x

def updater(path):
 code=path.read_text('utf8');marker='sources["updates.lua"] = function()\n'
 start=code.index(marker)+len(marker)
 end=code.index('\nreturn Updates',start)+len('\nreturn Updates')
 return lua.execute(code[start:end].encode())

def validate(module,manifest):
 module[b'validate'](table(manifest),lambda b:hashlib.sha256(b).hexdigest().encode())

manifests={}
for channel in ('update','update/live','update/current'):
 root=r/channel;m=json.loads((root/'manifest.json').read_text('utf8'));v=root/m['packagePath']
 manifests[channel]=m
 assert json.loads((v/'manifest.json').read_text('utf8'))==m
 for key in ('script','assets'):
  info=m[key];data=(v/info['file']).read_bytes()
  assert len(data)==info['bytes'] and hashlib.sha256(data).hexdigest()==info['sha256']
  assert data==(root/info['file']).read_bytes()
 code=(v/'X-TOOL.lua').read_bytes();lua.compile(code)
 pack=(v/'assets.pack').read_bytes()
 for item in m['assets']['files']:
  blob=pack[item['offset']:item['offset']+item['bytes']]
  assert len(blob)==item['bytes'] and hashlib.sha256(blob).hexdigest()==item['sha256'],item['path']
 validate(updater(v/'X-TOOL.lua'),m)
 print('Verified',channel,m['version'],len(m['assets']['files']),'resources')

validate(updater(r/'update/versions/3.5.171/X-TOOL.lua'),manifests['update'])
for old in ('update/versions/3.5.205/X-TOOL.lua','update/live/versions/3.5.276/X-TOOL.lua','release/3.5.294/X-TOOL.lua'):
 validate(updater(r/old),manifests['update/live'])
bridge=r/'update/live'/manifests['update/live']['packagePath']/'X-TOOL.lua'
validate(updater(bridge),manifests['update/current'])
assert b'/update/current/manifest.json' in bridge.read_bytes()
assert (r/'X-TOOL.lua').read_bytes()==(r/'update/current/X-TOOL.lua').read_bytes()
assert b'/update/current/manifest.json' in (r/'X-TOOL.lua').read_bytes()
assert tuple(map(int,manifests['update/live']['version'].split('.'))) < tuple(map(int,manifests['update/current']['version'].split('.')))
print('Verified legacy compatibility and current public entrypoint')
