"""Scan distributable repository text without emitting credential values."""
import base64,json,re,subprocess,os
from pathlib import Path
os.chdir(Path(__file__).resolve().parents[1])
paths=subprocess.check_output(['git','ls-files','-c','-o','--exclude-standard','-z']).decode().split('\0')
findings=[]
for raw in sorted(set(paths)):
 p=Path(raw)
 if not p.is_file() or p.stat().st_size>5_000_000:continue
 if p.suffix.lower() in ('.png','.jpg','.jpeg','.mp4','.pdf','.bin','.wav','.mlmodel','.mlmodelc','.ttf'):continue
 try:text=p.read_text()
 except (UnicodeDecodeError,OSError):continue
 for match in re.finditer(r'\b(?:sb_secret_[A-Za-z0-9_-]{20,}|sbp_[a-fA-F0-9]{30,})\b|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',text):
  findings.append({'file':str(p),'line':text.count('\n',0,match.start())+1,'type':'server-secret-or-private-key'})
 for match in re.finditer(r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{30,}',text):
  try:payload=json.loads(base64.urlsafe_b64decode(match.group().split('.')[1]+'==='))
  except Exception:continue
  if payload.get('role') not in ('anon',None):findings.append({'file':str(p),'line':text.count('\n',0,match.start())+1,'type':'non-public-JWT','role':payload['role']})
result={'files_considered':len(set(paths)),'findings':findings,'secrets_printed':False}
Path('docs/evidence/SECURITY-SOURCE-SECRETS-20261023.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
raise SystemExit(1 if findings else 0)
