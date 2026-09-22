import hashlib,json
from pathlib import Path
from lupa.luajit21 import LuaRuntime
r=Path(__file__).resolve().parents[1]
lua=LuaRuntime(encoding=None)
def table(x):
 if isinstance(x,dict):return lua.table_from({k.encode():table(v) for k,v in x.items()})
 if isinstance(x,list):return lua.table_from([table(v) for v in x])
 return x.encode() if isinstance(x,str) else x
old=(r/'update/versions/3.5.171/X-TOOL.lua').read_text(encoding='utf8')
a=old.index('    sources["updates.lua"] = function()\n')+len('    sources["updates.lua"] = function()\n')
b=old.index('\n    end\n    sources[',a)
legacy=lua.execute(old[a:b].encode())
for channel in ('update','update/live'):
 root=r/channel;m=json.loads((root/'manifest.json').read_text(encoding='utf8'));v=root/m['packagePath']
 for key in ('script','assets'):
  info=m[key];data=(v/info['file']).read_bytes()
  assert len(data)==info['bytes']
  assert hashlib.sha256(data).hexdigest()==info['sha256']
  assert data==(root/info['file']).read_bytes()
 code=(v/'X-TOOL.lua').read_bytes();lua.compile(code)
 pack=(v/'assets.pack').read_bytes()
 for item in m['assets']['files']:
  data=pack[item['offset']:item['offset']+item['bytes']]
  assert hashlib.sha256(data).hexdigest()==item['sha256'],item['path']
 if channel=='update':
  legacy[b'validate'](table(m),lambda b:hashlib.sha256(b).hexdigest().encode())
  assert b'/update/live/manifest.json' in code and m['version']=='3.5.203'
 else:
  assert (r/'X-TOOL.lua').read_bytes()==code
 print('Verified',channel,m['version'],len(m['assets']['files']),'resources')
