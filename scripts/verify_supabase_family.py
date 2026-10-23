"""Opt-in E2E for the ONE approved, non-production Supabase test project.

Uses synthetic credentials/images only. Never prints credentials, emails, tokens,
server responses or image paths. Fixture identities persist in gitignored .local.
"""
import argparse
import io
import json
import secrets
import time
import urllib.request
import urllib.error
from pathlib import Path
from uuid import uuid4
from PIL import Image

ROOT=Path(__file__).resolve().parent.parent
TARGET='https://pmrvzpuznwzuejbuhaqm.supabase.co'
PUBLIC=json.loads((ROOT/'.local/supabase-public.json').read_text())
ADMIN=json.loads((ROOT/'.local/supabase-server.json').read_text())
assert PUBLIC['url']==ADMIN['url']==TARGET, 'Only approved test project allowed'
parser=argparse.ArgumentParser();parser.add_argument('--create-synthetic-accounts',action='store_true');args=parser.parse_args()
checks=[]
def call(path,body=None,key=None,token=None,method=None,raw=None,mime=None):
 headers={'apikey':key or PUBLIC['anon_key']}
 if token:headers['Authorization']='Bearer '+token
 if body is not None:raw=json.dumps(body).encode();mime='application/json'
 if mime:headers['Content-Type']=mime
 req=urllib.request.Request(TARGET+path,data=raw,headers=headers,method=method)
 try:
  with urllib.request.urlopen(req,timeout=30) as r:
   data=r.read();return r.status,json.loads(data) if 'json' in r.headers.get('Content-Type','') else data,dict(r.headers)
 except urllib.error.HTTPError as e:
  data=e.read()
  try:data=json.loads(data)
  except ValueError:pass
  return e.code,data,dict(e.headers)

def check(label,response,statuses=(200,),predicate=None):
 status,data,headers=response
 passed=status in statuses and (predicate is None or predicate(data,headers))
 checks.append({'check':label,'passed':passed,'status':status})
 if not passed:
  code=data.get('code') or data.get('error_code') if isinstance(data,dict) else 'non_json'
  raise RuntimeError(f'{label} failed: HTTP {status}; code {code}')
 return data

