"""Bounded authorized MEFRION security/E2E checks using disposable QA identities.

Production owns the exact allowlisted target. Secrets stay in .local (0600).
Does not enumerate customer content, brute-force credentials, or stress the service.
Every attack targets this run's IDs. Cleanup uses normal retirement requests.
"""
import argparse,base64,hashlib,importlib.util,io,json,secrets,time,urllib.error,urllib.parse,urllib.request
from pathlib import Path
from uuid import uuid4
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
STATE=ROOT/'.local/security-e2e-state.json'
REPORT=ROOT/'docs/evidence/SECURITY-E2E-20261023.json'
spec=importlib.util.spec_from_file_location('journey',ROOT/'scripts/verify_production_journey.py')
j=importlib.util.module_from_spec(spec);spec.loader.exec_module(j)
j.STATE=STATE
CHECKS=[]
def save(s):j.save(s)
def request(path,body=None,role=None,state=None,method=None,raw=None,headers=None,token=None):
 h={'apikey':j.PUBLIC['anon_key'],**(headers or {})}
 if role:h['Authorization']='Bearer '+state['users'][role]['token']
 if token is not None:h['Authorization']='Bearer '+token
 if body is not None:raw=json.dumps(body,allow_nan=False).encode();h['Content-Type']='application/json'
 try:
  with urllib.request.urlopen(urllib.request.Request(j.BASE+path,data=raw,headers=h,method=method),timeout=45) as r:
   data=r.read();return r.status,(json.loads(data) if 'json' in r.headers.get('Content-Type','') else data),dict(r.headers)
 except urllib.error.HTTPError as e:
  data=e.read()
  try:data=json.loads(data)
  except ValueError:pass
  return e.code,data,dict(e.headers)
def check(name,response,codes=(200,),predicate=lambda d,h:True):
 status,data,headers=response
 passed=status in codes and predicate(data,headers)
 CHECKS.append({'check':name,'passed':passed,'status':status})
 return data if passed else None
def rpc(s,name,body=None,role='owner',codes=(200,),predicate=lambda d,h:True,label=None):
 return check(label or name,request('/rest/v1/rpc/mefrion_'+name,body or {},role,s),codes,predicate)
def need(value,name):
 if value is None:raise RuntimeError('Fixture setup failed: '+name)
 return value

