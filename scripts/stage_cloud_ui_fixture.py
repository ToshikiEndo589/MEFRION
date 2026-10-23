"""Stage synthetic owner test credentials ONLY into Simulator test Runner.
No credentials in code/build settings. Fixture is not part of the app bundle.
"""
import json,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parent.parent
sim=sys.argv[1]
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',sim,'dev.local.mefrion.prototype.uitests.xctrunner','data'],text=True).strip())
public=json.loads((root/'.local/supabase-public.json').read_text())
identities=json.loads((root/'.local/supabase-test-identities.json').read_text())
owner=next(i for i in identities if i['role']=='owner')
session=json.loads((root/'.local/supabase-test-sessions.json').read_text())
target=container/'Documents/cloud-fixture.json';target.parent.mkdir(parents=True,exist_ok=True)
target.write_text(json.dumps({'anon_key':public['anon_key'],'email':owner['email'],'password':owner['password'],'pet_id':session['pet_id']}));target.chmod(0o600)
print('Synthetic cloud fixture staged into Simulator test Runner; no values printed.')
