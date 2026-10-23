"""Prepare only our existing synthetic operator for a real browser MFA test."""
import base64,hashlib,hmac,json,struct,time,urllib.request
from pathlib import Path
from uuid import uuid4
root=Path(__file__).resolve().parent.parent
public=json.loads((root/'.local/supabase-public.json').read_text());service=json.loads((root/'.local/supabase-server.json').read_text());identity=json.loads((root/'.local/supabase-operator-test.json').read_text())
assert public['url']==service['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
assert identity['email'].startswith('mefrion-test-') and identity['email'].endswith('@example.invalid')
def call(path,body,token=None,privileged=False):
 key=service['secret_key'] if privileged else public['anon_key'];headers={'apikey':key,'Content-Type':'application/json'}
 if token or privileged:headers['Authorization']='Bearer '+(token or key)
 with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=json.dumps(body).encode(),headers=headers),timeout=30) as response:return json.load(response)
login=call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']});assert login['user']['user_metadata']['test_only'] and login['user']['id']==identity['id']
token=login['access_token'];enrollment=call('/auth/v1/factors',{'factor_type':'totp','friendly_name':'Synthetic browser '+uuid4().hex},token)
factor=enrollment['id'];secret=enrollment['totp']['secret'];challenge=call('/auth/v1/factors/'+factor+'/challenge',{},token)
key=base64.b32decode(secret+'='*((8-len(secret)%8)%8));digest=hmac.new(key,struct.pack('>Q',int(time.time())//30),hashlib.sha1).digest();offset=digest[-1]&15;code=str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
verified=call('/auth/v1/factors/'+factor+'/verify',{'challenge_id':challenge['id'],'code':code},token)
assert call('/rest/v1/rpc/mefrion_grant_test_operator',{'p_user':identity['id'],'p_role':'moderator','p_active':True},privileged=True)
fixture={**identity,'factor':factor,'secret':secret,'access_token':verified['access_token']};path=root/'.local/operator-browser-fixture.json';path.write_text(json.dumps(fixture));path.chmod(0o600)
print('Synthetic MFA browser fixture ready; credentials and TOTP secret not printed.')
