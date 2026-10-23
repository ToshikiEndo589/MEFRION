"""Disable and remove only the synthetic browser factor prepared by this task."""
import json,urllib.request,base64,hmac,hashlib,struct,time
from pathlib import Path
root=Path(__file__).resolve().parent.parent
public=json.loads((root/'.local/supabase-public.json').read_text());service=json.loads((root/'.local/supabase-server.json').read_text());fixture=json.loads((root/'.local/operator-browser-fixture.json').read_text())
assert public['url']==service['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
assert fixture['email'].startswith('mefrion-test-') and fixture['email'].endswith('@example.invalid')
def call(path,body=None,token=None,privileged=False,method=None):
 key=service['secret_key'] if privileged else public['anon_key'];headers={'apikey':key};raw=None
 if token or privileged:headers['Authorization']='Bearer '+(token or key)
 if body is not None:headers['Content-Type']='application/json';raw=json.dumps(body).encode()
 with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=raw,headers=headers,method=method),timeout=30) as response:
  data=response.read();return json.loads(data) if data else None
login=call('/auth/v1/token?grant_type=password',{'email':fixture['email'],'password':fixture['password']});token=login['access_token']
challenge=call('/auth/v1/factors/'+fixture['factor']+'/challenge',{},token)
key=base64.b32decode(fixture['secret']+'='*((8-len(fixture['secret'])%8)%8));digest=hmac.new(key,struct.pack('>Q',int(time.time())//30),hashlib.sha1).digest();offset=digest[-1]&15;code=str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
verified=call('/auth/v1/factors/'+fixture['factor']+'/verify',{'challenge_id':challenge['id'],'code':code},token);fixture['access_token']=verified['access_token']
user=call('/auth/v1/user',token=fixture['access_token']);assert user['id']==fixture['id'] and user['user_metadata']['test_only']
assert call('/rest/v1/rpc/mefrion_grant_test_operator',{'p_user':fixture['id'],'p_role':'moderator','p_active':False},privileged=True)
call('/auth/v1/factors/'+fixture['factor'],token=fixture['access_token'],method='DELETE')
(root/'.local/operator-browser-fixture.json').unlink()
print('Exact synthetic browser role disabled and TOTP factor removed.')
