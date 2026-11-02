"""Scan distributable files; report locations/types, never credential values."""
import argparse
import base64
import json
import re
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SECRET_PATTERN=re.compile(
    r'\b(?:sb_secret_[A-Za-z0-9_-]{20,}|sbp_[a-fA-F0-9]{30,}'
    r'|(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})'
    r'|(?:xkeysib|xsmtpsib)-[A-Za-z0-9_-]{30,}|AKIA[A-Z0-9]{16})\b'
    r'|-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',re.ASCII
)
JWT_PATTERN=re.compile(r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{30,}')


def scan_text(text,path):
    findings=[]
    for match in SECRET_PATTERN.finditer(text):
        findings.append({'file':str(path),'line':text.count('\n',0,match.start())+1,'type':'server-secret-or-private-key'})
    for match in JWT_PATTERN.finditer(text):
        try:payload=json.loads(base64.urlsafe_b64decode(match.group().split('.')[1]+'==='))
        except (ValueError,TypeError):continue
        # Only the explicitly public Supabase anon JWT is distributable.
        if not isinstance(payload,dict) or payload.get('role')!='anon':
            findings.append({'file':str(path),'line':text.count('\n',0,match.start())+1,'type':'non-public-JWT'})
    return findings


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--report',default='SECURITY-SOURCE-SECRETS-20261023.json')
    parser.add_argument('--bundle',type=Path,help='Also inspect a built .app, including executable/resources')
    args=parser.parse_args()
    paths=set(filter(None,subprocess.check_output(['git','ls-files','-c','-o','--exclude-standard','-z'],cwd=ROOT).decode().split('\0')))
    findings=[];scanned=0
    for raw in sorted(paths):
        p=ROOT/raw
        if not p.is_file() or p.stat().st_size>5_000_000:continue
        if p.suffix.lower() in ('.png','.jpg','.jpeg','.mp4','.pdf','.bin','.wav','.mlmodel','.mlmodelc','.ttf'):continue
        try:text=p.read_text()
        except (UnicodeDecodeError,OSError):continue
        scanned+=1;findings.extend(scan_text(text,raw))
    bundle_files=0
    if args.bundle:
        if args.bundle.suffix!='.app' or not args.bundle.is_dir():parser.error('--bundle must be an existing .app directory')
        for p in args.bundle.rglob('*'):
            if not p.is_file() or p.is_symlink():continue
            # Latin-1 maps bytes one-to-one, so embedded ASCII credentials in a
            # Mach-O executable cannot evade the scan through binary encoding.
            text=p.read_bytes().decode('latin-1')
            findings.extend(scan_text(text,'APP/'+str(p.relative_to(args.bundle))))
            bundle_files+=1
    result={'files_considered':len(paths),'text_files_scanned':scanned,'bundle_files_scanned':bundle_files,'findings':findings,'secrets_printed':False}
    (ROOT/'docs/evidence'/Path(args.report).name).write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result));return int(bool(findings))

if __name__=='__main__':raise SystemExit(main())
