"""Synthetic former-provider fixture; approved Free project only."""
import argparse,io,json,subprocess,urllib.request
from pathlib import Path
from uuid import uuid4
from PIL import Image
root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','cleanup']);parser.add_argument('--simulator');args=parser.parse_args()
public=json.loads((root/'.local/supabase-public.json').read_text());assert public['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
identities=json.loads((root/'.local/supabase-test-identities.json').read_text());pet=json.loads((root/'.local/supabase-test-sessions.json').read_text())['pet_id']
protected=root/'.local/cloud-provider-ui.json';tokens={}
def call(path,body=None,role=None,raw=None):
    headers={'apikey':public['anon_key']}
    if role:headers['Authorization']='Bearer '+tokens[role]
    if body is not None:raw=json.dumps(body).encode();headers['Content-Type']='application/json'
    elif raw:headers['Content-Type']='image/jpeg'
    with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=raw,headers=headers),timeout=40) as response:
        data=response.read();return json.loads(data) if 'json' in response.headers.get('Content-Type','') else data
def rpc(name,body={},role='owner'):return call('/rest/v1/rpc/mefrion_'+name,body,role)
for role in ('owner','family'):
    identity=next(i for i in identities if i['role']==role)
    assert identity['email'].startswith('mefrion-test-') and identity['email'].endswith('@example.invalid')
    tokens[role]=call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']})['access_token']
    user=call('/auth/v1/user',role=role);assert user['id']==identity['id'] and user['user_metadata']['test_only']
assert any(p['id']==pet and p['name']=='E2E合成試験' and p['role']=='owner' for p in rpc('list_pets'))
family=next(i for i in identities if i['role']=='family')
if args.action=='prepare':
    assert not protected.exists(),'Clean previous exact synthetic fixture first'
    invite=rpc('invite',{'p_pet':pet});rpc('accept_invite',{'p_token':invite['token'],'p_confirm_scope':True},'family')
    photo=rpc('begin_photo',{'p_pet':pet,'p_request_key':str(uuid4()),'p_title':'退出後管理の合成検証'},'family')
    protected.write_text(json.dumps({'photo':photo['id'],'pet':pet}));protected.chmod(0o600)
    stream=io.BytesIO();Image.new('RGB',(128,128),(240,200,180)).save(stream,format='JPEG')
    call('/storage/v1/object/family-originals/'+photo['path'],role='family',raw=stream.getvalue());rpc('finish_photo',{'p_photo':photo['id']},'family')
    for purpose in ('sns','twins','external_share'):rpc('consent',{'p_photo':photo['id'],'p_purpose':purpose,'p_allowed':True},'family')
    rpc('remove_member',{'p_pet':pet,'p_user':family['id']})
    assert not any(p['id']==pet for p in rpc('list_pets',role='family'))
    if args.simulator:
        container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',args.simulator,'dev.local.mefrion.prototype.uitests.xctrunner','data'],text=True).strip())
        target=container/'Documents/cloud-provider-fixture.json';target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(json.dumps({'anon_key':public['anon_key'],'email':family['email'],'password':family['password'],'photo_id':photo['id']}));target.chmod(0o600)
    print('Former synthetic provider removed from family; safe metadata fixture staged.')
else:
    fixture=json.loads(protected.read_text());assert fixture['pet']==pet
    rpc('delete_photo',{'p_photo':fixture['photo']},'family');protected.unlink();print('Exact synthetic former-provider photo tombstoned.')
