"""Run ad hoc signed iPhone Simulator build/tests only when full Xcode is ready."""
import argparse,json,subprocess,sys,re
import time,urllib.request
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--cloud-integration',action='store_true',help='Require pre-staged reserved synthetic fixtures; never treats fixture absence as complete');parser.add_argument('--device',help='Available iPhone Simulator UDID');parser.add_argument('--result-bundle',help='New private xcresult output path');args=parser.parse_args()
# Keep Xcode's approved signing and device settings on existing checkouts.
# Generation is only needed for a missing project; normal verification is read-only.
if not Path('ios/MEFRION.xcodeproj/project.pbxproj').exists():
 subprocess.run([sys.executable,'scripts/generate_xcode_project.py'],check=True)
selected=subprocess.run(['xcode-select','-p'],capture_output=True,text=True)
if selected.returncode or not Path(selected.stdout.strip(),'usr/bin/xcodebuild').exists():
 print('UNVERIFIED: full Xcode developer directory not configured. Install Xcode and iOS Simulator, open once to finish setup. No Swift compilation performed.')
 sys.exit(2)
build=['xcodebuild','-project','ios/MEFRION.xcodeproj','-scheme','MEFRION','-sdk','iphonesimulator','-destination','generic/platform=iOS Simulator','CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-','build']
subprocess.run(build,check=True)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices']
phone=next((d for ds in devices.values() for d in ds if (d['udid']==args.device if args.device else d['name'].startswith('iPhone'))),None)
if not phone:
 print('UNVERIFIED: build passed but no iPhone Simulator available for XCTest.')
 sys.exit(2)
server=subprocess.Popen([sys.executable,'scripts/serve_ui_fixtures.py'])
try:
 for _ in range(50):
  if server.poll() is not None: raise RuntimeError('Disposable UI fixture server failed to start')
  try:
   with urllib.request.urlopen('http://127.0.0.1:8766/health',timeout=1) as response:
    if response.status==200: break
  except OSError: time.sleep(.1)
 else: raise RuntimeError('Disposable UI fixture server did not become ready')
 # A new integration test must not accidentally enter offline CI. Inspect
 # its declared cloud fixture/useCloud dependency rather than a stale list.
 source=Path('ios/MEFRIONUITests/PrototypeUITests.swift').read_text()
 targets=re.split(r'(?=    func test)',source)
 cloud=[]
 for target in targets:
  match=re.match(r'    func (test\w+)',target)
  if match and ('fixture.json' in target or 'MEFRION_TEST_USE_CLOUD' in target):cloud.append(match.group(1))
 excluded=[] if args.cloud_integration else ['-skip-testing:MEFRIONUITests/PrototypeUITests/'+name for name in cloud]
 print('Scope: cloud fixtures included' if args.cloud_integration else f'Scope: offline tests only; {len(cloud)} cloud targets excluded, not certified')

 subprocess.run(['xcodebuild','-project','ios/MEFRION.xcodeproj','-scheme','MEFRION','-destination','id='+phone['udid'],'CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','test']+(['-resultBundlePath',args.result_bundle] if args.result_bundle else [])+excluded,check=True)
finally:
 server.terminate();server.wait(timeout=10)
