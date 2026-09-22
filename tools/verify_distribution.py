import hashlib,json
from pathlib import Path
from lupa.luajit21 import LuaRuntime
r=Path(__file__).resolve().parents[1]
m=json.loads((r/'update/manifest.json').read_text())
v=r/'update'/m['packagePath']
for key in ('script','assets'):
 info=m[key];data=(v/info['file']).read_bytes()
 assert len(data)==info['bytes']
 assert hashlib.sha256(data).hexdigest()==info['sha256']
 assert data==(r/'update'/info['file']).read_bytes()
assert (r/'X-TOOL.lua').read_bytes()==(v/'X-TOOL.lua').read_bytes()
LuaRuntime(encoding=None).compile((r/'X-TOOL.lua').read_bytes())
pack=(v/'assets.pack').read_bytes()
for item in m['assets']['files']:
 data=pack[item['offset']:item['offset']+item['bytes']]
 assert hashlib.sha256(data).hexdigest()==item['sha256'],item['path']
print('Verified',m['version'],len(m['assets']['files']),'resources')
