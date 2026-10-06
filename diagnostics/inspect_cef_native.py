"""Static PE import/export and bridge-string inventory; never loads the binaries."""
from pathlib import Path
import struct,re,json,hashlib,os
base=Path(os.environ['APPDATA'])/'Advance RP Launcher/bin/plugins/cef'
paths=[base/'cef_interface.dll',base/'plugins/cef_interface.dll',base/'client.dll',Path('D:/Launcher/Advance Games/AdvanceCore.asi')]
reports=[]
for path in paths:
 if not path.exists():continue
 data=path.read_bytes()
 u16=lambda n:struct.unpack_from('<H',data,n)[0]
 u32=lambda n:struct.unpack_from('<I',data,n)[0]
 pe=u32(60);assert data[pe:pe+4]==b'PE\0\0'
 opt=pe+24;dirs=opt+(96 if u16(opt)==267 else 112)
 sections=[]
 for i in range(u16(pe+6)):
  p=opt+u16(pe+20)+40*i
  sections.append((u32(p+12),max(u32(p+8),u32(p+16)),u32(p+20)))
 def offset(rva):
  for va,size,raw in sections:
   if va<=rva<va+size:return raw+rva-va
  return rva
 def string(rva):
  p=offset(rva);return data[p:data.index(b'\0',p)].decode('ascii',errors='replace')
 exports=[];rva=u32(dirs)
 if rva:
  p=offset(rva);names=offset(u32(p+32));ords=offset(u32(p+36));funcs=offset(u32(p+28))
  for i in range(u32(p+24)):
   exports.append({'name':string(u32(names+4*i)),'rva':hex(u32(funcs+4*u16(ords+2*i)))})
 imports=[];rva=u32(dirs+8)
 if rva:
  p=offset(rva)
  while u32(p+12):
   dll=string(u32(p+12));thunk=offset(u32(p)or u32(p+16));names=[]
   while u32(thunk):
    value=u32(thunk)
    names.append('#'+str(value&65535)if value&0x80000000 else string(value+2));thunk+=4
   imports.append({'dll':dll,'names':names});p+=20
 strings=[]
 for m in re.finditer(rb'[\x20-\x7e]{5,}',data):
  s=m.group().decode('ascii')
  if re.search(r'cef:|dialog|subscribe|emit_event|on_event|rpc|raknet|browser|plugin',s,re.I):
   strings.append({'offset':hex(m.start()),'text':s[:500]})
 report={'path':str(path),'sha256':hashlib.sha256(data).hexdigest(),'exports':exports,'imports':imports,'strings':strings}
 reports.append(report)
 print(json.dumps({'file':path.name,'path':str(path),'exports':exports,'bridge_imports':[x for x in imports if re.search('cef|client|samp',x['dll'],re.I)],'strings':strings[:55]},ensure_ascii=False))
(Path(__file__).parent/'cef-native-report.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2),encoding='utf-8')
