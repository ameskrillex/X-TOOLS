"""Trim administrator statue placements and remove the home Legends banner."""
import hashlib
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / '.test-deps'))
from lupa.luajit21 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
serialize = lua.eval('''function(value)
    local function encode(v)
        if type(v)=='string' then return string.format('%q',v) end
        if type(v)~='table' then return tostring(v) end
        local out={}
        if #v>0 then for _,item in ipairs(v)do out[#out+1]=encode(item)end
        else
            local keys={};for key in pairs(v)do keys[#keys+1]=key end;table.sort(keys)
            for _,key in ipairs(keys)do out[#out+1]='['..encode(key)..']='..encode(v[key])end
        end
        return '{'..table.concat(out,', ')..'}'
    end
    return encode(value)
end''')


def keep(section):
    return (not section.startswith('staff_') or section in ('staff_heads', 'staff_deputies')
            or section.endswith('_chief'))


base = ROOT / 'update/live/versions/3.5.209'
code = (base / 'X-TOOL.lua').read_text(encoding='utf-8')


def bounds(name):
    start = code.index("factories['crimelegends." + name + "']=function(...)\n")
    start = code.index('\n', start) + 1
    return start, code.index('\nend\n', start)


start, end = bounds('roster')
body = code[start:end]
roster = lua.execute(body)
before_people = len(roster)
before_placements = sum(len(p.placements) for p in roster.values())
result = []
counts = {}
retained = []
for line in body.splitlines():
    if not line.lstrip().startswith('{id='):
        result.append(line)
        continue
    person = lua.execute('return ' + line.strip().rstrip(','))
    placements = [slot for slot in person.placements.values() if keep(slot.section)]
    if not placements:
        continue
    retained.append(person)
    for slot in placements:
        counts[slot.section] = counts.get(slot.section, 0) + 1
    if len(placements) != len(person.placements):
        person.placements = lua.table_from(placements)
        person.roles = lua.table_from([role for role in person.roles.values() if keep(role.group)])
        if not keep(person.group):
            person.group = placements[0].section
        if person.section and not keep(person.section):
            person.section = placements[0].section
        line = '    ' + serialize(person) + ','
    result.append(line)
code = code[:start] + '\n'.join(result) + '\n' + code[end:]
start, end = bounds('catalog')
catalog = lua.execute(code[start:end])
catalog.sections = lua.table_from([section for section in catalog.sections.values() if keep(section.id)])
catalog.people = len(retained)
catalog.placements = sum(counts.values())
code = code[:start] + '-- Section metadata for the retained statue roles.\nreturn ' + serialize(catalog) + '\n' + code[end:]
start, end = bounds('admin_rows')
rows = lua.execute(code[start:end])
for key in list(rows.keys()):
    if not keep(key):
        rows[key] = None
code = code[:start] + '-- Retained collision-checked AdminZone rows.\nreturn ' + serialize(rows) + '\n' + code[end:]

# Remove both the homepage call and its image-button drawing function.
start = code.index('    local legends=rt.modules.legends_browser\n')
end = code.index('    local rx,ry=', start)
code = code[:start] + code[end:]
start = code.index('    function ui.legendsButton(')
end = code.index('    function ui.icon(', start)
code = code[:start] + code[end:]
code = code.replace('3.5.209', '3.5.210').encode('utf-8')
manifest = json.loads((base / 'manifest.json').read_text(encoding='utf-8'))
manifest.update(version='3.5.210', packagePath='versions/3.5.210/')
manifest['script'].update(bytes=len(code), sha256=hashlib.sha256(code).hexdigest())
encoded = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
for folder in (ROOT / 'update/live', ROOT / 'update/live/versions/3.5.210'):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'X-TOOL.lua').write_bytes(code)
    (folder / 'manifest.json').write_bytes(encoded)
    shutil.copyfile(base / 'assets.pack', folder / 'assets.pack')
(ROOT / 'X-TOOL.lua').write_bytes(code)
print(json.dumps({'before_people': before_people, 'people': len(retained),
                  'before_placements': before_placements, 'placements': sum(counts.values()),
                  'sections': counts, 'script': manifest['script']}, ensure_ascii=False))
