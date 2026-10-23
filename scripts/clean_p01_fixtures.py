"""Clean this task's exact protected fixtures; never human photos or accounts."""
import json,subprocess,sys,urllib.request
from uuid import uuid4
from p1_test_support import ROOT,DevelopmentClient
from process_account_retirement import execute
c=DevelopmentClient();c.login();results=[]
path=ROOT/'.local/p01-moderation-case.json'
if path.exists():
 f=json.loads(path.read_text());u=f['target'];assert u['email'].startswith('mefrion-test-moderation-case-') and u['email'].endswith('@example.invalid')
 l=c.check('cleanup-target-login',c.call('/auth/v1/token?grant_type=password',{'email':u['email'],'password':u['password']}));c.tokens['target']=l['access_token'];assert l['user']['id']==u['id'] and l['user']['user_metadata']['test_only']
 rows=c.check('restore-completed-before-retirement',c.rpc('my_moderation',role='target'));assert next(v for v in rows if v['id']==f['report'])['decision']=='restore_account'
 c.check('retire-exact-disposable-target',c.rpc('request_retirement',{'p_expected_user':u['id'],'p_explicit':True,'p_request_key':str(uuid4())},'target'));results.append(execute(u['id']));c.check('remove-exact-owned-moderation-photo',c.rpc('delete_photo',{'p_photo':f['photo']}));path.unlink()
path=ROOT/'.local/retirement-ui-fixture.json'
if path.exists():
 f=json.loads(path.read_text());assert f['email'].startswith('mefrion-test-retirement-ui-');r=execute(f['id']);assert r['processed']==1 or r.get('already_completed');results.append(r);path.unlink()
path=ROOT/'.local/p1-card-ui-fixture.json'
if path.exists():
 f=json.loads(path.read_text());assert f['pet']==c.pet
 for photo in f['photos']:c.check('remove-exact-owned-card-photo',c.rpc('delete_photo',{'p_photo':photo}))
 path.unlink()
subprocess.run([sys.executable,str(ROOT/'scripts/cloud_social_ui_fixture.py'),'cleanup','--simulator','4F89959B-BD92-42D9-BBFB-DFD0F86318B8'],check=True,capture_output=True)
subprocess.run([sys.executable,str(ROOT/'scripts/clean_operator_ui_fixture.py')],check=True,capture_output=True)
container=subprocess.check_output(['xcrun','simctl','get_app_container','4F89959B-BD92-42D9-BBFB-DFD0F86318B8','dev.local.mefrion.prototype.uitests.xctrunner','data'],text=True).strip()
from pathlib import Path
for name in ('p1-card-fixture.json','cloud-fixture.json','cloud-safety-fixture.json','retirement-fixture.json'):
 p=Path(container)/'Documents'/name
 if p.exists():p.unlink()
(ROOT/'docs/evidence/p01-fixture-cleanup.json').write_text(json.dumps({'passed':True,'checks':c.checks,'retirement_cleanup':results,'scope':'exact task-owned synthetic fixtures; normal Keychain and device photo library untouched'},ensure_ascii=False,indent=2));print(json.dumps({'passed':True,'checks':len(c.checks),'retirements':len(results)}))
