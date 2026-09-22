"""Reproducibly build 3.5.208 from immutable 3.5.207 resources and a reviewed template."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '3.5.208'
BASE_VERSION = '3.5.207'
BASE_ZIP_SHA256 = 'f60b177f158f80c9cd82354201bc404d27e3a5815da62513ee58751679758596'
ART_PATHS = {'art/legends-banner.png', 'art/legends-directory.png'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def build(base_archive, destination):
    assert sha(base_archive.read_bytes()) == BASE_ZIP_SHA256, 'Wrong base archive'
    base = ROOT / 'update/live/versions' / BASE_VERSION
    old = json.loads((base / 'manifest.json').read_text(encoding='utf-8'))
    original_pack = (base / 'assets.pack').read_bytes()
    assert sha(original_pack) == old['assets']['sha256']
    assert original_pack[:6] == b'CTAS1\n'
    art = (ROOT / 'artwork/legends-3.5.208.png').read_bytes()
    assert art[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', art[16:24]) == (2172, 724)
    manifest = copy.deepcopy(old)
    manifest['version'] = VERSION
    manifest['packagePath'] = f'versions/{VERSION}/'
    pack = bytearray(b'CTAS1\n')
    identity = bytearray()
    resources = {}
    for item in manifest['assets']['files']:
        data = original_pack[item['offset']:item['offset'] + item['bytes']]
        assert sha(data) == item['sha256'], item['path']
        if item['path'] in ART_PATHS:
            data = art
        item.update(offset=len(pack), bytes=len(data), sha256=sha(data))
        pack.extend(data)
        identity.extend(f"{item['path']}\0{len(data)}\0{sha(data)}\n".encode())
        resources[item['path']] = data
    assets = manifest['assets']
    assets.update(bytes=len(pack), sha256=sha(pack))
    assets['id'] = sha(identity + assets['sha256'].encode())
    template = ROOT / 'release' / VERSION
    code = (template / 'X-TOOL.lua').read_text(encoding='utf-8')
    code = code.replace(BASE_VERSION, VERSION).replace(old['assets']['id'], assets['id'])
    marker = 'local packs=decodeJson([====['
    start = code.index(marker) + len(marker)
    end = code.index(']====])', start)
    packs = json.loads(code[start:end])
    resource = next(p for p in packs if p['label'] == 'resources')
    resource.update(bytes=assets['bytes'], sha256=assets['sha256'], files=assets['files'])
    resource['url'] = f'https://raw.githubusercontent.com/ameskrillex/X-TOOLS/main/update/live/versions/{VERSION}/assets.pack'
    assert resource['directory'] == f"resource/X-TOOL/{assets['id']}"
    code = (code[:start] + json.dumps(packs, ensure_ascii=False, separators=(',', ':')) + code[end:]).encode('utf-8')
    manifest['script'].update(bytes=len(code), sha256=sha(code))
    encoded_manifest = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    for folder in (ROOT / 'update/live', ROOT / 'update/live/versions' / VERSION):
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'X-TOOL.lua').write_bytes(code)
        (folder / 'assets.pack').write_bytes(pack)
        (folder / 'manifest.json').write_bytes(encoded_manifest)
    (ROOT / 'X-TOOL.lua').write_bytes(code)
    (ROOT / 'release-notes.md').write_bytes((template / 'release-notes.md').read_bytes())

    destination.mkdir(parents=True, exist_ok=True)
    old_prefix = f"resource/X-TOOL/{old['assets']['id']}/"
    new_prefix = f"resource/X-TOOL/{assets['id']}/"
    with zipfile.ZipFile(base_archive) as source:
        assert source.testzip() is None
        assert source.read('X-TOOL.lua') == (base / 'X-TOOL.lua').read_bytes()
        expected = {}
        with zipfile.ZipFile(destination / 'X-Tools.zip', 'w') as target:
            for info in source.infolist():
                entry = copy.copy(info)
                data = source.read(info.filename)
                if info.filename == 'X-TOOL.lua':
                    data = code
                elif info.filename.startswith(old_prefix):
                    path = info.filename[len(old_prefix):]
                    entry.filename = new_prefix + path
                    if not info.is_dir():
                        data = resources[path]
                target.writestr(entry, data)
                expected[entry.filename] = sha(data)
        with zipfile.ZipFile(destination / 'X-Tools.zip') as result:
            assert result.testzip() is None
            assert len(result.namelist()) == len(expected) == len(source.namelist())
            for name in result.namelist():
                assert sha(result.read(name)) == expected[name], name
            for item in assets['files']:
                assert sha(result.read(new_prefix + item['path'])) == item['sha256']
    (destination / 'X-TOOL.lua').write_bytes(code)
    print('Verified', len(expected), 'archive entries and', len(resources), 'resources; asset ID', assets['id'])
    for name in ('X-TOOL.lua', 'X-Tools.zip'):
        path = destination / name
        print(name, path.stat().st_size, sha(path.read_bytes()))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base_archive', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    build(args.base_archive, args.destination)
