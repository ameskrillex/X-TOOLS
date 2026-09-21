"""Build 3.5.171 from the verified 3.5.170 distribution, preserving dependencies."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE_SHA256 = '8532e6b6ded91c368e0f64b51069bb1888d42464db767e72539f3311826e0e68'


def build(base_archive, destination):
    assert hashlib.sha256(base_archive.read_bytes()).hexdigest() == BASE_SHA256, 'Wrong base archive'
    manifest = json.loads((ROOT / 'update/manifest.json').read_text(encoding='utf-8'))
    assert manifest['version'] == '3.5.171'
    code = (ROOT / 'X-TOOL.lua').read_bytes()
    assert hashlib.sha256(code).hexdigest() == manifest['script']['sha256']
    assert len(code) == manifest['script']['bytes']
    assert code == (ROOT / 'update/versions/3.5.171/X-TOOL.lua').read_bytes()
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(base_archive) as source:
        assert source.testzip() is None
        assert source.read('X-TOOL.lua') == (ROOT / 'update/versions/3.5.170/X-TOOL.lua').read_bytes()
        installer = source.read('X-Tools-Libraries.lua').replace(b'3.5.170', b'3.5.171')
        replacements = {'X-TOOL.lua': code, 'X-Tools-Libraries.lua': installer}
        with zipfile.ZipFile(destination / 'X-Tools.zip', 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as target:
            for info in source.infolist():
                target.writestr(copy.copy(info), replacements.get(info.filename, source.read(info.filename)))
        with zipfile.ZipFile(destination / 'X-Tools.zip') as result:
            assert result.testzip() is None
            assert result.namelist() == source.namelist()
            for name in source.namelist():
                assert result.read(name) == replacements.get(name, source.read(name)), name
            for file in manifest['assets']['files']:
                name = f"resource/X-TOOL/{manifest['assets']['id']}/{file['path']}"
                payload = result.read(name)
                assert len(payload) == file['bytes']
                assert hashlib.sha256(payload).hexdigest() == file['sha256']
        for name, data in replacements.items():
            (destination / name).write_bytes(data)
        print(f'Built and verified {len(source.namelist())} archive entries; libraries and resources preserved.')
    for path in sorted(destination.iterdir()):
        if path.is_file():
            print(path.name, path.stat().st_size, hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base_archive', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    build(args.base_archive, args.destination)
