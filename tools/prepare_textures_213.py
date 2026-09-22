"""Withdraw timed texture eviction after the MoonImGui rendering regression."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
base = ROOT / 'update/live/versions/3.5.212'
code = (base / 'X-TOOL.lua').read_text(encoding='utf-8')


def replace(old, new):
    global code
    assert code.count(old) == 1, (code.count(old), old[:80])
    code = code.replace(old, new)


start = code.index('-- Run before a new ImGui frame, or while ImGui processing is disabled.')
end = code.index('function Art.shutdownAll()', start)
code = code[:start] + '''-- Keep native textures alive for the script lifetime. Withdraw timed eviction
-- after reports of blank tinted cards on MoonImGui 1.1.2; free only on shutdown.
''' + code[end:]
replace('local IDLE_MS=15000\n', '')
replace('cache={},attempted={},lastUsed={}', 'cache={},attempted={}')
replace('    self.lastUsed[name]=self.api.getGameTimer()\n', '')
replace('self.cache={};self.attempted={};self.lastUsed={}', 'self.cache={};self.attempted={}')
replace("                    self:service('art.lua').collect(self.api.getGameTimer())\n", '')
replace("            if not self.imgui.Process then self:service('art.lua').collect(self.api.getGameTimer()) end\n", '')

code = code.replace('3.5.212', '3.5.213').encode('utf-8')
manifest = json.loads((base / 'manifest.json').read_text(encoding='utf-8'))
manifest.update(version='3.5.213', packagePath='versions/3.5.213/')
manifest['script'].update(bytes=len(code), sha256=hashlib.sha256(code).hexdigest())
encoded = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
for folder in (ROOT / 'update/live', ROOT / 'update/live/versions/3.5.213'):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'X-TOOL.lua').write_bytes(code)
    (folder / 'manifest.json').write_bytes(encoded)
    shutil.copyfile(base / 'assets.pack', folder / 'assets.pack')
(ROOT / 'X-TOOL.lua').write_bytes(code)
print(json.dumps(manifest['script']))
