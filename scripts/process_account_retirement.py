"""Process an explicitly requested account retirement in the development project.

Storage deletion and Auth soft erasure are idempotent; the SQL ledger remains
for restore suppression. Receipt is acknowledged only after every step succeeds.
"""
import argparse,json,urllib.request,urllib.error
from pathlib import Path
from uuid import UUID
ROOT=Path(__file__).resolve().parent.parent

def execute(user_id):
 UUID(user_id)
 config=json.loads((ROOT/'.local/supabase-server.json').read_text())
 assert config['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
 def request(path,body=None,method='POST',allow_missing=False):
  headers={'apikey':config['secret_key'],'Authorization':'Bearer '+config['secret_key'],'Content-Type':'application/json'}
  req=urllib.request.Request(config['url']+path,data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method)
  try:
   with urllib.request.urlopen(req,timeout=40) as response:
    data=response.read();return json.loads(data) if data else None
  except urllib.error.HTTPError as error:
   if allow_missing and error.code==404:return None
   raise RuntimeError('retirement_step_failed_'+str(error.code)) from None
 jobs=request('/rest/v1/rpc/mefrion_retirement_batch',{})
 job=next((job for job in jobs if job['user_id']==user_id),None)
 if not job:return {'scope':'requested account','processed':0,'already_completed':True}
 user=request('/auth/v1/admin/users/'+user_id,method='GET')
 assert user['id']==user_id,'retirement_identity_mismatch'
 # Only a user's authenticated, recently reverified RPC creates this queue row.
 # Soft erasure retains the row, so retries can finish interrupted cleanup.
 for item in job['paths']:
  assert item['bucket'] in ('family-originals','public-derived') and '..' not in item['path'] and not item['path'].startswith('/')
  request('/storage/v1/object/'+item['bucket'],{'prefixes':[item['path']]},method='DELETE')
  # Verify absence, not just HTTP success of a delete operation.
  parent,_,filename=item['path'].rpartition('/')
  remaining=request('/storage/v1/object/list/'+item['bucket'],{'prefix':parent,'search':filename,'limit':100})
  assert not any(entry['name']==filename for entry in remaining),'storage_not_removed'
 if not user.get('deleted_at'):
  request('/auth/v1/admin/users/'+user_id,{'should_soft_delete':True},method='DELETE')
 erased=request('/auth/v1/admin/users/'+user_id,method='GET')
 assert erased.get('deleted_at'),'auth_not_erased'
 assert request('/rest/v1/rpc/mefrion_retirement_ack',{'p_user':user_id}) is True
 return {'scope':'requested account','processed':1,'storage_paths_removed':len(job['paths']),'auth_soft_erased':True,'backup_retention_finalized':False}

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--user',required=True);args=parser.parse_args()
 print(json.dumps(execute(args.user)))