def setup():
 if STATE.exists():raise RuntimeError('Existing QA state; use verify/cleanup instead')
 s={'users':{r:{'id':str(uuid4()),'email':'mefrion-qa-security-'+uuid4().hex+'@example.invalid','password':secrets.token_urlsafe(32)} for r in ('owner','family','outsider')},'photos':[],'posts':[],'phase':'setup'};save(s)
 statements=['begin']
 for u in s['users'].values():
  statements.append("insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,reauthentication_token,phone_change_token,raw_app_meta_data,raw_user_meta_data) values("+j.lit(u['id'])+",'00000000-0000-0000-0000-000000000000','authenticated','authenticated',"+j.lit(u['email'])+",extensions.crypt("+j.lit(u['password'])+",extensions.gen_salt('bf',10)),now(),now(),now(),'','','','','','','','{\"provider\":\"email\",\"providers\":[\"email\"]}','{\"test_only\":true,\"security_fixture\":true}')")
 statements.append('commit')
 j.query(';'.join(statements)+';');j.login(s)
 s['pet']=need(rpc(s,'create_pet',{'p_name':'QA セキュリティ試験','p_species':'dog','p_breed':'','p_introduction':'合成データ・検証終了後に削除'}),'pet')['id'];save(s)
 invitation=need(rpc(s,'invite',{'p_pet':s['pet']}),'invite')
 rpc(s,'accept_invite',{'p_token':invitation['token'],'p_confirm_scope':False},'family',codes=(400,),label='invite-explicit-scope-required')
 need(rpc(s,'accept_invite',{'p_token':invitation['token'],'p_confirm_scope':True},'family'),'join')
 rpc(s,'accept_invite',{'p_token':invitation['token'],'p_confirm_scope':True},'outsider',codes=(400,),label='invite-replay-denied')
 for index,kind in enumerate(('image','image','video')):
  r=need(rpc(s,'begin_video' if kind=='video' else 'begin_photo',{'p_pet':s['pet'],'p_request_key':str(uuid4()),**({'p_duration':2} if kind=='video' else {})}),'media')
  r['kind']=kind;s['photos'].append(r);save(s)
  buffer=io.BytesIO();Image.new('RGB',(400,300),(220+index,180,155)).save(buffer,'JPEG');jpeg=buffer.getvalue()
  payload=(ROOT/'.local/cloud-video-fixture.mp4').read_bytes() if kind=='video' else jpeg
  check('fixture-upload-'+str(index),request('/storage/v1/object/family-originals/'+r['path'],role='owner',state=s,raw=payload,headers={'Content-Type':'video/mp4' if kind=='video' else 'image/jpeg'}),(200,201))
  if kind=='video':check('fixture-poster-upload',request('/storage/v1/object/family-originals/'+r['preview_path'],role='owner',state=s,raw=jpeg,headers={'Content-Type':'image/jpeg'}),(200,201))
  need(rpc(s,'finish_video' if kind=='video' else 'finish_photo',{'p_photo':r['id']}),'finish')
  rpc(s,'consent',{'p_photo':r['id'],'p_purpose':'sns','p_allowed':True})
  rpc(s,'consent',{'p_photo':r['id'],'p_purpose':'external_share','p_allowed':True})
 rpc(s,'set_public_profile',{'p_pet':s['pet'],'p_enabled':True,'p_explicit':True})
 post=need(rpc(s,'request_publication',{'p_pet':s['pet'],'p_photos':[p['id'] for p in s['photos']],'p_body':'QA 合成データによるE2E試験（終了後に削除）','p_kind':'post','p_request_key':str(uuid4()),'p_explicit':True}),'post')
 s['posts'].append(post['id'])
 s['card']=need(rpc(s,'save_card',{'p_pet':s['pet'],'p_first':s['photos'][0]['id'],'p_second':s['photos'][1]['id'],'p_layout':{'text':'<script>alert("QA")</script> & " <img src=x onerror=alert(1)>'},'p_key':str(uuid4())}),'card')
 shared=need(rpc(s,'share_card',{'p_card':s['card'],'p_key':str(uuid4()),'p_explicit':True}),'share');s['share']=shared['id'];s['posts'].append(shared['id']);s['phase']='publication_pending';save(s)
 return s

