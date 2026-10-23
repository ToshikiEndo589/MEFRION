"""Manual worker for approved SYNTHETIC test project only, never production.

Visibility is revoked synchronously in RPC before eventual blob cleanup.
Retries are safe because storage removal and acknowledgment are idempotent.
"""
import json
import urllib.request
import urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
config=json.loads((ROOT/'.local/supabase-server.json').read_text())
assert config['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co','Only approved test project allowed'
headers={'apikey':config['secret_key'],'Authorization':'Bearer '+config['secret_key'],'Content-Type':'application/json'}
def request(path,body,method='POST'):
 req=urllib.request.Request(config['url']+path,data=json.dumps(body).encode(),headers=headers,method=method)
 with urllib.request.urlopen(req,timeout=30) as r:return json.load(r)
rows=request('/rest/v1/rpc/mefrion_deletion_batch',{})
processed=0;failed=0
for row in rows:
 try:
  bucket=row.get('bucket','family-originals')
  if bucket not in ('family-originals','public-derived') or not row['path'] or '..' in row['path'] or row['path'].startswith('/'): raise ValueError('Object path not allowed')
  request('/storage/v1/object/'+bucket,{'prefixes':[row['path']]},'DELETE')
  parent,_,filename=row['path'].rpartition('/')
  remaining=request('/storage/v1/object/list/'+bucket,{'prefix':parent,'search':filename,'limit':100})
  if any(item['name']==filename for item in remaining): raise ValueError('Object remains')
  if request('/rest/v1/rpc/mefrion_deletion_ack',{'p_id':row['id'],'p_path':row['path']}):processed+=1
 except (OSError,ValueError):failed+=1
result={'scope':'approved synthetic development project only','processed':processed,'failed':failed,'automatic_worker':False}
(ROOT/'docs/evidence/supabase-deletion-worker.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
if failed:raise SystemExit(1)
