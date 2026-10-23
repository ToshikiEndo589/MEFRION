"""One bounded, locked cycle for the approved free development project.

Processes only authenticated retirement requests already entered in the SQL
ledger. A local LaunchAgent can run this while the Mac is awake; a cloud
schedule is still required before production. Only counts/status are logged.
"""
import fcntl,json,os,subprocess,sys,time,urllib.request
from pathlib import Path
from process_account_retirement import execute
ROOT=Path(__file__).resolve().parent.parent
LOCAL=ROOT/'.local'

def write_status(report):
 path=LOCAL/'development-worker-status.json'
 temporary=LOCAL/'development-worker-status.tmp'
 temporary.write_text(json.dumps(report,indent=2));temporary.chmod(0o600);temporary.replace(path)

def cycle():
 config=json.loads((LOCAL/'supabase-server.json').read_text())
 assert config['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
 report={'timestamp':int(time.time()),'scope':'approved development project','retirements_processed':0,'failures':0,'automatic_local':os.environ.get('MEFRION_AUTOMATIC_CYCLE')=='1','cloud_schedule':False}
 for name in ('process_seed_outbox','process_twins_outbox','process_twins_share_outbox','process_publication_outbox','process_deletion_outbox'):
  result=subprocess.run([sys.executable,str(ROOT/'scripts'/(name+'.py'))],capture_output=True,text=True,timeout=240)
  try:data=json.loads(result.stdout);report[name]={k:data.get(k,0) for k in ('processed','failed','stopped','scheduled_jobs_dispatched')}
  except (ValueError,TypeError):report[name]={'failed':1}
  if result.returncode:report['failures']+=1
 req=urllib.request.Request(config['url']+'/rest/v1/rpc/mefrion_retirement_batch',data=b'{}',headers={'apikey':config['secret_key'],'Authorization':'Bearer '+config['secret_key'],'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=30) as response:jobs=json.load(response)
 report['retirements_pending_before']=len(jobs)
 for job in jobs:
  try:report['retirements_processed']+=execute(job['user_id'])['processed']
  except (AssertionError,RuntimeError,OSError):report['failures']+=1
 with urllib.request.urlopen(req,timeout=30) as response:report['retirements_pending_after']=len(json.load(response))
 write_status(report)
 print(json.dumps(report));return report

if __name__=='__main__':
 LOCAL.mkdir(exist_ok=True)
 with (LOCAL/'development-workers.lock').open('a') as lock:
  try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  except BlockingIOError:print('Another bounded development cycle is running.');raise SystemExit(0)
  try:result=cycle()
  except (OSError,ValueError,KeyError,TypeError,subprocess.TimeoutExpired):
   write_status({'timestamp':int(time.time()),'scope':'approved development project','failures':1,'automatic_local':os.environ.get('MEFRION_AUTOMATIC_CYCLE')=='1','cloud_schedule':False})
   print('Development worker cycle failed; next scheduled cycle retries.');raise SystemExit(1)
  raise SystemExit(1 if result['failures'] else 0)
