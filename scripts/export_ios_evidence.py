"""Export XCTest summary and redact protected fixture values from build logs."""
import argparse,json,re,subprocess
from pathlib import Path
root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser();parser.add_argument('name');args=parser.parse_args()
name=args.name
assert re.fullmatch(r'[a-z0-9-]+',name)
hidden=root/'.local';evidence=root/'docs/evidence'
values=set()
def collect(value,key=''):
    if isinstance(value,dict):
        for field,item in value.items():collect(item,field)
    elif isinstance(value,list):
        for item in value:collect(item,key)
    elif isinstance(value,str) and (key in ('email','password','anon_key','secret_key','access_token','refresh_token') or value.startswith(('sb_secret_','sb_publishable_','eyJ'))):values.add(value)
for path in hidden.glob('*.json'):
    collect(json.loads(path.read_text()))
source=hidden/(name+'.log');source.chmod(0o600);log=source.read_text()
for value in sorted(values,key=len,reverse=True):log=log.replace(value,'[REDACTED]')
log=re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+','[REDACTED-JWT]',log)
(evidence/(name+'.log')).write_text(log)
summary=subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(hidden/(name+'.xcresult')),'--format','json'])
(evidence/(name+'-summary.json')).write_bytes(summary)
result=json.loads(summary)
print(json.dumps({key:result[key] for key in ('result','passedTests','failedTests','skippedTests','totalTestCount')}))