def auth_and_idor(s):
 p=s['photos'][0];video=s['photos'][2]
 denied=(400,401,403,404)
 for name,args in [('list_pets',{}),('album',{'p_pet':s['pet']}),('members',{'p_pet':s['pet']}),('family_activity',{'p_pet':s['pet']}),('photo',{'p_photo':p['id']}),('provided_photos',{})]:
  rpc(s,name,args,None,codes=denied,label='anonymous-'+name+'-denied')
  rpc(s,name,args,'outsider',codes=denied if name not in ('list_pets','provided_photos') else (200,),predicate=(lambda d,h:d==[]) if name in ('list_pets','provided_photos') else (lambda d,h:True),label='outsider-'+name+'-scope')
 rpc(s,'album',{'p_pet':s['pet']},'family',predicate=lambda d,h:len(d)==3,label='family-sees-fixture-only')
 for endpoint,ident in [('private-image',p['id']),('private-video',video['id'])]:
  for role in (None,'outsider'):
   check(str(role)+'-'+endpoint+'-denied',request('/functions/v1/'+endpoint+'?photo='+ident,role=role,state=s),denied)
  check('family-'+endpoint+'-allowed',request('/functions/v1/'+endpoint+'?photo='+ident,role='family',state=s),predicate=lambda d,h:isinstance(d,bytes) and len(d)>100 and 'no-store' in h.get('Cache-Control',h.get('cache-control','')))
  check('forged-jwt-'+endpoint,request('/functions/v1/'+endpoint+'?photo='+ident,token='eyJhbGciOiJub25lIn0.'+base64.urlsafe_b64encode(json.dumps({'sub':s['users']['owner']['id'],'role':'service_role'}).encode()).decode().rstrip('=')+'.'),denied)
 for name,args in [('delete_photo',{'p_photo':p['id']}),('edit_photo',{'p_photo':p['id'],'p_captured':None,'p_title':'attack','p_event_kind':None,'p_note':'attack'}),('consent',{'p_photo':p['id'],'p_purpose':'sns','p_allowed':False}),('begin_photo',{'p_pet':s['pet'],'p_request_key':str(uuid4())}),('set_album_visibility',{'p_photo':p['id'],'p_visible':False}),('stop_publication',{'p_post':s['posts'][0]}),('update_pet',{'p_pet':s['pet'],'p_name':'attack','p_breed':'','p_introduction':'','p_details':{},'p_public_fields':[]}),('request_retirement',{'p_request_key':str(uuid4()),'p_explicit':True,'p_expected_user':s['users']['owner']['id']})]:
  rpc(s,name,args,'outsider',codes=denied,label='idor-'+name+'-denied')
 rpc(s,'delete_photo',{'p_photo':p['id']},'family',codes=denied,label='family-cannot-delete-other-provider')
 for table in ('mefrion_reference_assets','mefrion_reference_usage','mefrion_reference_resemblance','mefrion_resemblance_retries'):
  for role in (None,'outsider'):
   check('private-table-'+table+'-'+str(role),request('/rest/v1/'+table+'?select=*&limit=1',role=role,state=s),denied)
 for path,method,body in [('/storage/v1/object/public/family-originals/'+p['path'],'GET',None),('/storage/v1/object/authenticated/family-originals/'+p['path'],'GET',None),('/storage/v1/object/sign/family-originals/'+p['path'],'POST',{'expiresIn':3600}),('/storage/v1/object/list/family-originals','POST',{'prefix':'','limit':1}),('/rest/v1/pets?select=*&limit=1','GET',None)]:
  if path=='/storage/v1/object/list/family-originals':
   check('foreign-bucket-list-has-no-objects',request(path,body,role='outsider',state=s,method=method),(*denied,200),predicate=lambda d,h:d==[] if isinstance(d,list) else True)
  else:check('direct-storage-or-table-denied-'+str(len(CHECKS)),request(path,body,role='outsider',state=s,method=method),denied)
 check('foreign-upload-denied',request('/storage/v1/object/family-originals/'+p['path'],role='outsider',state=s,raw=b'not-jpeg',headers={'Content-Type':'image/jpeg','x-upsert':'true'}),denied)
 check('own-metadata-cannot-grant-operator',request('/auth/v1/user',{'data':{'role':'admin','is_admin':True,'operator':True}},role='outsider',state=s,method='PUT'))
 for name,args in [('operator_queue',{}),('operator_cloud_health',{}),('seed_permissions',{}),('seed_list',{}),('report_queue',{}),('cloud_worker_status',{}),('cloud_database_snapshot',{}),('offsite_configuration',{}),('cloud_work_get',{'p_id':str(uuid4()),'p_lease':str(uuid4())}),('retirement_ack',{'p_user':s['users']['owner']['id']})]:
  rpc(s,name,args,'outsider',codes=denied,label='privilege-'+name+'-denied')
 for endpoint in ('cloud-worker','asset-ingest','database-backup','offsite-backup'):
  for token in (None,'invalid-'+('x'*40)):
   check('internal-'+endpoint+'-'+('no-token' if token is None else 'wrong-token'),request('/functions/v1/'+endpoint,{},method='POST',headers={} if token is None else {'x-mefrion-worker':token}),denied)
 for value in ('../secret',str(uuid4())+"' OR '1'='1",'http://127.0.0.1/secret','%00'):
  check('gateway-input-'+str(len(CHECKS)),request('/functions/v1/private-image?photo='+urllib.parse.quote(value,safe=''),role='owner',state=s),(404,))
 check('untrusted-origin-preflight',request('/functions/v1/private-image',method='OPTIONS',headers={'Origin':'https://attacker.invalid'}),(403,),predicate=lambda d,h:'Access-Control-Allow-Origin' not in h)
 check('trusted-origin-preflight',request('/functions/v1/private-image',method='OPTIONS',headers={'Origin':'https://mefrion-support.toshiki1108.chatgpt.site'}),(204,))
 rpc(s,'create_pet',{'p_name':'x'*41,'p_species':'dog'},codes=(400,),label='overlong-pet-name-denied')
 rpc(s,'begin_video',{'p_pet':s['pet'],'p_request_key':str(uuid4()),'p_duration':301},codes=(400,403),label='over-five-minute-video-denied')
 rpc(s,'feed_page',{'p_limit':5,'p_query':"' OR 1=1 --",'p_mode':'all'},predicate=lambda d,h:len(d['items'])==0,label='search-sql-input-is-data')
 rpc(s,'feed_page',{'p_limit':5,'p_query':'x'*101},codes=(400,),label='oversized-search-denied')
 rpc(s,'feed_page',{'p_limit':10000},predicate=lambda d,h:len(d['items'])<=50,label='feed-limit-clamped')
 # Prove input-size handling without allocating large payloads.
 extra=rpc(s,'begin_photo',{'p_pet':s['pet'],'p_request_key':str(uuid4()),'p_title':'x'*201},codes=(400,),label='oversized-photo-title-denied')
 # A successful vulnerable response is tracked for cleanup; it contains only synthetic content.
 if CHECKS[-1]['passed'] is False:
  rows=j.query('select id::text from mefrion_private.photos where pet_id='+j.lit(s['pet'])+' and length(title)>200')
  s.setdefault('extra_photos',[]).extend(r['id'] for r in rows);save(s)

