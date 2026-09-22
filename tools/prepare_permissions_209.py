"""Build the permissions-only 3.5.209 update from immutable 3.5.208."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
base = ROOT / 'update/live/versions/3.5.208'
code = (base / 'X-TOOL.lua').read_text(encoding='utf-8')
changes = {
    'getcar=3,clearhospital=3': 'getcar=1,clearhospital=3',
    'lego=4,tempwork=4,templeader=4': 'lego=4,tempwork=3,templeader=4',
    "{'Лидерство и семья','templeader_window',4}": "{'Лидерство и семья','templeader_window',3}",
    "g.Text('Временное лидерство');g.Separator()": "g.Text('Временное лидерство и работа');g.Separator()",
    'if imgui.TreeNode("Работы") then': 'if currentAdminLevel() >= 3 and imgui.TreeNode("Работы") then',
    'if imgui.Button("Уволиться с временной работы") then': 'if currentAdminLevel() >= 3 and imgui.Button("Уволиться с временной работы") then',
    'AdminZone (/az), /tr и /getcar требуют 3 уровень.': '/getcar доступен с 1 уровня. AdminZone (/az) и /tr требуют 3 уровень.',
}
for old, new in changes.items():
    assert code.count(old) == 1, old
    code = code.replace(old, new)
code = code.replace('3.5.208', '3.5.209').encode('utf-8')
manifest = json.loads((base / 'manifest.json').read_text(encoding='utf-8'))
manifest.update(version='3.5.209', packagePath='versions/3.5.209/')
manifest['script'].update(bytes=len(code), sha256=hashlib.sha256(code).hexdigest())
encoded = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
for folder in (ROOT / 'update/live', ROOT / 'update/live/versions/3.5.209'):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'X-TOOL.lua').write_bytes(code)
    (folder / 'manifest.json').write_bytes(encoded)
    shutil.copyfile(base / 'assets.pack', folder / 'assets.pack')
(ROOT / 'X-TOOL.lua').write_bytes(code)
print('Prepared 3.5.209:', manifest['script'])
