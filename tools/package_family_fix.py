"""Package the 3.5.207 family parser hotfix from the verified 3.5.206 release."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE_SHA256 = 'f90f33c07dc5b7e731cc6bebc46412bce01ed2b989dd7bd52b5caefa3378be22'


def build(base_archive, destination):
    assert hashlib.sha256(base_archive.read_bytes()).hexdigest() == BASE_SHA256, 'Wrong base archive'
    manifest = json.loads((ROOT / 'update/live/manifest.json').read_text(encoding='utf-8'))
    assert manifest['version'] == '3.5.207'
    code = (ROOT / 'X-TOOL.lua').read_bytes()
    assert len(code) == manifest['script']['bytes']
    assert hashlib.sha256(code).hexdigest() == manifest['script']['sha256']
    assert code == (ROOT / 'update/live/versions/3.5.207/X-TOOL.lua').read_bytes()
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(base_archive) as source:
        assert source.testzip() is None
        assert source.read('X-TOOL.lua') == (ROOT / 'update/live/versions/3.5.206/X-TOOL.lua').read_bytes()
        with zipfile.ZipFile(destination / 'X-Tools.zip', 'w') as target:
            for info in source.infolist():
                data = code if info.filename == 'X-TOOL.lua' else source.read(info.filename)
                target.writestr(copy.copy(info), data)
        with zipfile.ZipFile(destination / 'X-Tools.zip') as result:
            assert result.testzip() is None
            assert result.namelist() == source.namelist()
            for name in source.namelist():
                assert result.read(name) == (code if name == 'X-TOOL.lua' else source.read(name)), name
            for file in manifest['assets']['files']:
                path = f"resource/X-TOOL/{manifest['assets']['id']}/{file['path']}"
                data = result.read(path)
                assert len(data) == file['bytes']
                assert hashlib.sha256(data).hexdigest() == file['sha256'], path
        print('Verified', len(source.namelist()), 'archive entries; only X-TOOL.lua replaced.')
    (destination / 'X-TOOL.lua').write_bytes(code)
    for path in sorted(destination.iterdir()):
        if path.is_file():
            print(path.name, path.stat().st_size, hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base_archive', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    build(args.base_archive, args.destination)