def rpc(name,body,token):return call('/rest/v1/rpc/mefrion_'+name,body,token=token)
fixture=ROOT/'.local/supabase-test-identities.json'
try:
 if fixture.exists():identities=json.loads(fixture.read_text())
 else:
  if not args.create_synthetic_accounts:raise RuntimeError('Synthetic identity creation requires opt-in')
  identities=[]
  for role in ['owner','family','outsider']:
   password=secrets.token_urlsafe(36);email=f'mefrion-test-{role}-{uuid4().hex}@example.invalid'
   user=check('create-synthetic-'+role,call('/auth/v1/admin/users',{'email':email,'password':password,'email_confirm':True,'user_metadata':{'test_only':True}},key=ADMIN['secret_key'],token=ADMIN['secret_key']),(200,201))
   identities.append({'id':user['id'],'email':email,'password':password,'role':role})
   fixture.write_text(json.dumps(identities));fixture.chmod(0o600)
  if len(identities)!=3:raise RuntimeError('Incomplete fixture account creation')
 if len(identities)!=3:raise RuntimeError('Incomplete fixture identity file; repair manually before running')
 sessions={}
 for identity in identities:
  session=check('real-password-sign-in-'+identity['role'],call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']}))
  sessions[identity['role']]=session['access_token']
  check('auth-get-user-'+identity['role'],call('/auth/v1/user',token=session['access_token']))
 a,b,c=(sessions[r] for r in ['owner','family','outsider'])
 pet=check('private-pet-create',rpc('create_pet',{'p_name':'E2E合成試験','p_species':'dog'},a))['id']
 check('outsider-cannot-read-album',rpc('album',{'p_pet':pet},c),(401,403))
 invite=check('owner-single-use-invite',rpc('invite',{'p_pet':pet},a))
 check('explicit-invite-scope-required',rpc('accept_invite',{'p_token':invite['token'],'p_confirm_scope':False},b),(400,))
 check('family-accept-invite',rpc('accept_invite',{'p_token':invite['token'],'p_confirm_scope':True},b))
 check('invite-token-cannot-be-reused',rpc('accept_invite',{'p_token':invite['token'],'p_confirm_scope':True},c),(400,))
 key=str(uuid4());body={'p_pet':pet,'p_request_key':key,'p_captured':'2020','p_title':'synthetic JPEG'}
 photo=check('family-reserve-photo',rpc('begin_photo',body,b))
 check('photo-reservation-retry-idempotent',rpc('begin_photo',body,b),predicate=lambda d,h:d['id']==photo['id'])
 check('photo-completion-before-upload-denied',rpc('finish_photo',{'p_photo':photo['id']},b),(400,))
 buffer=io.BytesIO();Image.new('RGB',(128,128),(242,188,170)).save(buffer,format='JPEG');jpeg=buffer.getvalue()
 object_path='/storage/v1/object/family-originals/'+photo['path']
 check('third-party-upload-denied',call(object_path,token=c,raw=jpeg,mime='image/jpeg',method='POST'),(400,401,403))
 check('family-upload-synthetic-image',call(object_path,token=b,raw=jpeg,mime='image/jpeg',method='POST'),(200,201))
 check('family-complete-upload',rpc('finish_photo',{'p_photo':photo['id']},b))
 check('family-album-contains-photo',rpc('album',{'p_pet':pet},b),predicate=lambda d,h:len(d)==1 and d[0]['id']==photo['id'])
 gateway='/functions/v1/private-image?photo='+photo['id']
 check('family-image-gateway',call(gateway,token=b),predicate=lambda d,h:isinstance(d,bytes) and d==jpeg and h.get('Cache-Control')=='private, no-store, max-age=0')
 check('owner-image-gateway',call(gateway,token=a),predicate=lambda d,h:d==jpeg)
 check('outsider-image-gateway-denied',call(gateway,token=c),(404,))
 check('anonymous-image-gateway-denied',call(gateway),(401,))
 check('authenticated-direct-original-denied',call('/storage/v1/object/authenticated/family-originals/'+photo['path'],token=b),(400,401,403,404))
 check('anonymous-public-original-denied',call('/storage/v1/object/public/family-originals/'+photo['path']),(400,401,403,404))
 check('authenticated-signed-url-creation-denied',call('/storage/v1/object/sign/family-originals/'+photo['path'],{'expiresIn':3600},token=b),(400,401,403,404))
 check('owner-cannot-grant-provider-consent',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':True},a),(403,))
 check('provider-grants-specific-purpose',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':True},b))
 check('owner-removes-family',rpc('remove_member',{'p_pet':pet,'p_user':identities[1]['id']},a))
 check('removed-family-album-denied',rpc('album',{'p_pet':pet},b),(403,))
 check('removed-family-image-denied',call(gateway,token=b),(404,))
 check('removed-provider-can-withdraw-consent',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':False},b))
 check('removed-provider-cannot-grant-consent',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':True},b),(403,))
 check('owner-deletes-synthetic-photo',rpc('delete_photo',{'p_photo':photo['id']},a))
 check('deleted-image-denied-to-owner',call(gateway,token=a),(404,))
 check('delete-retry-idempotent',rpc('delete_photo',{'p_photo':photo['id']},a))
 # Keep tokens only in a private local file for the next Simulator E2E step.
 token_path=ROOT/'.local/supabase-test-sessions.json';token_path.write_text(json.dumps({'sessions':sessions,'pet_id':pet}));token_path.chmod(0o600)
 outcome={'passed':True,'scope':'real Auth / synthetic JPEG / family storage gateway','checks':checks,'remaining':['native family E2E','deletion outbox object purge','real human email/Apple/Google','production QA']}
except Exception as error:
 outcome={'passed':False,'scope':'real Auth / synthetic JPEG / family storage gateway','checks':checks,'failure':str(error)}
finally:
 dest=ROOT/'docs/evidence/supabase-family-e2e.json';dest.write_text(json.dumps(outcome,ensure_ascii=False,indent=2))
 print(json.dumps({'passed':outcome['passed'],'completed_checks':len(checks),'failure':outcome.get('failure')},ensure_ascii=False))
if not outcome['passed']:raise SystemExit(1)
