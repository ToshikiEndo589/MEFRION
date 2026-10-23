"""Move the existing development environment to the reviewed cloud runtime.

Only the two named MEFRION projects are supported. Does not copy users, alter
subscriptions, or publish seed posts. Tokens never enter command arguments.
"""
import json, os, secrets, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REF='pmrvzpuznwzuejbuhaqm'

def main():
 token=os.environ['SUPABASE_ACCESS_TOKEN']
 def query(sql):
  req=urllib.request.Request(f'https://api.supabase.com/v1/projects/{REF}/database/query',data=json.dumps({'query':sql}).encode(),headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
  with urllib.request.urlopen(req,timeout=180) as response:return json.load(response)
 def literal(value):return "'"+value.replace("'","''")+"'"
 query('create schema if not exists supabase_migrations; create table if not exists supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);')
 for name,value in [('mefrion_cloud_worker_token',secrets.token_urlsafe(48)),('mefrion_project_url',f'https://{REF}.supabase.co'),('mefrion_database_backup_key',secrets.token_urlsafe(48))]:
  rows=query('select decrypted_secret as value from vault.decrypted_secrets where name='+literal(name))
  if rows:value=rows[0]['value']
  else:query('select vault.create_secret('+literal(value)+','+literal(name)+',\'MEFRION cloud runtime\')')
  if name!='mefrion_project_url':
   path=ROOT/'.local'/('development-cloud-worker-token' if name.endswith('worker_token') else 'development-backup-recovery-key')
   path.touch(mode=0o600,exist_ok=True);path.chmod(0o600);path.write_text(value)
 for path in sorted((ROOT/'supabase/migrations').glob('20261023000*.sql')):
  if path.name.split('_',1)[0] > '202610230008':continue # Independent production backups have separate credentials.
  version,_,name=path.stem.partition('_')
  if query('select version from supabase_migrations.schema_migrations where version='+literal(version)):continue
  sql=path.read_text()
  # Record the migration atomically with its DDL.
  record='insert into supabase_migrations.schema_migrations(version,name,statements) values('+literal(version)+','+literal(name)+',array['+literal(sql)+']);\ncommit;'
  query(sql.rsplit('commit;',1)[0]+record)
  print(json.dumps({'applied':path.name}))
 print(json.dumps({'cron':query("select jobname,schedule,active from cron.job where jobname like 'mefrion-%'"),'queue':query('select kind,state,count(*) from mefrion_private.cloud_jobs group by kind,state')}))
if __name__=='__main__':main()