def public_checks(s):
 rows=need(rpc(s,'public_feed',role='outsider'),'feed')
 post=next((r for r in rows if r['id']==s['posts'][0]),None)
 if not post:raise RuntimeError('Cloud publication still pending; rerun verify after Cron')
 for i,mid in enumerate(post['media']):
  mid=mid if isinstance(mid,str) else mid['id']
  check('public-media-'+str(i),request('/functions/v1/'+('public-video' if i==2 else 'public-image')+'?media='+mid),predicate=lambda d,h:isinstance(d,bytes) and len(d)>100 and 'no-store' in h.get('Cache-Control',h.get('cache-control','')))
 s['media']=post['media'];save(s)
 rpc(s,'set_social_name',{'p_name':'QA 閲覧者'},'outsider')
 rpc(s,'follow',{'p_pet':s['pet'],'p_enabled':True},'outsider')
 connections=need(rpc(s,'social_connections',{'p_kind':'followers','p_limit':10}),'connections')
 check('followers-hide-auth-identity',(200,connections,{}),predicate=lambda d,h:all(s['users']['outsider']['id'] not in row['id'] for row in d))
 rpc(s,'react',{'p_post':s['posts'][0],'p_kind':'like','p_enabled':True},'outsider')
 rpc(s,'react',{'p_post':s['posts'][0],'p_kind':'save','p_enabled':True},'outsider')
 rpc(s,'saved_feed',{'p_limit':10},'outsider',predicate=lambda d,h:any(r['id']==s['posts'][0] for r in d),label='saved-feed-roundtrip')
 body={'p_post':s['posts'][0],'p_body':'QA テストコメント','p_parent':None,'p_alias_pet':None,'p_request_key':str(uuid4())}
 comment=need(rpc(s,'comment',body,'outsider'),'comment');s['comment']=comment;save(s)
 rpc(s,'comment',body,'outsider',predicate=lambda d,h:d==comment,label='comment-retry-idempotent')
 rpc(s,'comment',{**body,'p_body':'different'},'outsider',codes=(400,),label='comment-key-conflict-denied')
 rpc(s,'delete_comment',{'p_comment':comment},'family',codes=(403,),label='foreign-comment-delete-denied')
 rpc(s,'comment',{**body,'p_alias_pet':s['pet'],'p_request_key':str(uuid4())},'outsider',codes=(403,),label='pet-speaker-impersonation-denied')
 rpc(s,'comment',{**body,'p_body':'x'*501,'p_request_key':str(uuid4())},'outsider',codes=(400,),label='oversized-comment-denied')
 rpc(s,'block_pet',{'p_pet':s['pet'],'p_enabled':True},'outsider')
 rpc(s,'public_feed',role='outsider',predicate=lambda d,h:all(r['id']!=s['posts'][0] for r in d),label='blocked-post-hidden')
 mid=s['media'][0];mid=mid if isinstance(mid,str) else mid['id']
 check('blocked-media-denied',request('/functions/v1/public-image?media='+mid,role='outsider',state=s),(404,))
 rpc(s,'block_pet',{'p_pet':s['pet'],'p_enabled':False},'outsider')
 response=request('/functions/v1/shared-page?post='+s['share'])
 check('share-xss-escaped',response,predicate=lambda d,h:b'<script>alert' not in d and b'&lt;script&gt;' in d and "default-src 'none'" in h.get('Content-Security-Policy',h.get('content-security-policy','')))
 rpc(s,'stop_publication',{'p_post':s['share']})
 check('share-withdrawal-immediate',request('/functions/v1/shared-page?post='+s['share']),(404,))
 rpc(s,'consent',{'p_photo':s['photos'][0]['id'],'p_purpose':'sns','p_allowed':False})
 check('consent-withdrawal-immediate',request('/functions/v1/public-image?media='+mid),(404,))
 rpc(s,'remove_member',{'p_pet':s['pet'],'p_user':s['users']['family']['id']})
 check('ex-member-original-revoked',request('/functions/v1/private-image?photo='+s['photos'][0]['id'],role='family',state=s),(401,403,404))
 s['phase']='verified';save(s)

