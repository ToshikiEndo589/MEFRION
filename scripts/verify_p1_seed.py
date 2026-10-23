"""Owned synthetic illustrations only. No human operator grants or public release."""
import io,json,subprocess,sys,urllib.request,urllib.error
from datetime import datetime,timedelta,timezone
from uuid import uuid4
from PIL import Image
from p1_test_support import ROOT,DevelopmentClient
c=DevelopmentClient();checks=c.checks;check=c.check;service=json.loads((ROOT/'.local/supabase-server.json').read_text());assert service['url']==c.config['url'];op=None;photos=[];pets=[]
def privileged(path,body):
 h={'apikey':service['secret_key'],'Authorization':'Bearer '+service['secret_key'],'Content-Type':'application/json'}
 try:
  with urllib.request.urlopen(urllib.request.Request(service['url']+path,data=json.dumps(body).encode(),headers=h),timeout=40) as r:return r.status,json.load(r)
 except urllib.error.HTTPError as e:return e.code,{}
def grant(role):return privileged('/rest/v1/rpc/mefrion_grant_test_operator',{'p_user':op['id'],'p_role':role,'p_active':True})
try:
 c.login();subprocess.run([sys.executable,str(ROOT/'scripts/stage_operator_ui_fixture.py')],check=True,capture_output=True)
 op=json.loads((ROOT/'.local/operator-browser-fixture.json').read_text());c.tokens['operator']=op['access_token'];check('grant-synthetic-admin',grant('admin'))
 fixture=ROOT/'.local/seed-publisher-test.json'
 if fixture.exists():publisher=json.loads(fixture.read_text())['id']
 else:
  user=check('create-one-inert-technical-publisher',privileged('/auth/v1/admin/users',{'email':'mefrion-test-managed-'+uuid4().hex+'@example.invalid','email_confirm':True,'user_metadata':{'test_only':True,'managed_publisher':True}}));publisher=user['id'];fixture.write_text(json.dumps({'id':publisher,'scope':'inert reserved development technical publisher, no per-Pet credentials'}));fixture.chmod(0o600)
 check('register-reserved-publisher',privileged('/rest/v1/rpc/mefrion_register_test_publisher',{'p_publisher':publisher}))
 before=check('metrics-before',c.rpc('seed_metrics',role='operator'))
 items=[{'key':'P1-synthetic-'+uuid4().hex,'name':'検証イラスト犬' if i==0 else '検証イラスト猫','species':'dog' if i==0 else 'cat','source':'Original synthetic solid-color illustration; no real pet claims'} for i in range(2)]
 args={'p_publisher':publisher,'p_items':items,'p_key':str(uuid4())}
 check('anonymous-seed-create-denied',c.rpc('seed_create',args,None),(401,403))
 check('ordinary-owner-seed-create-denied',c.rpc('seed_create',args,'owner'),(403,))
 result=check('batch-two-pets-one-operator',c.rpc('seed_create',args,'operator'));pets=[v['id'] for v in result]
 check('batch-idempotency',c.rpc('seed_create',args,'operator'),predicate=lambda v:v==result)
 check('batch-key-conflict',c.rpc('seed_create',{**args,'p_items':[items[0]]},'operator'),(400,))
 check('batch-size-limit',c.rpc('seed_create',{**args,'p_key':str(uuid4()),'p_items':items*11},'operator'),(400,))
 check('staff-cannot-read-ordinary-private-family',c.rpc('album',{'p_pet':c.pet},'operator'),(403,))
 jobs=[]
 for index,pet in enumerate(pets):
  photo=check('managed-photo-reserve',c.rpc('seed_begin_photo',{'p_pet':pet,'p_key':str(uuid4()),'p_title':'Owned synthetic illustration'},'operator'));photos.append(photo['id'])
  out=io.BytesIO();Image.new('RGB',(256,256),(200,145+index*50,150)).save(out,'JPEG')
  check('managed-original-upload',c.call('/storage/v1/object/family-originals/'+photo['path'],role='operator',raw=out.getvalue()),(200,201))
  check('managed-photo-ready',c.rpc('seed_finish_photo',{'p_photo':photo['id']},'operator'))
  check('ordinary-user-managed-album-denied',c.rpc('album',{'p_pet':pet},'owner'),(403,))
  check('staff-managed-album-only',c.rpc('album',{'p_pet':pet},'operator'),predicate=lambda v:any(p['id']==photo['id'] for p in v))
  check('individual-image-rights',c.rpc('seed_photo_rights',{'p_photo':photo['id'],'p_holder':'MEFRION owned synthetic test','p_scope':'Development SNS only; no real animal claims','p_evidence':'Owned generated in scripts/verify_p1_seed.py','p_until':(datetime.now(timezone.utc)+timedelta(days=2)).isoformat(),'p_allowed':True},'operator'))
  body={'p_pet':pet,'p_photos':[photo['id']],'p_body':'MEFRION開発用の所有イラストです。実在のペット・体験ではありません。','p_key':str(uuid4())}
  job=check('managed-draft',c.rpc('seed_draft',body,'operator'));jobs.append(job)
  check('draft-idempotency',c.rpc('seed_draft',body,'operator'),predicate=lambda v:v==job)
  check('unapproved-schedule-rejected',c.rpc('seed_schedule',{'p_job':job,'p_version':1,'p_when':datetime.now(timezone.utc).isoformat(),'p_explicit':True},'operator'),(400,))
  check('rights-required',c.rpc('seed_approve',{'p_job':job,'p_version':1,'p_rights_note':'','p_rights_until':(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()},'operator'),(400,))
  check('editor-role-only',grant('editor'))
  check('editor-cannot-approve',c.rpc('seed_approve',{'p_job':job,'p_version':1,'p_rights_note':'Owned synthetic test only','p_rights_until':(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()},'operator'),(403,))
  check('approver-role',grant('approver'))
  check('approver-cannot-create',c.rpc('seed_create',{**args,'p_key':str(uuid4())},'operator'),(403,))
  check('approval-explicit-rights',c.rpc('seed_approve',{'p_job':job,'p_version':1,'p_rights_note':'Owned synthetic illustrations; development only; no real animals','p_rights_until':(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()},'operator'))
  check('stale-approval-version-rejected',c.rpc('seed_approve',{'p_job':job,'p_version':1,'p_rights_note':'Owned synthetic illustrations','p_rights_until':(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()},'operator'),(400,))
  check('approver-cannot-schedule',c.rpc('seed_now',{'p_job':job,'p_version':2,'p_explicit':True},'operator'),(403,))
  check('dispatcher-admin',grant('admin'))
  check('explicit-schedule',c.rpc('seed_now',{'p_job':job,'p_version':2,'p_explicit':True},'operator'))
 check('ordinary-user-cannot-dispatch',c.rpc('seed_dispatch',role='owner'),(401,403))
 check('due-two-dispatched',privileged('/rest/v1/rpc/mefrion_seed_dispatch',{}),predicate=lambda v:v==2)
 check('no-double-dispatch',privileged('/rest/v1/rpc/mefrion_seed_dispatch',{}),predicate=lambda v:v==0)
 worker=subprocess.run([sys.executable,str(ROOT/'scripts/process_publication_outbox.py')],check=True,capture_output=True,text=True);assert json.loads(worker.stdout)['failed']==0
 feed=check('seed-in-normal-public-feed',c.rpc('feed_page',{'p_query':'検証イラスト'},None),predicate=lambda v:len([r for r in v['items'] if r['pet_id'] in pets])==2)
 check('only-real-reaction-counters', (200,feed),predicate=lambda v:all(r['likes']==0 and r['comments']==0 for r in v['items'] if r['pet_id'] in pets))
 check('no-unfollowed-seed-in-following',c.rpc('feed_page',{'p_mode':'following','p_query':'検証イラスト'},'owner'),predicate=lambda v:not v['items'])
 check('follow-managed-pet',c.rpc('follow',{'p_pet':pets[0],'p_enabled':True},'owner'))
 check('followed-seed-only',c.rpc('feed_page',{'p_mode':'following','p_query':'検証イラスト'},'owner'),predicate=lambda v:len(v['items'])==1 and v['items'][0]['pet_id']==pets[0])
 check('block-managed-publisher',c.rpc('block_pet',{'p_pet':pets[0],'p_enabled':True},'owner'))
 check('managed-block-excludes-all-publisher-pets',c.rpc('feed_page',{'p_query':'検証イラスト'},'owner'),predicate=lambda v:not v['items'])
 check('unblock',c.rpc('block_pet',{'p_pet':pets[0],'p_enabled':False},'owner'))
 after=check('metrics-after',c.rpc('seed_metrics',role='operator'),predicate=lambda v:v['real_registered_users']==before['real_registered_users'] and v['ugc_posts']==before['ugc_posts'] and v['managed_posts']==before['managed_posts'] and v['synthetic_posts']>=before['synthetic_posts']+2)
 check('ordinary-user-metrics-denied',c.rpc('seed_metrics',role='owner'),(403,))
 check('edit-invalidates-publication',c.rpc('seed_revise',{'p_job':jobs[0],'p_version':5,'p_photos':[photos[0]],'p_body':'Revised synthetic body'},'operator'))
 check('stale-editor-version-denied',c.rpc('seed_revise',{'p_job':jobs[0],'p_version':5,'p_photos':[photos[0]],'p_body':'Wrong overwrite'},'operator'),(400,))
 check('revision-requires-new-approval',c.rpc('seed_schedule',{'p_job':jobs[0],'p_version':6,'p_when':datetime.now(timezone.utc).isoformat(),'p_explicit':True},'operator'),(400,))
 check('permissions-admin',c.rpc('seed_permissions',role='operator'),predicate=lambda v:all(v.values()))
 check('ordinary-rights-history-denied',c.rpc('seed_rights_history',{'p_pet':pets[0]},'owner'),(403,))
 check('immutable-original-rights-evidence',c.rpc('seed_rights_history',{'p_pet':pets[0]},'operator'),predicate=lambda rows:len(rows)>=1 and rows[0]['rights']['holder']=='MEFRION owned synthetic test')
 batchargs={'p_items':[{'pet_id':pet,'photos':[photos[i]],'body':'Owned batch only','planned_at':(datetime.now(timezone.utc)+timedelta(hours=2)).isoformat()} for i,pet in enumerate(pets)],'p_key':str(uuid4())}
 batch=check('two-pet-bulk-drafts',c.rpc('seed_draft_batch',batchargs,'operator'),predicate=lambda rows:len(rows)==2)
 check('bulk-draft-retry',c.rpc('seed_draft_batch',batchargs,'operator'),predicate=lambda rows:rows==batch)
 check('bulk-key-conflict',c.rpc('seed_draft_batch',{**batchargs,'p_items':batchargs['p_items'][:1]},'operator'),(400,))
 check('past-plan-denied',c.rpc('seed_draft_batch',{'p_key':str(uuid4()),'p_items':[{**batchargs['p_items'][0],'planned_at':(datetime.now(timezone.utc)-timedelta(hours=1)).isoformat()}]},'operator'),(400,))
 check('batch-cross-pet-source-denied',c.rpc('seed_draft_batch',{'p_key':str(uuid4()),'p_items':[{**batchargs['p_items'][0],'photos':[photos[1]]}]},'operator'),(400,))
 check('published-cancel',c.rpc('seed_cancel',{'p_job':jobs[1],'p_version':5,'p_explicit':True},'operator'))
 check('cancel-stale-rejected',c.rpc('seed_cancel',{'p_job':jobs[1],'p_version':5,'p_explicit':True},'operator'),(400,))
 check('cancel-requires-reapproval',c.rpc('seed_now',{'p_job':jobs[1],'p_version':6,'p_explicit':True},'operator'),(400,))
 check('cancelled-old-post-no-feed',c.rpc('feed_page',{'p_query':'検証イラスト'},None),predicate=lambda v:all(r['pet_id']!=pets[1] for r in v['items']))
 check('editor-visible-permissions',grant('editor'))
 check('editor-permissions-correct',c.rpc('seed_permissions',role='operator'),predicate=lambda v:v['edit'] and not v['approve'] and not v['schedule'])
 check('approver-visible-permissions',grant('approver'))
 check('approver-permissions-correct',c.rpc('seed_permissions',role='operator'),predicate=lambda v:v['approve'] and not v['edit'] and not v['schedule'])
 check('restore-synthetic-admin',grant('admin'))
 check('batch-rights-withdraw',c.rpc('seed_stop',{'p_pets':pets,'p_withdraw_rights':True},'operator'),predicate=lambda v:v==2)
 check('rights-withdraw-hidden',c.rpc('feed_page',{'p_query':'検証イラスト'},None),predicate=lambda v:all(r['pet_id'] not in pets for r in v['items']))
 outcome={'passed':True,'scope':'two owned synthetic managed Pets / one technical publisher / one reserved MFA operator / no human grants','checks':checks}
except Exception as e:outcome={'passed':False,'failure':str(e),'checks':checks}
finally:
 if op:
  check('cleanup-synthetic-admin-role',grant('admin'))
  if pets:check('cleanup-managed-visibility',c.rpc('seed_stop',{'p_pets':pets,'p_withdraw_rights':True},'operator'))
  for id in photos:check('cleanup-managed-photo',c.rpc('seed_delete_photo',{'p_photo':id,'p_explicit':True},'operator'))
  subprocess.run([sys.executable,str(ROOT/'scripts/clean_operator_ui_fixture.py')],check=True,capture_output=True)
 (ROOT/'docs/evidence/p1-seed-server.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'passed':outcome['passed'],'checks':len(checks),'failure':outcome.get('failure')}))
if not outcome['passed']:raise SystemExit(1)
