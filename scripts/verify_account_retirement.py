"""Actual Auth/RPC/Storage retirement boundary, reserved synthetic fixture only."""
import io,json,secrets,urllib.request,urllib.error,sys,subprocess
from pathlib import Path
from uuid import uuid4
from PIL import Image
from process_account_retirement import execute
root=Path(__file__).resolve().parent.parent
public=json.loads((root/'.local/supabase-public.json').read_text());server=json.loads((root/'.local/supabase-server.json').read_text())
assert public['url']==server['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
checks=[]
def call(path,body=None,token=None,admin=False,raw=None,method=None):
 headers={'apikey':server['secret_key'] if admin else public['anon_key']}
 if token:headers['Authorization']='Bearer '+token
 elif admin:headers['Authorization']='Bearer '+server['secret_key']
 if body is not None:raw=json.dumps(body).encode();headers['Content-Type']='application/json'
 elif raw is not None:headers['Content-Type']='image/jpeg'
 req=urllib.request.Request(public['url']+path,data=raw,headers=headers,method=method or ('POST' if raw is not None else 'GET'))
 try:
  with urllib.request.urlopen(req,timeout=40) as r:
   data=r.read();return r.status,json.loads(data) if 'json' in r.headers.get('Content-Type','') else data
 except urllib.error.HTTPError as e:return e.code,{}
def check(name,result,codes=(200,),predicate=lambda data:True):
 status,data=result;passed=status in codes and predicate(data);checks.append({'check':name,'status':status,'passed':passed})
 if not passed:raise RuntimeError(name+' failed status '+str(status))
 return data
def rpc(name,body={},token=None,admin=False):return call('/rest/v1/rpc/mefrion_'+name,body,token,admin)
identity_file=root/'.local/p0-retirement-identity.json'
if identity_file.exists():identity=json.loads(identity_file.read_text())
else:
 identity={'email':'mefrion-test-retirement-'+uuid4().hex+'@example.invalid','password':secrets.token_urlsafe(32)}
 user=check('create-dedicated-synthetic-user',call('/auth/v1/admin/users',{**identity,'email_confirm':True,'user_metadata':{'test_only':True}},admin=True),(200,201));identity['id']=user['id'];identity_file.write_text(json.dumps(identity));identity_file.chmod(0o600)
try:
 login=check('real-password-auth',call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']}));token=login['access_token'];refresh=login['refresh_token']
 check('actual-auth-user',call('/auth/v1/user',token=token),predicate=lambda user:user['id']==identity['id'] and user['user_metadata']['test_only'])
 check('anon-retirement-rejected',rpc('request_retirement',{'p_request_key':str(uuid4()),'p_explicit':True,'p_expected_user':identity['id']}),(401,403))
 check('missing-explicit-confirmation-rejected',rpc('request_retirement',{'p_request_key':str(uuid4()),'p_explicit':False,'p_expected_user':identity['id']},token),(403,))
 check('wrong-identity-retirement-denied',rpc('request_retirement',{'p_request_key':str(uuid4()),'p_explicit':True,'p_expected_user':str(uuid4())},token),(403,))
 pet=check('private-pet-created',rpc('create_pet',{'p_name':'専用退会合成試験','p_species':'dog'},token))
 photo=check('reserve-owned-synthetic-image',rpc('begin_photo',{'p_pet':pet['id'],'p_request_key':str(uuid4())},token))
 image=Image.new('RGB',(64,64),(255,228,216));buffer=io.BytesIO();image.save(buffer,format='JPEG')
 check('store-synthetic-original',call('/storage/v1/object/family-originals/'+photo['path'],token=token,raw=buffer.getvalue()),(200,201))
 check('finish-original',rpc('finish_photo',{'p_photo':photo['id']},token))
 check('original-visible-before-retirement',call('/functions/v1/private-image?photo='+photo['id'],token=token))
 check('third-party-direct-original-denied',call('/storage/v1/object/family-originals/'+photo['path']),(400,401,403,404))
 check('provider-sns-consent',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':True},token))
 check('explicit-public-profile',rpc('set_public_profile',{'p_pet':pet['id'],'p_enabled':True,'p_explicit':True},token))
 post=check('publication-request',rpc('request_publication',{'p_pet':pet['id'],'p_photos':[photo['id']],'p_body':'SYNTHETIC RETIREMENT ONLY','p_kind':'post','p_request_key':str(uuid4()),'p_explicit':True},token))
 # Family fixtures use only the existing reserved synthetic identity.
 family=next(i for i in json.loads((root/'.local/supabase-test-identities.json').read_text()) if i['role']=='family')
 family_login=check('family-password-auth',call('/auth/v1/token?grant_type=password',{'email':family['email'],'password':family['password']}));family_token=family_login['access_token']
 check('family-is-reserved-synthetic',call('/auth/v1/user',token=family_token),predicate=lambda u:u['id']==family['id'] and u['user_metadata']['test_only'])
 invite=check('retiring-owner-family-invite',rpc('invite',{'p_pet':pet['id']},token))
 check('family-joins-retiring-owner',rpc('accept_invite',{'p_token':invite['token'],'p_confirm_scope':True},family_token))
 family_photo=check('family-provider-original-reservation',rpc('begin_photo',{'p_pet':pet['id'],'p_request_key':str(uuid4())},family_token))
 check('family-provider-upload',call('/storage/v1/object/family-originals/'+family_photo['path'],token=family_token,raw=buffer.getvalue()),(200,201))
 check('family-provider-finish',rpc('finish_photo',{'p_photo':family_photo['id']},family_token))
 other_pet=check('other-family-owned-pet',rpc('create_pet',{'p_name':'退会連動専用の共同家族合成試験','p_species':'cat'},family_token))
 other_invite=check('other-family-invites-retiring-user',rpc('invite',{'p_pet':other_pet['id']},family_token))
 check('retiring-user-joins-other-family',rpc('accept_invite',{'p_token':other_invite['token'],'p_confirm_scope':True},token))
 provided=check('retiring-user-provided-original-reservation',rpc('begin_photo',{'p_pet':other_pet['id'],'p_request_key':str(uuid4())},token))
 check('retiring-user-provided-upload',call('/storage/v1/object/family-originals/'+provided['path'],token=token,raw=buffer.getvalue()),(200,201))
 check('retiring-user-provided-finish',rpc('finish_photo',{'p_photo':provided['id']},token))
 survivor=check('other-family-own-original-reservation',rpc('begin_photo',{'p_pet':other_pet['id'],'p_request_key':str(uuid4())},family_token))
 check('other-family-own-upload',call('/storage/v1/object/family-originals/'+survivor['path'],token=family_token,raw=buffer.getvalue()),(200,201))
 check('other-family-own-finish',rpc('finish_photo',{'p_photo':survivor['id']},family_token))
 worker=subprocess.run([sys.executable,str(root/'scripts/process_publication_outbox.py')],capture_output=True,text=True,check=True);assert json.loads(worker.stdout)['failed']==0
 public_post=check('public-post-before-retirement',rpc('public_feed',token=family_token),predicate=lambda rows:any(p['id']==post['id'] for p in rows))
 media=next(p for p in public_post if p['id']==post['id'])['media'][0]
 check('public-derived-before-retirement',call('/functions/v1/public-image?media='+media))
 key=str(uuid4());body={'p_request_key':key,'p_explicit':True,'p_expected_user':identity['id']}
 receipt=check('retirement-accepted',rpc('request_retirement',body,token),predicate=lambda r:r['accepted'] and r['state']=='pending')
 check('exact-retirement-retry',rpc('request_retirement',body,token),predicate=lambda r:r==receipt)
 check('other-key-conflict',rpc('request_retirement',{**body,'p_request_key':str(uuid4())},token),(400,))
 check('old-session-private-original-denied',call('/functions/v1/private-image?photo='+photo['id'],token=token),(401,403,404))
 check('old-session-family-access-false',rpc('family_access',{'p_pet':pet['id']},token),predicate=lambda r:r is False)
 check('old-session-list-pets-denied',rpc('list_pets',token=token),(403,))
 check('old-session-private-album-denied',rpc('album',{'p_pet':pet['id']},token),(403,))
 check('old-session-pet-create-denied',rpc('create_pet',{'p_name':'Cannot resurrect','p_species':'cat'},token),(403,))
 check('old-session-consent-denied',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':True},token),(403,))
 check('old-session-profile-republish-denied',rpc('set_public_profile',{'p_pet':pet['id'],'p_enabled':True,'p_explicit':True},token),(403,))
 check('retired-pet-absent-from-public-search',rpc('search_feed',{'p_query':'専用退会','p_limit':10}),predicate=lambda rows:not any(r['pet_id']==pet['id'] for r in rows))
 check('user-cannot-run-cleanup',rpc('retirement_batch',token=token),(403,))
 check('user-cannot-ack-cleanup',rpc('retirement_ack',{'p_user':identity['id']},token),(403,))
 check('family-access-to-retired-pet-false',rpc('family_access',{'p_pet':pet['id']},family_token),predicate=lambda r:r is False)
 check('family-original-on-retired-pet-denied',call('/functions/v1/private-image?photo='+family_photo['id'],token=family_token),(401,403,404))
 check('family-cannot-reserve-on-retired-pet',rpc('begin_photo',{'p_pet':pet['id'],'p_request_key':str(uuid4())},family_token),(403,))
 check('provided-photo-removed-from-other-family',call('/functions/v1/private-image?photo='+provided['id'],token=family_token),(401,403,404))
 check('unrelated-family-own-photo-survives',call('/functions/v1/private-image?photo='+survivor['id'],token=family_token))
 check('other-family-owner-still-has-access',rpc('family_access',{'p_pet':other_pet['id']},family_token),predicate=lambda r:r is True)
 check('derived-immediately-revoked',call('/functions/v1/public-image?media='+media),(401,403,404))
 cleanup=execute(identity['id']);assert cleanup['processed']==1
 check('password-signin-after-erasure-denied',call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']}),(400,401,403,422))
 check('refresh-after-erasure-denied',call('/auth/v1/token?grant_type=refresh_token',{'refresh_token':refresh}),(400,401,403,422))
 check('pending-job-removed',rpc('retirement_batch',admin=True),predicate=lambda rows:not any(r['user_id']==identity['id'] for r in rows))
 assert execute(identity['id'])['already_completed']
 check('cleanup-surviving-exact-synthetic-photo',rpc('delete_photo',{'p_photo':survivor['id']},family_token))
 result={'passed':True,'checks':checks,'cleanup':cleanup,'scope':'reserved synthetic development account only','remaining':'backup-retention policy, scheduled cloud deployment and additional concurrent relationship scenarios'}
except Exception as error:
 result={'passed':False,'checks':checks,'failure':str(error)}
(root/'docs/evidence/p0-account-retirement-e2e.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps({'passed':result['passed'],'checks':len(checks),'failure':result.get('failure')}))
if not result['passed']:raise SystemExit(1)
