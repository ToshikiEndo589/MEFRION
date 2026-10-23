"""Non-destructive checks of MEFRION's allowlisted public site only."""
import json,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE='https://mefrion-support.toshiki1108.chatgpt.site'
checks=[]
def call(path,method='GET',headers=None):
 with tempfile.TemporaryDirectory(prefix='mefrion-security-') as tmp:
  h=Path(tmp)/'headers';b=Path(tmp)/'body'
  command=['curl','--silent','--show-error','--max-time','25','--path-as-is','-D',str(h),'-o',str(b),'-w','%{http_code}','-X',method]
  for k,v in (headers or {}).items():command.extend(['-H',k+': '+v])
  result=subprocess.run(command+[BASE+path],capture_output=True,text=True,check=True)
  fields={}
  for line in h.read_text().splitlines():
   if ':' in line:
    k,v=line.split(':',1);fields[k.lower()]=v.strip()
  return int(result.stdout),b.read_bytes(),fields

def check(name,response,statuses,predicate=lambda body,h:True):
 status,body,h=response;ok=status in statuses and predicate(body,h)
 checks.append({'check':name,'status':status,'passed':ok})

def main():
 check('site-health',call('/healthz'),(200,),lambda b,h:json.loads(b)['ok'])
 for path in ('/privacy','/terms','/console/'):
  check('security-headers-'+path,call(path),(200,),lambda b,h:h.get('x-content-type-options')=='nosniff' and h.get('x-frame-options')=='DENY' and 'no-store' in h.get('cache-control',''))
 check('console-public-config-has-no-secret',call('/console/config.json'),(200,),lambda b,h:set(json.loads(b))=={'url','anon_key'} and not json.loads(b)['anon_key'].startswith('sb_secret_'))
 for path in ('/.env','/.git/config','/cloud-shared/not-a-uuid','/cloud-shared/../../internal-backup/catalog'):
  check('path-hidden-'+path,call(path),(400,401,403,404))
 for path in ('/internal-backup/health','/internal-backup/catalog','/internal-backup/production/manifests/00000000-0000-0000-0000-000000000000.bin'):
  check('encrypted-backup-unauthorized-'+path,call(path),(401,403))
  check('encrypted-backup-wrong-token-'+path,call(path,headers={'x-mefrion-backup':'QA-not-a-real-key-'+'x'*40}),(401,403))
 check('site-rejects-unexpected-write',call('/privacy',method='POST'),(405,))
 result={'scope':'public MEFRION site only; no successful mutation attempted','passed':all(c['passed'] for c in checks),'checks':checks}
 (ROOT/'docs/evidence/SECURITY-PUBLIC-SURFACE-20261023.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'passed':result['passed'],'checks':len(checks),'failed':[c['check'] for c in checks if not c['passed']]}))
 return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