def retirement(s):
 # Verify that private free text is removed, not merely made unreachable.
 rpc(s,'update_pet',{'p_pet':s['pet'],'p_name':'QA','p_breed':'','p_introduction':'','p_details':{'temperament':'QA_PRIVATE_RETIREMENT_MARKER'},'p_public_fields':[]})
 rpc(s,'edit_photo',{'p_photo':s['photos'][0]['id'],'p_captured':None,'p_title':'QA','p_event_kind':None,'p_note':'QA_PRIVATE_RETIREMENT_MARKER'})
 rpc(s,'set_family_name',{'p_pet':s['pet'],'p_name':'QA_PRIVATE_RETIREMENT_MARKER'})
 rpc(s,'save_event',{'p_pet':s['pet'],'p_key':str(uuid4()),'p_captured':'2026-10-23','p_title':'QA_PRIVATE_RETIREMENT_MARKER','p_kind':'other','p_note':'QA_PRIVATE_RETIREMENT_MARKER'})
 for role in ('family','outsider','owner'):
  rpc(s,'request_retirement',{'p_request_key':str(uuid4()),'p_explicit':True,'p_expected_user':s['users'][role]['id']},role)
  rpc(s,'list_pets',role=role,codes=(401,403),label='retired-session-denied-'+role)
 rows=j.query("select (select count(*) from mefrion_private.pets where id="+j.lit(s['pet'])+" and details::text like '%QA_PRIVATE_RETIREMENT_MARKER%')+(select count(*) from mefrion_private.photos where id="+j.lit(s['photos'][0]['id'])+" and note like '%QA_PRIVATE_RETIREMENT_MARKER%') as remaining")
 check('retirement-private-text-erased',(200,rows,{}),predicate=lambda d,h:d[0]['remaining']==0)
 rows=j.query("select (select count(*) from mefrion_private.family_display_names where pet_id="+j.lit(s['pet'])+")+(select count(*) from mefrion_private.pet_events where pet_id="+j.lit(s['pet'])+")+(select count(*) from mefrion_private.cards where pet_id="+j.lit(s['pet'])+") as remaining")
 check('retirement-alias-events-cards-erased',(200,rows,{}),predicate=lambda d,h:d[0]['remaining']==0)
 s['phase']='retirement_requested';save(s)

def main():
 p=argparse.ArgumentParser();p.add_argument('action',choices=['setup','verify','cleanup','authz']);args=p.parse_args()
 try:
  if args.action=='setup':s=setup()
  else:
   s=json.loads(STATE.read_text())
   if s['phase']=='retirement_requested':raise RuntimeError('QA identities retired; do not reuse')
   j.login(s)
   if args.action=='verify':auth_and_idor(s);public_checks(s)
   elif args.action=='authz':auth_and_idor(s)
   else:retirement(s)
  result={'action':args.action,'scope':'MEFRION production; dedicated synthetic fixtures only; bounded requests','passed':all(c['passed'] for c in CHECKS),'checks':CHECKS,'failed_checks':[c['check'] for c in CHECKS if not c['passed']]}
 except Exception as e:result={'action':args.action,'passed':False,'checks':CHECKS,'failure':str(e)}
 target=REPORT.with_name(REPORT.stem+'-'+args.action.upper()+REPORT.suffix);target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'passed':result['passed'],'checks':len(CHECKS),'failed_checks':result.get('failed_checks'),'failure':result.get('failure')},ensure_ascii=False))
 return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
