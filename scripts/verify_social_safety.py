"""Actual account-wide blocks/report intake using disposable synthetic fixtures.

Only the approved development project. No human images or credentials in evidence.
Keeps two empty/private synthetic Pets for repeatability; removes uploaded photos.
"""
import io,json,subprocess,sys,urllib.request,urllib.error
from pathlib import Path
from uuid import uuid4
from PIL import Image
root=Path(__file__).resolve().parent.parent
public=json.loads((root/'.local/supabase-public.json').read_text())
service=json.loads((root/'.local/supabase-server.json').read_text())
assert public['url']==service['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
identities=json.loads((root/'.local/supabase-test-identities.json').read_text())
primary=json.loads((root/'.local/supabase-test-sessions.json').read_text())['pet_id']
checks=[];tokens={};photos=[];profiles=[];blocked=[];family_joined=False;recovery_report=None

def call(path,body=None,token=None,raw=None,privileged=False):
    key=service['secret_key'] if privileged else public['anon_key'];headers={'apikey':key}
    if privileged:headers['Authorization']='Bearer '+key
    elif token:headers['Authorization']='Bearer '+token
    if body is not None:raw=json.dumps(body).encode();headers['Content-Type']='application/json'
    elif raw is not None:headers['Content-Type']='image/jpeg'
    try:
        with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=raw,headers=headers),timeout=40) as response:
            data=response.read();return response.status,json.loads(data) if 'json' in response.headers.get('Content-Type','') else data
    except urllib.error.HTTPError as error:return error.code,{}
def rpc(name,body={},role=None,privileged=False):return call('/rest/v1/rpc/mefrion_'+name,body,tokens.get(role),privileged=privileged)
def check(label,result,statuses=(200,),predicate=lambda data:True):
    status,data=result;ok=status in statuses and predicate(data);checks.append({'check':label,'status':status,'passed':ok})
    if not ok:raise RuntimeError(label+' failed')
    return data

def fixture_pet(role,name):
    pets=check('list-'+role+'-private-pets',rpc('list_pets',role=role))
    found=next((p for p in pets if p['name']==name and p.get('role')=='owner'),None)
    return found['id'] if found else check('create-reusable-'+role+'-private-pet',rpc('create_pet',{'p_name':name,'p_species':'dog'},role))['id']
