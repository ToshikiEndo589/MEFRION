"""Stage a single disposable account for native account-retirement UI tests."""
import json,secrets,subprocess,urllib.request
from pathlib import Path
from uuid import uuid4
root=Path(__file__).resolve().parent.parent
public=json.loads((root/'.local/supabase-public.json').read_text());server=json.loads((root/'.local/supabase-server.json').read_text());assert public['url']==server['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
path=root/'.local/retirement-ui-fixture.json';assert not path.exists(),'Inspect the exact previous synthetic fixture before replacing it'
identity={'email':'mefrion-test-retirement-ui-'+uuid4().hex+'@example.invalid','password':secrets.token_urlsafe(32)}
def call(endpoint,body,key,token=None):
 headers={'apikey':key,'Content-Type':'application/json'}
 if token:headers['Authorization']='Bearer '+token
 with urllib.request.urlopen(urllib.request.Request(public['url']+endpoint,data=json.dumps(body).encode(),headers=headers),timeout=30) as response:return json.load(response)
user=call('/auth/v1/admin/users',{**identity,'email_confirm':True,'user_metadata':{'test_only':True}},server['secret_key'],server['secret_key']);identity['id']=user['id'];path.write_text(json.dumps(identity));path.chmod(0o600)
login=call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']},public['anon_key']);assert login['user']['id']==identity['id']
call('/rest/v1/rpc/mefrion_create_pet',{'p_name':'Native retirement synthetic only','p_species':'cat'},public['anon_key'],login['access_token'])
outsider=next(i for i in json.loads((root/'.local/supabase-test-identities.json').read_text()) if i['role']=='outsider')
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container','4F89959B-BD92-42D9-BBFB-DFD0F86318B8','dev.local.mefrion.prototype.uitests.xctrunner','data'],text=True).strip())
target=container/'Documents/retirement-fixture.json';target.write_text(json.dumps({**identity,'anon_key':public['anon_key'],'other_email':outsider['email'],'other_password':outsider['password']}));target.chmod(0o600)
print('Dedicated synthetic retirement UI fixture staged; credentials not printed.')
