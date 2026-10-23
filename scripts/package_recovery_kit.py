"""Archive reviewed backend source independently; keep recovery secrets local."""
import hashlib,json,secrets,subprocess,gzip
from pathlib import Path
from uuid import uuid4
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
ROOT=Path(__file__).resolve().parents[1]
creds=json.loads((ROOT/'.local/offsite-backup-credentials.json').read_text())
paths=sorted((ROOT/'supabase/migrations').glob('*.sql'))+sorted((ROOT/'supabase/functions').rglob('*.ts'))+[ROOT/'supabase/config.toml',ROOT/'scripts/verify_offsite_backup.py',ROOT/'scripts/deploy_production_functions.py']
source=gzip.compress(json.dumps({'format':'mefrion-recovery-source-v1','files':{str(p.relative_to(ROOT)):p.read_text() for p in paths}},ensure_ascii=False).encode(),mtime=0)
iv=secrets.token_bytes(12);cipher=b'MFRBKP01'+iv+AESGCM(bytes.fromhex(creds['key_hex'])).encrypt(iv,source,b'MFRBKP01');sha=hashlib.sha256(cipher).hexdigest()
key='production/snapshots/'+str(uuid4())+'.bin';temp=ROOT/'.local/recovery-source-upload.bin';temp.touch(mode=0o600,exist_ok=True);temp.chmod(0o600);temp.write_bytes(cipher)
config='url = '+json.dumps('https://mefrion-support.toshiki1108.chatgpt.site/internal-backup/'+key)+'\nrequest = "PUT"\nheader = '+json.dumps('x-mefrion-backup: '+creds['token'])+'\nheader = '+json.dumps('x-content-sha256: '+sha)+'\ndata-binary = '+json.dumps('@'+str(temp))+'\n'
r=subprocess.run(['curl','--fail','--silent','--show-error','--config','-'],input=config.encode(),capture_output=True);assert r.returncode==0
config='url = '+json.dumps('https://mefrion-support.toshiki1108.chatgpt.site/internal-backup/'+key)+'\nheader = '+json.dumps('x-mefrion-backup: '+creds['token'])+'\n'
r=subprocess.run(['curl','--fail','--silent','--show-error','--config','-'],input=config.encode(),capture_output=True);assert r.returncode==0 and hashlib.sha256(r.stdout).hexdigest()==sha
restored=AESGCM(bytes.fromhex(creds['key_hex'])).decrypt(r.stdout[8:20],r.stdout[20:],r.stdout[:8]);assert gzip.decompress(restored)==gzip.decompress(source)
kit={'format':'MEFRION-production-recovery-kit-v1','endpoint':'https://mefrion-support.toshiki1108.chatgpt.site/internal-backup/','credentials':creds,'pgp_passphrase':(ROOT/'.local/production-backup-recovery-key').read_text().strip(),'last_verified_run':'d76fd897-b0a6-4bc3-96ae-e6dd8ca160b0','backend_source_key':key,'backend_source_sha256':sha,'warning':'Secret owner-only recovery material. Store separately from the Mac and never commit or send by chat.'}
p=ROOT/'.local/MEFRION-production-recovery-kit.json';p.touch(mode=0o600,exist_ok=True);p.chmod(0o600);p.write_text(json.dumps(kit,indent=2))
report={'backend_source_files':len(paths),'encrypted_source_bytes':len(cipher),'source_roundtrip_verified':True,'recovery_kit_owner_only_mode':oct(p.stat().st_mode&0o777)}
(ROOT/'docs/evidence/RECOVERY-KIT-20261023.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
