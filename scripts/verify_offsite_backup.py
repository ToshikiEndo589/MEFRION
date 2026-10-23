"""Restore an encrypted production backup without reading production.

Download only from the independent Site, authenticate/decrypt locally, restore
DB rows into rollback-only TEMP tables and media into a private disposable
bucket in the approved development project. No production writes or reads.
"""
import argparse,hashlib,io,json,re,urllib.error,urllib.request,warnings,subprocess
from pathlib import Path,PurePosixPath
from uuid import UUID,uuid4
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.exceptions import InvalidTag
import pgpy
ROOT=Path(__file__).resolve().parents[1];DEST='https://mefrion-support.toshiki1108.chatgpt.site/internal-backup/';DEV='pmrvzpuznwzuejbuhaqm'
def digest(b):return hashlib.sha256(b).hexdigest()
def main():
 parser=argparse.ArgumentParser();parser.add_argument('run_id',nargs='?',default='latest');args=parser.parse_args()
 creds=json.loads((ROOT/'.local/offsite-backup-credentials.json').read_text());key=AESGCM(bytes.fromhex(creds['key_hex']))
 def raw_download(path):
  if path!='catalog' and not re.fullmatch(r'production/(objects/[a-f0-9]{64}|(?:snapshots|manifests)/[a-f0-9-]{36})\.bin',path):raise RuntimeError('Backup key invalid')
  config='url = '+json.dumps(DEST+path)+'\nheader = '+json.dumps('x-mefrion-backup: '+creds['token'])+'\n'
  result=subprocess.run(['curl','--fail','--silent','--show-error','--max-time','90','--max-filesize',str(54*1024*1024),'--config','-'],input=config.encode(),capture_output=True)
  if result.returncode:raise RuntimeError('Independent download failed: HTTP transport '+str(result.returncode))
  return result.stdout
 def download(path,expected=None):
  data=raw_download(path)
  if expected and digest(data)!=expected:raise RuntimeError('Ciphertext mismatch')
  if data[:8]!=b'MFRBKP01':raise RuntimeError('Invalid backup envelope')
  return key.decrypt(data[8:20],data[20:],data[:8]),data
 if args.run_id=='latest':
  catalog=json.loads(raw_download('catalog'));assert catalog['items'];run=Path(max(catalog['items'],key=lambda x:x['uploaded'])['key']).stem;run=str(UUID(run))
 else:run=str(UUID(args.run_id))
 manifest,envelope=download('production/manifests/'+run+'.bin');manifest=json.loads(manifest)
 assert manifest['id']==run and manifest['format']=='mefrion-offsite-v1'
 tampered=bytearray(envelope);tampered[-1]^=1
 try:key.decrypt(bytes(tampered[8:20]),bytes(tampered[20:]),bytes(tampered[:8]));raise RuntimeError('Tamper accepted')
 except InvalidTag:pass
 snapshot,_=download(manifest['snapshot_key'],manifest['snapshot_sha'])
 with warnings.catch_warnings():
  warnings.simplefilter('ignore');message=pgpy.PGPMessage.from_blob(snapshot);plain=message.decrypt((ROOT/'.local/production-backup-recovery-key').read_text().strip()).message
 document=json.loads(plain);assert document['format']=='mefrion-offsite-v1'
 media=[]
 for item in manifest['objects']:
  if item['bucket'] not in ('family-originals','public-derived') or '..' in PurePosixPath(item['path']).parts or item['path'].startswith('/'):raise RuntimeError('Inventory path invalid')
  data,_=download(item['key'],item['cipher_sha'])
  if digest(data)!=item['plain_sha'] or len(data)!=item['bytes']:raise RuntimeError('Media recovery mismatch')
  media.append((item,data))
 # No production credentials or calls beyond this point either.
 management=(ROOT/'.local/cloud-migration-token').read_text().strip()
 def quote(v):return "'"+v.replace("'","''")+"'"
 statements=['begin'];table_count=0;row_count=0
 for i,(name,rows) in enumerate(document['tables'].items()):
  if not re.fullmatch(r'(auth|mefrion_private|storage)\.[a-z_]+',name):raise RuntimeError('Unexpected table')
  temp='recovery_drill_'+str(i)
  statements += ['create temporary table '+temp+' (like '+name+' including defaults)', 'insert into '+temp+' select * from jsonb_populate_recordset(null::'+temp+','+quote(json.dumps(rows))+ '::jsonb)',"do $$ begin if (select count(*) from "+temp+")<>"+str(len(rows))+" then raise exception 'restore_count';end if;end $$"]
  table_count+=1;row_count+=len(rows)
 statements += ["select jsonb_build_object('tables',"+str(table_count)+",'rows',"+str(row_count)+") as restored",'rollback']
 req=urllib.request.Request('https://api.supabase.com/v1/projects/'+DEV+'/database/query',data=json.dumps({'query':';'.join(statements)+';'}).encode(),headers={'Authorization':'Bearer '+management,'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(req,timeout=180) as r:restored=json.load(r)
 except urllib.error.HTTPError:raise RuntimeError('Temporary database restoration failed; no row data logged') from None
 cfg=json.loads((ROOT/'.local/supabase-server.json').read_text());assert cfg['url']=='https://'+DEV+'.supabase.co'
 bucket='recovery-drill-'+uuid4().hex;uploaded=[]
 def storage(path,body=None,raw=None,mime='application/json',method=None):
  headers={'apikey':cfg['secret_key'],'Authorization':'Bearer '+cfg['secret_key'],'Content-Type':mime}
  if body is not None:raw=json.dumps(body).encode()
  with urllib.request.urlopen(urllib.request.Request(cfg['url']+'/storage/v1/'+path,data=raw,headers=headers,method=method),timeout=90) as r:return r.read()
 storage('bucket',body={'id':bucket,'name':bucket,'public':False,'file_size_limit':52428800})
 try:
  for item,data in media:
   name=item['fingerprint']+Path(item['path']).suffix
   storage('object/'+bucket+'/'+name,raw=data,mime='video/mp4' if name.endswith('.mp4') else 'image/jpeg');uploaded.append(name)
   assert digest(storage('object/'+bucket+'/'+name,method='GET'))==item['plain_sha']
 finally:
  if uploaded:storage('object/'+bucket,body={'prefixes':uploaded},method='DELETE')
  storage('bucket/'+bucket,method='DELETE')
 report={'passed':True,'run_id':run,'production_read_requests':0,'production_write_requests':0,'independent_download':True,'aes_gcm_tamper_rejected':True,'pgp_decrypted_offline':True,'temporary_database_tables':table_count,'temporary_database_rows':row_count,'media_restored_and_readback_verified':len(media),'video_files':sum(i['path'].endswith('.mp4') for i,_ in media),'media_bytes':sum(len(d) for _,d in media),'temporary_private_bucket_removed':True,'retirement_ledger_included':'mefrion_private.account_retirements' in document['tables']}
 (ROOT/'docs/evidence/OFFSITE-RESTORE-20261023.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
