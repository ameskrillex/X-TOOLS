"""Read-only inventory of the launcher's shipped CEF assets (no player logs)."""
from pathlib import Path
import hashlib
import json
import os
import re

root=Path(os.environ['APPDATA'])/'Advance RP Launcher/bin/plugins/cef'
out=Path(__file__).resolve().parent/'cef-static-report.json'
rows=[]
for file in sorted(root.rglob('*')):
    if not file.is_file(): continue
    rel=file.relative_to(root).as_posix()
    if file.suffix.lower() not in ('.js','.html','.json','.dll','.exe'): continue
    row={'path':rel,'bytes':file.stat().st_size}
    if row['bytes']<=20*1024*1024:
        data=file.read_bytes()
        row['sha256']=hashlib.sha256(data).hexdigest()
        if file.suffix.lower() in ('.js','.html'):
            text=data.decode('utf-8',errors='replace')
            matches=[]
            # Candidate bridge call sites, not claims about a supported API.
            pattern=r'\b(?:cef|mp|engine|bridge)\.[A-Za-z_$][\w$]*|(?:addEventListener|dispatchEvent|emit|subscribe|trigger|on)\s*\(\s*["\'][^"\']{1,160}["\']'
            for match in re.finditer(pattern,text):
                matches.append({'offset':match.start(),'candidate':match.group(),
                    'context':text[max(0,match.start()-100):match.end()+180]})
                if len(matches)>=2000:break
            row['candidate_event_sites']=matches
            row['candidate_limit']=2000
    rows.append(row)
assert root.is_dir(),root
out.write_text(json.dumps({'root':str(root),'scope':'Static shipped assets only; candidate sites require review; no runtime hooks installed','files':rows},ensure_ascii=False,indent=2),encoding='utf-8')
print(f'Files: {len(rows)}; candidate sites: {sum(len(r.get("candidate_event_sites",[])) for r in rows)}; report: {out}')