try:
    for identity in identities:
        assert identity['email'].endswith('@example.invalid') and identity['email'].startswith('mefrion-test-')
        tokens[identity['role']]=check('synthetic-login-'+identity['role'],call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']}))['access_token']
    other=fixture_pet('owner','E2E安全追加Pet');outsider_pet=fixture_pet('outsider','E2E安全閲覧Pet')
    for pet,role in [(primary,'owner'),(other,'owner'),(outsider_pet,'outsider')]:
        check('enable-synthetic-profile-'+role,rpc('set_public_profile',{'p_pet':pet,'p_enabled':True,'p_explicit':True},role));profiles.append((pet,role))
    stream=io.BytesIO();Image.new('RGB',(360,240),(238,190,170)).save(stream,format='JPEG');jpeg=stream.getvalue()
    posts=[]
    for pet in [primary,other]:
        photo=check('reserve-synthetic-photo',rpc('begin_photo',{'p_pet':pet,'p_request_key':str(uuid4())},'owner'));photos.append((photo['id'],pet))
        check('upload-synthetic-photo',call('/storage/v1/object/family-originals/'+photo['path'],token=tokens['owner'],raw=jpeg),(200,201))
        check('finish-synthetic-photo',rpc('finish_photo',{'p_photo':photo['id']},'owner'))
        check('provider-purpose-sns',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':True},'owner'))
        posts.append(check('request-synthetic-public-post',rpc('request_publication',{'p_pet':pet,'p_photos':[photo['id']],'p_body':'Synthetic safety test only','p_kind':'post','p_request_key':str(uuid4()),'p_explicit':True},'owner'))['id'])
    worker=subprocess.run([sys.executable,str(root/'scripts/process_publication_outbox.py')],capture_output=True,text=True,check=True)
    if json.loads(worker.stdout)['failed']:raise RuntimeError('derivative worker failed')
    feed=check('outsider-sees-two-owner-pets',rpc('public_feed',role='outsider'),predicate=lambda rows:all(p in [r['id'] for r in rows] for p in posts))
    media=next(row for row in feed if row['id']==posts[0])['media'][0];image_path='/functions/v1/public-image?media='+media
    check('visible-derived-image',call(image_path,token=tokens['outsider']))
    report={'p_post':posts[0],'p_pet':primary,'p_reason':'other','p_note':'Synthetic automated intake test','p_request_key':str(uuid4())}
    report_id=check('registered-report-intake',rpc('report',report,'outsider'))
    check('report-idempotent-retry',rpc('report',report,'outsider'),predicate=lambda value:value==report_id)
    check('report-key-conflict',rpc('report',{**report,'p_note':'different'},'outsider'),(400,))
    check('anonymous-report-denied',rpc('report',report),(401,403))
    check('ordinary-owner-cannot-read-intake',rpc('report_queue',role='owner'),(403,))
    queue=check('service-intake-safe-projection',rpc('report_queue',privileged=True),predicate=lambda rows:any(row['id']==report_id for row in rows) and all(not any(k in row for k in ('actor_id','target_id','object_path','provider_id')) for row in rows))
    check('anonymous-block-denied',rpc('block_pet',{'p_pet':primary,'p_enabled':True}),(401,403))
    check('self-block-denied',rpc('block_pet',{'p_pet':primary,'p_enabled':True},'owner'),(400,))
    check('outsider-block-owner',rpc('block_pet',{'p_pet':primary,'p_enabled':True},'outsider'));blocked.append((primary,'outsider'))
    check('all-owner-pet-names-hidden',rpc('public_feed',role='outsider'),predicate=lambda rows:all(p not in [r['id'] for r in rows] for p in posts))
    check('blocked-derived-image-denied',call(image_path,token=tokens['outsider']),(404,))
    check('anonymous-public-image-still-public',call(image_path))
    check('block-list-has-no-human-id',rpc('blocked_pets',role='outsider'),predicate=lambda rows:any(row['id']==primary for row in rows) and all(set(row)=={'id','name'} for row in rows))
    check('unblock-owner',rpc('block_pet',{'p_pet':primary,'p_enabled':False},'outsider'));blocked=[]
    check('unblocked-two-pets-visible',rpc('public_feed',role='outsider'),predicate=lambda rows:all(p in [r['id'] for r in rows] for p in posts))
    check('owner-blocks-outsider',rpc('block_pet',{'p_pet':outsider_pet,'p_enabled':True},'owner'));blocked.append((outsider_pet,'owner'))
    check('reciprocal-all-pets-hidden',rpc('public_feed',role='outsider'),predicate=lambda rows:all(p not in [r['id'] for r in rows] for p in posts))
    check('reciprocal-image-denied',call(image_path,token=tokens['outsider']),(404,))
    check('unblock-outsider',rpc('block_pet',{'p_pet':outsider_pet,'p_enabled':False},'owner'));blocked=[]
    invite=check('family-invite',rpc('invite',{'p_pet':primary},'owner'))
    check('family-explicit-join',rpc('accept_invite',{'p_token':invite['token'],'p_confirm_scope':True},'family'));family_joined=True
    check('family-blocks-owner',rpc('block_pet',{'p_pet':primary,'p_enabled':True},'family'));blocked.append((primary,'family'))
    check('social-block-retains-private-family-role',rpc('album',{'p_pet':primary},'family'),predicate=lambda rows:any(row['id']==photos[0][0] for row in rows))
    check('blocked-family-public-feed-hidden',rpc('public_feed',role='family'),predicate=lambda rows:all(p not in [r['id'] for r in rows] for p in posts))
    review={'p_report':report_id,'p_decision':'hide_post','p_note':'Synthetic review / hide only this post','p_request_key':str(uuid4())}
    check('ordinary-owner-cannot-review',rpc('review_report',review,'owner'),(403,))
    check('anonymous-cannot-review',rpc('review_report',review),(401,403))
    action=check('service-hide-post',rpc('review_report',review,privileged=True))
    check('review-idempotency',rpc('review_report',review,privileged=True),predicate=lambda row:row['id']==action['id'])
    check('review-key-conflict',rpc('review_report',{**review,'p_decision':'dismiss'},privileged=True),(400,))
    check('hidden-post-removed-other-pet-retained',rpc('public_feed'),predicate=lambda rows:posts[0] not in [r['id'] for r in rows] and posts[1] in [r['id'] for r in rows])
    check('hidden-image-before-purge-denied',call(image_path),(404,))
    recovery_report=report_id
    check('service-suspend-all-pets',rpc('review_report',{**review,'p_decision':'suspend_account','p_note':'Synthetic account suspension','p_request_key':str(uuid4())},privileged=True))
    check('suspended-all-pets-hidden',rpc('public_feed'),predicate=lambda rows:all(p not in [r['id'] for r in rows] for p in posts))
    check('suspended-other-pet-publication-denied',rpc('set_public_profile',{'p_pet':other,'p_enabled':True,'p_explicit':True},'owner'),(403,))
    check('suspended-new-public-post-denied',rpc('request_publication',{'p_pet':other,'p_photos':[photos[1][0]],'p_body':'Suspension bypass attempt','p_kind':'post','p_request_key':str(uuid4()),'p_explicit':True},'owner'),(400,403))
    check('suspended-private-album-retained',rpc('album',{'p_pet':primary},'owner'),predicate=lambda rows:any(row['id']==photos[0][0] for row in rows))
    check('suspended-provider-can-withdraw',rpc('consent',{'p_photo':photos[0][0],'p_purpose':'sns','p_allowed':False},'owner'))
    check('target-moderation-history-safe',rpc('my_moderation',role='owner'),predicate=lambda rows:any(row['id']==report_id and row['decision']=='suspend_account' and 'Synthetic' not in row['note'] for row in rows) and all(set(row)=={'id','decision','note','created_at'} for row in rows))
    check('reporter-cannot-see-target-actions',rpc('my_moderation',role='outsider'),predicate=lambda rows:report_id not in [r['id'] for r in rows])
    appeal={'p_report':report_id,'p_note':'Synthetic appeal only'}
    appeal_id=check('affected-owner-can-appeal',rpc('appeal',appeal,'owner'))
    check('appeal-idempotency',rpc('appeal',appeal,'owner'),predicate=lambda value:value==appeal_id)
    check('reporter-cannot-appeal-for-owner',rpc('appeal',appeal,'outsider'),(403,))
    check('appeal-edit-conflict',rpc('appeal',{**appeal,'p_note':'Different'},'owner'),(400,))
    check('service-history-appeal-intake',rpc('report_queue',privileged=True),predicate=lambda rows:any(row['id']==report_id and len(row['reviews'])==2 and len(row['appeals'])==1 for row in rows))
    check('service-restores-account',rpc('review_report',{**review,'p_decision':'restore_account','p_note':'Synthetic recovery','p_request_key':str(uuid4())},privileged=True));recovery_report=None
    check('restoration-does-not-republish',rpc('public_feed'),predicate=lambda rows:all(p not in [r['id'] for r in rows] for p in posts))
    check('restored-owner-can-explicitly-enable',rpc('set_public_profile',{'p_pet':other,'p_enabled':True,'p_explicit':True},'owner'))
    check('old-stopped-post-still-hidden-after-reenable',rpc('public_feed'),predicate=lambda rows:posts[1] not in [r['id'] for r in rows])
    outcome={'passed':True,'scope':'actual Auth / synthetic images / blocks / reports / moderation / appeals','checks':checks}
except Exception as error:outcome={'passed':False,'failure':str(error),'checks':checks}
finally:
    if recovery_report:
        check('cleanup-synthetic-suspension',rpc('review_report',{'p_report':recovery_report,'p_decision':'restore_account','p_note':'Synthetic cleanup recovery','p_request_key':str(uuid4())},privileged=True))
    for pet,role in blocked:check('cleanup-synthetic-block',rpc('block_pet',{'p_pet':pet,'p_enabled':False},role))
    if family_joined:
        identity=next(i for i in identities if i['role']=='family')
        check('cleanup-synthetic-family-membership',rpc('remove_member',{'p_pet':primary,'p_user':identity['id']},'owner'))
    for pet,role in profiles:check('return-synthetic-profile-private',rpc('set_public_profile',{'p_pet':pet,'p_enabled':False},role))
    for photo,pet in photos:check('delete-synthetic-original',rpc('delete_photo',{'p_photo':photo},'owner'))
    (root/'docs/evidence/supabase-social-safety-e2e.json').write_text(json.dumps(outcome,indent=2))
    print(json.dumps({'passed':outcome['passed'],'checks':len(checks),'failure':outcome.get('failure')}))
if not outcome['passed']:raise SystemExit(1)
