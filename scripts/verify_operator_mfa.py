"""Actual TOTP + role boundary; synthetic reserved accounts only, approved Free project."""
import base64,hashlib,hmac,json,secrets,struct,time,urllib.request,urllib.error
from pathlib import Path
from uuid import uuid4
root=Path(__file__).resolve().parent.parent
public=json.loads((root/'.local/supabase-public.json').read_text());service=json.loads((root/'.local/supabase-server.json').read_text())
assert public['url']==service['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
checks=[];identity=None;factor=None;aal2=None

def call(path,body=None,token=None,privileged=False,method=None):
 key=service['secret_key'] if privileged else public['anon_key'];headers={'apikey':key};raw=None
 if token:headers['Authorization']='Bearer '+token
 elif privileged:headers['Authorization']='Bearer '+key
 if body is not None:raw=json.dumps(body).encode();headers['Content-Type']='application/json'
 try:
  with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=raw,headers=headers,method=method),timeout=40) as response:
   data=response.read();return response.status,json.loads(data) if data else {}
 except urllib.error.HTTPError as error:return error.code,{}
def rpc(name,body={},token=None,privileged=False):return call('/rest/v1/rpc/mefrion_'+name,body,token,privileged)
def check(label,result,statuses=(200,),predicate=lambda data:True):
 status,data=result;passed=status in statuses and predicate(data);checks.append({'check':label,'status':status,'passed':passed})
 if not passed:raise RuntimeError(label+' failed')
 return data
