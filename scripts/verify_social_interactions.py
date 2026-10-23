"""Actual Auth/RPC tests, synthetic disposable fixtures in the approved Free project."""
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
checks=[];tokens={};photos=[];profiles=[];blocked=[];recovery_report=None

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
try:
    for identity in identities:
        assert identity['email'].startswith('mefrion-test-') and identity['email'].endswith('@example.invalid')
        login=check('synthetic-login-'+identity['role'],call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']}))
        assert login['user']['user_metadata']['test_only'] is True
        tokens[identity['role']]=login['access_token']
    outsider_pet=next(p['id'] for p in check('reuse-private-outsider-pet',rpc('list_pets',role='outsider')) if p['name']=='E2E安全閲覧Pet' and p['role']=='owner')
    for pet,role in [(primary,'owner'),(outsider_pet,'outsider')]:
        check('enable-test-profile-'+role,rpc('set_public_profile',{'p_pet':pet,'p_enabled':True,'p_explicit':True},role));profiles.append((pet,role))
    for role in tokens:check('explicit-public-nickname-'+role,rpc('set_social_name',{'p_name':'E2E '+role},role))
    stream=io.BytesIO();Image.new('RGB',(320,240),(230,190,160)).save(stream,format='JPEG')
    photo=check('reserve-synthetic-photo',rpc('begin_photo',{'p_pet':primary,'p_request_key':str(uuid4())},'owner'));photos.append(photo['id'])
    check('upload-synthetic-photo',call('/storage/v1/object/family-originals/'+photo['path'],token=tokens['owner'],raw=stream.getvalue()),(200,201))
    check('finish-photo',rpc('finish_photo',{'p_photo':photo['id']},'owner'))
    check('sns-purpose-only',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':True},'owner'))
    post=check('request-explicit-public-post',rpc('request_publication',{'p_pet':primary,'p_photos':[photo['id']],'p_body':'Synthetic SNS only','p_kind':'post','p_request_key':str(uuid4()),'p_explicit':True},'owner'))['id']
    worker=subprocess.run([sys.executable,str(root/'scripts/process_publication_outbox.py')],capture_output=True,text=True,check=True)
    assert json.loads(worker.stdout)['failed']==0
    def row(role='outsider'):return next(r for r in check('read-current-feed',rpc('public_feed',role=role)) if r['id']==post)
    assert row()['likes']==0
    reaction={'p_post':post,'p_kind':'like','p_enabled':True}
    check('anon-like-denied',rpc('react',reaction),(401,403))
    check('like',rpc('react',reaction,'outsider'));check('like-exact-retry',rpc('react',reaction,'outsider'))
    assert row()['likes']==1 and row()['liked']
    check('save',rpc('react',{**reaction,'p_kind':'save'},'outsider'))
    check('private-saved-feed',rpc('saved_feed',role='outsider'),predicate=lambda rows:post in [r['id'] for r in rows])
    check('different-account-cannot-see-saves',rpc('saved_feed',role='family'),predicate=lambda rows:post not in [r['id'] for r in rows])
    check('follow',rpc('follow',{'p_pet':primary,'p_enabled':True},'outsider'))
    check('follow-retry',rpc('follow',{'p_pet':primary,'p_enabled':True},'outsider'))
    check('following-feed',rpc('following_feed',role='outsider'),predicate=lambda rows:post in [r['id'] for r in rows])
    check('self-follow-denied',rpc('follow',{'p_pet':primary,'p_enabled':True},'owner'),(403,))
    check('public-search',rpc('search_feed',{'p_query':'Ｅ２Ｅ合成'}),predicate=lambda rows:post in [r['id'] for r in rows])
    draft={'p_post':post,'p_body':'Synthetic root','p_parent':None,'p_alias_pet':None,'p_request_key':str(uuid4())}
    comment=check('registered-root-comment',rpc('comment',draft,'outsider'))
    check('comment-retry',rpc('comment',draft,'outsider'),predicate=lambda value:value==comment)
    check('comment-conflict',rpc('comment',{**draft,'p_body':'different'},'outsider'),(400,))
    check('cannot-impersonate-owner-pet',rpc('comment',{**draft,'p_alias_pet':primary,'p_request_key':str(uuid4())},'outsider'),(403,))
    alias=check('owned-public-pet-alias',rpc('comment',{**draft,'p_alias_pet':outsider_pet,'p_request_key':str(uuid4())},'outsider'))
    check('own-last-speaker-remembered',rpc('social_identity',role='outsider'),predicate=lambda row:row['last_pet']==outsider_pet and set(row)=={'name','last_pet'})
    reply=check('one-level-reply',rpc('comment',{**draft,'p_parent':comment,'p_body':'Synthetic reply','p_request_key':str(uuid4())},'family'))
    check('second-level-reply-denied',rpc('comment',{**draft,'p_parent':reply,'p_request_key':str(uuid4())},'owner'),(400,))
    check('public-comments-no-human-identifiers',rpc('comments',{'p_post':post}),predicate=lambda rows:len(rows)==3 and all(set(r)=={'id','body','parent','display_name','mine','deleted','created_at'} for r in rows))
    check('owner-safe-notifications',rpc('social_notifications',role='owner'),predicate=lambda rows:any(r['post_id']==post and r['kind']=='like' for r in rows) and all(not any(k in r for k in ('actor_id','recipient_id','email')) for r in rows))
    old_preferences=check('read-own-notification-preferences',rpc('notification_preferences',role='owner'),predicate=lambda data:set(data)=={'like','comment','follow','twins'})
    check('anon-preferences-denied',rpc('notification_preferences'),(401,403))
    check('invalid-preferences-denied',rpc('set_notification_preferences',{'p_settings':{'like':True}},'owner'),(400,))
    check('non-boolean-preferences-denied',rpc('set_notification_preferences',{'p_settings':{'like':'true','comment':True,'follow':True,'twins':False}},'owner'),(400,))
    off={'like':False,'comment':False,'follow':False,'twins':False}
    check('disable-own-social-notifications',rpc('set_notification_preferences',{'p_settings':off},'owner'))
    check('disabled-notifications-hidden',rpc('social_notifications',role='owner'),predicate=lambda rows:rows==[])
    check('restore-own-notification-settings',rpc('set_notification_preferences',{'p_settings':old_preferences},'owner'))
    check('reply-recipient-notification',rpc('social_notifications',role='outsider'),predicate=lambda rows:any(r['kind']=='reply' and r['post_id']==post for r in rows))
    check('unrelated-notifications-empty',rpc('social_notifications',role='family'),predicate=lambda rows:all(r['post_id']!=post for r in rows))
    check('non-author-delete-denied',rpc('delete_comment',{'p_comment':comment},'family'),(403,))
    check('author-delete',rpc('delete_comment',{'p_comment':comment},'outsider'))
    check('deleted-root-placeholder-reply-retained',rpc('comments',{'p_post':post}),predicate=lambda rows:any(r['id']==comment and r['deleted'] and r['body']=='' for r in rows) and any(r['id']==reply for r in rows))
    report={'p_comment':alias,'p_reason':'other','p_note':'Synthetic report only','p_request_key':str(uuid4())}
    report_id=check('comment-report',rpc('report_comment',report,'owner'))
    check('report-retry',rpc('report_comment',report,'owner'),predicate=lambda value:value==report_id)
    check('ordinary-user-cannot-moderate',rpc('review_report',{'p_report':report_id,'p_decision':'hide_comment','p_note':'Internal confidential synthetic','p_request_key':str(uuid4())},'owner'),(403,))
    check('service-hide-comment',rpc('review_report',{'p_report':report_id,'p_decision':'hide_comment','p_note':'Internal confidential synthetic','p_request_key':str(uuid4())},privileged=True))
    check('hidden-comment-body-removed',rpc('comments',{'p_post':post}),predicate=lambda rows:any(r['id']==alias and r['deleted'] and r['body']=='' for r in rows))
    check('target-fixed-notice-no-internal-note',rpc('my_moderation',role='outsider'),predicate=lambda rows:any(r['id']==report_id and r['decision']=='hide_comment' and 'Internal' not in r['note'] for r in rows))
    check('target-comment-appeal',rpc('appeal',{'p_report':report_id,'p_note':'Synthetic appeal'},'outsider'))
    hidden_root=check('suspension-root-comment',rpc('comment',{**draft,'p_body':'Synthetic suspension root','p_request_key':str(uuid4())},'family'))
    hidden_reply=check('suspension-root-reply',rpc('comment',{**draft,'p_parent':hidden_root,'p_body':'Synthetic child','p_request_key':str(uuid4())},'outsider'))
    suspension_report=check('suspension-comment-report',rpc('report_comment',{'p_comment':hidden_root,'p_reason':'other','p_note':'Synthetic suspension','p_request_key':str(uuid4())},'owner'))
    recovery_report=suspension_report
    check('service-suspend-comment-author',rpc('review_report',{'p_report':suspension_report,'p_decision':'suspend_account','p_note':'Synthetic suspension','p_request_key':str(uuid4())},privileged=True))
    check('suspended-comments-and-child-hidden',rpc('comments',{'p_post':post}),predicate=lambda rows:all(r['id'] not in (hidden_root,hidden_reply,reply) for r in rows))
    check('suspended-new-comment-denied',rpc('comment',{**draft,'p_request_key':str(uuid4())},'family'),(403,))
    check('suspended-like-denied',rpc('react',reaction,'family'),(403,))
    check('suspended-unlike-allowed',rpc('react',{**reaction,'p_enabled':False},'family'))
    check('service-restore-comment-author',rpc('review_report',{'p_report':suspension_report,'p_decision':'restore_account','p_note':'Synthetic recovery','p_request_key':str(uuid4())},privileged=True));recovery_report=None
    check('restore-does-not-unhide-comments',rpc('comments',{'p_post':post}),predicate=lambda rows:all(r['id'] not in (hidden_root,hidden_reply,reply) for r in rows))
    privacy_root=check('privacy-public-alias-root',rpc('comment',{**draft,'p_body':'Synthetic private alias','p_alias_pet':outsider_pet,'p_request_key':str(uuid4())},'outsider'))
    privacy_reply=check('privacy-public-alias-reply',rpc('comment',{**draft,'p_body':'Synthetic private child','p_parent':privacy_root,'p_request_key':str(uuid4())},'owner'))
    check('public-speakers-owned-only',rpc('public_speakers',role='outsider'),predicate=lambda rows:any(r['id']==outsider_pet for r in rows) and all(r['id']!=primary and set(r)=={'id','name'} for r in rows))
    check('withdraw-speaker-public-profile',rpc('set_public_profile',{'p_pet':outsider_pet,'p_enabled':False},'outsider'))
    check('private-speaker-not-selectable',rpc('public_speakers',role='outsider'),predicate=lambda rows:all(r['id']!=outsider_pet for r in rows))
    check('private-last-speaker-cleared',rpc('social_identity',role='outsider'),predicate=lambda row:row['last_pet'] is None)
    check('private-alias-and-reply-hidden',rpc('comments',{'p_post':post}),predicate=lambda rows:all(r['id'] not in (privacy_root,privacy_reply,alias) for r in rows))
    check('private-alias-report-denied',rpc('report_comment',{'p_comment':privacy_reply,'p_reason':'other','p_note':'Synthetic hidden attempt','p_request_key':str(uuid4())},'family'),(403,))
    check('private-alias-reply-denied',rpc('comment',{**draft,'p_parent':privacy_root,'p_request_key':str(uuid4())},'family'),(400,))
    check('private-alias-notification-hidden',rpc('social_notifications',role='owner'),predicate=lambda rows:all(r['name']!='E2E安全閲覧Pet' for r in rows))
    check('explicitly-reenable-speaker',rpc('set_public_profile',{'p_pet':outsider_pet,'p_enabled':True,'p_explicit':True},'outsider'))
    check('reenable-does-not-republish-alias',rpc('comments',{'p_post':post}),predicate=lambda rows:all(r['id'] not in (privacy_root,privacy_reply,alias) for r in rows))
    check('block-owner',rpc('block_pet',{'p_pet':primary,'p_enabled':True},'outsider'));blocked.append(primary)
    check('blocked-comments-hidden',rpc('comments',{'p_post':post},'outsider'),predicate=lambda rows:rows==[])
    check('blocked-reaction-denied',rpc('react',reaction,'outsider'),(403,))
    check('blocked-saved-hidden',rpc('saved_feed',role='outsider'),predicate=lambda rows:post not in [r['id'] for r in rows])
    check('blocked-notifications-cleared',rpc('social_notifications',role='owner'),predicate=lambda rows:all(r['post_id']!=post or r['name']!='E2E outsider' for r in rows))
    check('unblock',rpc('block_pet',{'p_pet':primary,'p_enabled':False},'outsider'));blocked=[]
    check('follow-not-restored',rpc('following_feed',role='outsider'),predicate=lambda rows:post not in [r['id'] for r in rows])
    check('withdraw-public-purpose',rpc('consent',{'p_photo':photo['id'],'p_purpose':'sns','p_allowed':False},'owner'))
    check('withdrawn-comments-hidden',rpc('comments',{'p_post':post}),predicate=lambda rows:rows==[])
    check('withdrawn-saved-hidden',rpc('saved_feed',role='outsider'),predicate=lambda rows:post not in [r['id'] for r in rows])
    check('withdrawn-notifications-hidden',rpc('social_notifications',role='owner'),predicate=lambda rows:all(r['post_id']!=post for r in rows))
    check('withdrawn-new-comment-denied',rpc('comment',{**draft,'p_request_key':str(uuid4())},'outsider'),(403,))
    check('unlike-stopped-post-allowed',rpc('react',{**reaction,'p_enabled':False},'outsider'))
    check('unsave-stopped-post-allowed',rpc('react',{**reaction,'p_kind':'save','p_enabled':False},'outsider'))
    outcome={'passed':True,'scope':'Actual Auth/RPC social interactions and privacy; synthetic data only','checks':checks}
except Exception as error:outcome={'passed':False,'failure':str(error),'checks':checks}
finally:
    if recovery_report:
        check('cleanup-synthetic-suspension',rpc('review_report',{'p_report':recovery_report,'p_decision':'restore_account','p_note':'Synthetic cleanup','p_request_key':str(uuid4())},privileged=True))
    for pet in blocked:check('cleanup-block',rpc('block_pet',{'p_pet':pet,'p_enabled':False},'outsider'))
    for pet,role in profiles:check('return-test-profile-private',rpc('set_public_profile',{'p_pet':pet,'p_enabled':False},role))
    for photo_id in photos:check('remove-test-original',rpc('delete_photo',{'p_photo':photo_id},'owner'))
    (root/'docs/evidence/supabase-social-interactions-e2e.json').write_text(json.dumps(outcome,indent=2))
    print(json.dumps({'passed':outcome['passed'],'checks':len(checks),'failure':outcome.get('failure')}))
if not outcome['passed']:raise SystemExit(1)
