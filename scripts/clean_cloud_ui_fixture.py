"""Clear only the synthetic owner's named UI-test Pet, never real user data."""
import json,urllib.request
from pathlib import Path
root=Path(__file__).resolve().parent.parent
public=json.loads((root/'.local/supabase-public.json').read_text())
assert public['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
identity=next(i for i in json.loads((root/'.local/supabase-test-identities.json').read_text()) if i['role']=='owner')
assert identity['email'].startswith('mefrion-test-owner-') and identity['email'].endswith('@example.invalid')
pet=json.loads((root/'.local/supabase-test-sessions.json').read_text())['pet_id'];token=None
def call(path,body=None):
    headers={'apikey':public['anon_key']}
    if token:headers['Authorization']='Bearer '+token
    if body is not None:headers['Content-Type']='application/json'
    with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=json.dumps(body).encode() if body is not None else None,headers=headers),timeout=30) as response:return json.load(response)
token=call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']})['access_token']
user=call('/auth/v1/user');assert user['id']==identity['id'] and user['user_metadata']['test_only'] is True
pets=call('/rest/v1/rpc/mefrion_list_pets',{});match=next(p for p in pets if p['id']==pet)
assert match['name']=='E2E合成試験' and match['role']=='owner'
call('/rest/v1/rpc/mefrion_set_public_profile',{'p_pet':pet,'p_enabled':False})
photos=call('/rest/v1/rpc/mefrion_album',{'p_pet':pet});deleted=0
for photo in photos:
    if photo['mine']:call('/rest/v1/rpc/mefrion_delete_photo',{'p_photo':photo['id']});deleted+=1
print(json.dumps({'scope':'synthetic fixture owner/Pet only','tombstoned':deleted,'profile_private':True}))