try:
 path=root/'.local/supabase-operator-test.json'
 if path.exists():identity=json.loads(path.read_text())
 else:
  email='mefrion-test-operator-'+uuid4().hex+'@example.invalid';password=secrets.token_urlsafe(32)
  user=check('create-synthetic-operator',call('/auth/v1/admin/users',{'email':email,'password':password,'email_confirm':True,'user_metadata':{'test_only':True}},privileged=True),(200,201))
  identity={'id':user['id'],'email':email,'password':password};path.write_text(json.dumps(identity));path.chmod(0o600)
 assert identity['email'].startswith('mefrion-test-') and identity['email'].endswith('@example.invalid')
 login=check('synthetic-operator-password-login',call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']}))
 assert login['user']['id']==identity['id'] and login['user']['user_metadata']['test_only'] is True
 aal1=login['access_token']
 def grant(role,active=True):return rpc('grant_test_operator',{'p_user':identity['id'],'p_role':role,'p_active':active},privileged=True)
 check('anon-operator-queue-denied',rpc('operator_queue'),(401,403))
 check('cannot-self-assign-role',rpc('grant_test_operator',{'p_user':identity['id'],'p_role':'admin','p_active':True},aal1),(403,))
 check('test-moderator-role',grant('moderator'))
 check('role-without-mfa-denied',rpc('operator_queue',token=aal1),(403,))
 enrollment=check('enroll-synthetic-totp',call('/auth/v1/factors',{'factor_type':'totp','friendly_name':'Synthetic '+uuid4().hex},aal1))
 factor=enrollment['id'];secret=enrollment['totp']['secret']
 check('unverified-factor-denied',rpc('operator_queue',token=aal1),(403,))
 challenge=check('challenge-synthetic-totp',call('/auth/v1/factors/'+factor+'/challenge',{},aal1))
 # Only this script's reserved test factor. Never reads/solves a human MFA challenge.
 key=base64.b32decode(secret+'='*((8-len(secret)%8)%8));digest=hmac.new(key,struct.pack('>Q',int(time.time())//30),hashlib.sha1).digest();offset=digest[-1]&15;code=str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
 verified=check('verify-synthetic-totp',call('/auth/v1/factors/'+factor+'/verify',{'challenge_id':challenge['id'],'code':code},aal1))
 aal2=verified['access_token']
 check('actual-aal2-auth-user',call('/auth/v1/user',token=aal2),predicate=lambda user:user['id']==identity['id'])
 check('mfa-moderator-queue',rpc('operator_queue',token=aal2),predicate=lambda rows:all(not any(k in r for k in ('actor_id','target_id','provider_id','object_path')) for r in rows))
 queue=check('service-select-owned-synthetic-report',rpc('report_queue',privileged=True))
 # Select only report evidence created by the synthetic SNS workflow.
 report=next(r for r in queue if r['note']=='Synthetic report only' and r['comment_id'] is not None)
 action={'p_report':report['id'],'p_decision':'dismiss','p_note':'Synthetic MFA review only','p_request_key':str(uuid4())}
 result=check('actual-mfa-moderator-review',rpc('operator_review',action,aal2))
 check('operator-review-exact-retry',rpc('operator_review',action,aal2),predicate=lambda row:row['id']==result['id'])
 check('operator-review-key-conflict',rpc('operator_review',{**action,'p_note':'different'},aal2),(400,))
 check('authenticated-direct-service-review-denied',rpc('review_report',action,aal2),(403,))
 check('test-editor-role',grant('editor'))
 check('mfa-editor-cannot-read-moderation',rpc('operator_queue',token=aal2),(403,))
 check('mfa-editor-cannot-review',rpc('operator_review',{**action,'p_request_key':str(uuid4())},aal2),(403,))
 check('test-admin-role',grant('admin'))
 check('mfa-admin-queue',rpc('operator_queue',token=aal2))
 check('revoke-test-role',grant('admin',False))
 check('revoked-role-immediately-denied',rpc('operator_queue',token=aal2),(403,))
 check('restore-test-moderator',grant('moderator'))
 from datetime import datetime,timedelta,timezone
 check('limited-expiry-assignment',rpc('set_operator',{'p_user':identity['id'],'p_role':'moderator','p_active':True,'p_expires':(datetime.now(timezone.utc)+timedelta(seconds=3)).isoformat(),'p_reason':'Synthetic expiry boundary only'},privileged=True))
 check('before-expiry-queue-allowed',rpc('operator_queue',token=aal2))
 time.sleep(3)
 check('expired-role-old-aal2-denied',rpc('operator_queue',token=aal2),(403,))
 check('restore-test-role-for-factor-check',grant('moderator'))
 logout_session=check('second-password-session-for-logout',call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']}))['access_token']
 logout_challenge=check('second-totp-challenge',call('/auth/v1/factors/'+factor+'/challenge',{},logout_session))
 digest=hmac.new(key,struct.pack('>Q',int(time.time())//30),hashlib.sha1).digest();offset=digest[-1]&15;logout_code=str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
 logout_token=check('second-totp-verify',call('/auth/v1/factors/'+factor+'/verify',{'challenge_id':logout_challenge['id'],'code':logout_code},logout_session))['access_token']
 check('second-session-moderator-before-logout',rpc('operator_queue',token=logout_token))
 check('actual-second-session-auth-logout',call('/auth/v1/logout?scope=local',{},logout_token),(204,))
 check('logged-out-old-jwt-with-verified-factor-denied',rpc('operator_queue',token=logout_token),(403,))
 check('first-session-still-allowed',rpc('operator_queue',token=aal2))
 check('remove-test-totp-factor',call('/auth/v1/factors/'+factor,token=aal2,method='DELETE'));factor=None
 check('removed-factor-old-aal2-denied',rpc('operator_queue',token=aal2),(403,))
 check('actual-auth-logout',call('/auth/v1/logout',{},aal2),(204,))
 check('logged-out-session-old-jwt-denied',rpc('operator_queue',token=aal2),(403,))
 outcome={'passed':True,'scope':'actual Auth / reserved synthetic TOTP / database role / revocation','checks':checks}
except Exception as error:outcome={'passed':False,'failure':str(error),'checks':checks}
finally:
 if identity:
  check('cleanup-disable-synthetic-operator',rpc('grant_test_operator',{'p_user':identity['id'],'p_role':'moderator','p_active':False},privileged=True))
 if factor and aal2:check('cleanup-test-factor',call('/auth/v1/factors/'+factor,token=aal2,method='DELETE'))
 (root/'docs/evidence/supabase-operator-mfa-e2e.json').write_text(json.dumps(outcome,indent=2))
 print(json.dumps({'passed':outcome['passed'],'checks':len(checks),'failure':outcome.get('failure')}))
if not outcome['passed']:raise SystemExit(1)
