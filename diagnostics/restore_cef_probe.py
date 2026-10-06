"""Restore only files still matching this installation; preserve launcher updates."""
from pathlib import Path
import hashlib
import json
root=Path(__file__).resolve().parent
report=json.loads((root/'cef-probe-install.json').read_text('utf-8'))
for name,digest in report.items():
    file=Path(name)
    assert hashlib.sha256(file.read_bytes()).hexdigest()==digest, 'File changed; refusing overwrite: '+name
    assert file.with_name(file.name+'.xtprobe-original').is_file()
for name in report:
    file=Path(name)
    file.write_bytes(file.with_name(file.name+'.xtprobe-original').read_bytes())
print('Original CEF files restored. Backups retained.')
