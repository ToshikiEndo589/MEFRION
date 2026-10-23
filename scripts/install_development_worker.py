"""Install/remove a reversible, local-only development worker LaunchAgent."""
import argparse,os,plistlib,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
LABEL='dev.local.mefrion.development-workers'
agent=Path.home()/'Library/LaunchAgents'/(LABEL+'.plist')
parser=argparse.ArgumentParser();parser.add_argument('action',choices=['install','remove']);args=parser.parse_args()
service='gui/'+str(os.getuid())+'/'+LABEL
if args.action=='remove':
 subprocess.run(['launchctl','bootout',service],capture_output=True)
 if agent.exists():agent.unlink()
 print('Local development worker removed; no external service changed.')
else:
 assert (ROOT/'.local/supabase-server.json').exists()
 if agent.exists():raise SystemExit('Existing worker found; inspect or remove it before replacing.')
 agent.parent.mkdir(parents=True,exist_ok=True)
 settings={'Label':LABEL,'ProgramArguments':[sys.executable,str(ROOT/'scripts/run_development_workers.py')],'WorkingDirectory':str(ROOT),'RunAtLoad':True,'StartInterval':60,'EnvironmentVariables':{'MEFRION_AUTOMATIC_CYCLE':'1'},'ProcessType':'Background','StandardOutPath':str(ROOT/'.local/development-worker.log'),'StandardErrorPath':str(ROOT/'.local/development-worker-error.log')}
 agent.write_bytes(plistlib.dumps(settings));agent.chmod(0o600)
 result=subprocess.run(['launchctl','bootstrap','gui/'+str(os.getuid()),str(agent)],capture_output=True)
 if result.returncode:agent.unlink();raise SystemExit('Local scheduler installation failed; no active worker declared.')
 print('Local development worker installed: every 60 seconds while this Mac is available; no cloud deployment.')
