"""Prepare/clean a synthetic public-post fixture for actual Simulator safety UI.

Only approved development URL and reserved synthetic accounts are accepted.
"""
import argparse,io,json,subprocess,sys,urllib.request,urllib.error
from pathlib import Path
from uuid import uuid4
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','cleanup']);parser.add_argument('--simulator');args=parser.parse_args()
public=json.loads((root/'.local/supabase-public.json').read_text());assert public['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
identities=json.loads((root/'.local/supabase-test-identities.json').read_text());primary=json.loads((root/'.local/supabase-test-sessions.json').read_text())['pet_id']
protected=root/'.local/cloud-social-ui.json';tokens={}
def call(path,body=None,role=None,raw=None):
    headers={'apikey':public['anon_key']}
    if role:headers['Authorization']='Bearer '+tokens[role]
    if body is not None:raw=json.dumps(body).encode();headers['Content-Type']='application/json'
    elif raw:headers['Content-Type']='image/jpeg'
    with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=raw,headers=headers),timeout=40) as response:
        data=response.read();return json.loads(data) if 'json' in response.headers.get('Content-Type','') else data
def rpc(name,body={},role='owner'):return call('/rest/v1/rpc/mefrion_'+name,body,role)
for role in ('owner','outsider'):
    identity=next(i for i in identities if i['role']==role)
    assert identity['email'].startswith('mefrion-test-') and identity['email'].endswith('@example.invalid')
    tokens[role]=call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']})['access_token']
    user=call('/auth/v1/user',role=role);assert user['id']==identity['id'] and user['user_metadata']['test_only']
assert any(p['id']==primary and p['name']=='E2E合成試験' and p['role']=='owner' for p in rpc('list_pets'))
if args.action=='prepare':
    rpc('follow',{'p_pet':primary,'p_enabled':False},role='outsider')
    rpc('set_social_name',{'p_name':'E2E outsider'},role='outsider')
    assert not protected.exists(),'Clean the previous exact fixture first'
    photo=rpc('begin_photo',{'p_pet':primary,'p_request_key':str(uuid4()),'p_title':'Native public safety synthetic fixture'})
    protected.write_text(json.dumps({'photo':photo['id'],'pet':primary}));protected.chmod(0o600)
    image=Image.new('RGB',(900,600),(255,242,226));draw=ImageDraw.Draw(image);draw.ellipse((280,100,620,440),fill=(182,126,83));draw.ellipse((245,110,345,265),fill=(168,110,72));draw.ellipse((555,110,655,265),fill=(168,110,72));draw.ellipse((405,300,495,365),fill=(250,222,176));draw.ellipse((390,250,410,275),fill=(65,45,34));draw.ellipse((490,250,510,275),fill=(65,45,34));draw.text((30,555),'MEFRION - OWNED SYNTHETIC TEST IMAGE',fill=(65,45,34));stream=io.BytesIO();image.save(stream,format='JPEG')
    call('/storage/v1/object/family-originals/'+photo['path'],role='owner',raw=stream.getvalue())
    rpc('finish_photo',{'p_photo':photo['id']});rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':True});rpc('set_public_profile',{'p_pet':primary,'p_enabled':True,'p_explicit':True})
    post=rpc('request_publication',{'p_pet':primary,'p_photos':[photo['id']],'p_body':'Native synthetic safety test','p_kind':'post','p_request_key':str(uuid4()),'p_explicit':True})
    protected.write_text(json.dumps({'photo':photo['id'],'pet':primary,'post':post['id']}));protected.chmod(0o600)
    worker=subprocess.run([sys.executable,str(root/'scripts/process_publication_outbox.py')],capture_output=True,text=True,check=True);assert json.loads(worker.stdout)['failed']==0
    assert any(p['id']==post['id'] for p in rpc('public_feed',role='outsider'))
    if args.simulator:
        container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',args.simulator,'dev.local.mefrion.prototype.uitests.xctrunner','data'],text=True).strip())
        outsider=next(i for i in identities if i['role']=='outsider');target=container/'Documents/cloud-safety-fixture.json';target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(json.dumps({'anon_key':public['anon_key'],'email':outsider['email'],'password':outsider['password'],'post_id':post['id']}));target.chmod(0o600)
    print('Synthetic public fixture ready; no credential values printed.')
else:
    fixture=json.loads(protected.read_text());assert fixture['pet']==primary
    rpc('block_pet',{'p_pet':primary,'p_enabled':False},role='outsider')
    rpc('set_public_profile',{'p_pet':primary,'p_enabled':False});rpc('delete_photo',{'p_photo':fixture['photo']})
    protected.unlink();print('Exact synthetic public fixture hidden and original tombstoned.')
