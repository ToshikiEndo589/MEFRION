"""Wait for approved iOS runtime, then run real Phase 0/1 iPhone tests."""
from datetime import datetime
from pathlib import Path
import json,subprocess,time,sys
root=Path(__file__).resolve().parent.parent
for _ in range(120):
    runtimes=json.loads(subprocess.check_output(['xcrun','simctl','list','runtimes','-j']))['runtimes']
    ios=next((r for r in runtimes if r.get('isAvailable') and r['name'].startswith('iOS')),None)
    if ios:break
    time.sleep(15)
else:
    print('UNVERIFIED: iOS runtime not ready after 30 minutes',flush=True);sys.exit(2)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices'].get(ios['identifier'],[])
phone=next((d for d in devices if d['name']=='MEFRION iPhone 17'),None)
if phone:
    device=phone['udid']
else:
    device=subprocess.check_output(['xcrun','simctl','create','MEFRION iPhone 17','com.apple.CoreSimulator.SimDeviceType.iPhone-17',ios['identifier']],text=True).strip()
print('iPhone runtime available: '+ios['name']+' / '+device,flush=True)
subprocess.run(['xcrun','simctl','boot',device],capture_output=True)
subprocess.run(['xcrun','simctl','bootstatus',device,'-b'],check=True)
result=root/'docs/evidence'/('ios-phase01-'+datetime.now().strftime('%Y%m%d-%H%M%S')+'.xcresult')
command=['xcodebuild','-project','ios/MEFRION.xcodeproj','-scheme','MEFRION','-destination','id='+device,'CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-resultBundlePath',str(result),'test-without-building']
with (root/'docs/evidence/ios-tests.log').open('w') as log:
    rc=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT).returncode
(root/'docs/evidence/ios-last-run.json').write_text(json.dumps({'command':command,'exit_code':rc,'result_bundle':str(result),'device':device,'runtime':ios['name'],'status':'executed_pass' if rc==0 else 'executed_failure'},indent=2))
print('Actual iPhone test exit '+str(rc)+'; see docs/evidence/ios-tests.log',flush=True)
sys.exit(rc)
