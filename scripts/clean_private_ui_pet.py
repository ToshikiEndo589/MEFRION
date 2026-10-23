"""Clean images only in the exact dedicated, reserved synthetic UI Pet."""
import json,urllib.request
from pathlib import Path
root=Path(__file__).resolve().parent.parent
public=json.loads((root/'.local/supabase-public.json').read_text());fixture=json.loads((root/'.local/p0-private-ui-pet.json').read_text());owner=next(i for i in json.loads((root/'.local/supabase-test-identities.json').read_text()) if i['id']==fixture['owner'])
assert public['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co';assert owner['email'].startswith('mefrion-test-') and owner['email'].endswith('@example.invalid')
def call(path,body,token=None):
 headers={'apikey':public['anon_key'],'Content-Type':'application/json'}
 if token:headers['Authorization']='Bearer '+token
 with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=json.dumps(body).encode(),headers=headers),timeout=30) as response:return json.load(response)
login=call('/auth/v1/token?grant_type=password',{'email':owner['email'],'password':owner['password']});assert login['user']['id']==owner['id'] and login['user']['user_metadata']['test_only'];token=login['access_token']
def rpc(name,body={}):return call('/rest/v1/rpc/mefrion_'+name,body,token)
assert any(p['id']==fixture['pet'] and p['role']=='owner' and p['name']=='P0 native withdrawal synthetic only' for p in rpc('list_pets'))
rpc('set_public_profile',{'p_pet':fixture['pet'],'p_enabled':False})
photos=rpc('album',{'p_pet':fixture['pet']});assert all(p['mine'] for p in photos)
for photo in photos:rpc('delete_photo',{'p_photo':photo['id']})
print('Exact private synthetic UI images removed:',len(photos))
