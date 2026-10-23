"""Real approved dev RPCs. Only existing reserved users and owned synthetic JPEGs."""
import io,json,subprocess,sys
from uuid import uuid4
from PIL import Image
from p1_test_support import ROOT,DevelopmentClient
c=DevelopmentClient();check=c.check;rpc=c.rpc;photos=[];card=None;shared=None;candidate=None
try:
 c.login();pet=c.pet
 check('public-profile-explicit',rpc('set_public_profile',{'p_pet':pet,'p_enabled':True,'p_explicit':True}))
 for i in range(2):
  p=check('reserve-owned-photo',rpc('begin_photo',{'p_pet':pet,'p_request_key':str(uuid4()),'p_captured':None,'p_title':'Synthetic Twins/shared tests'}));photos.append(p['id']);out=io.BytesIO();Image.new('RGB',(256,256),(160+i*40,140,150)).save(out,'JPEG')
  check('upload-owned-jpeg',c.call('/storage/v1/object/family-originals/'+p['path'],role='owner',raw=out.getvalue()),(200,201));check('finish-private',rpc('finish_photo',{'p_photo':p['id']}))
 enroll={'p_pet':pet,'p_photo':photos[0],'p_key':str(uuid4()),'p_explicit':True}
 check('twins-without-provider-purpose-denied',rpc('twins_enroll',enroll),(403,))
 check('provider-twins-consent',rpc('consent',{'p_photo':photos[0],'p_purpose':'twins','p_allowed':True}))
 check('implicit-enrollment-denied',rpc('twins_enroll',{**enroll,'p_explicit':False}),(400,))
 check('outsider-enrollment-denied',rpc('twins_enroll',enroll,'outsider'),(403,))
 registered=check('explicit-enroll',rpc('twins_enroll',enroll));candidate=registered['id'];check('enroll-idempotency',rpc('twins_enroll',enroll),predicate=lambda v:v==registered)
 subprocess.run([sys.executable,str(ROOT/'scripts/process_twins_outbox.py')],check=True,capture_output=True)
 check('public-candidate-projection-no-originals',rpc('twins_candidates',{'p_species':'dog'},None),predicate=lambda rows:any(v['id']==candidate for v in rows) and all(set(v)=={'id','pet_id','name','species','breed','demo_only'} for v in rows))
 check('self-owner-excluded',rpc('twins_candidates',{'p_species':'dog'}),predicate=lambda rows:all(v['id']!=candidate for v in rows))
 check('other-species-excluded',rpc('twins_candidates',{'p_species':'cat'},None),predicate=lambda rows:all(v['id']!=candidate for v in rows))
 check('candidate-gateway-derivative',c.call('/functions/v1/public-image?media='+candidate),predicate=lambda b:b.startswith(b'\xff\xd8'))
 args={'p_key':str(uuid4()),'p_hash':'a'*64,'p_species':'dog'}
 search=check('registered-search',rpc('twins_begin',args,'outsider'))
 check('same-search-retry-does-not-spend-more',rpc('twins_begin',args,'outsider'),predicate=lambda v:v['id']==search['id'])
 check('retry-key-input-conflict',rpc('twins_begin',{**args,'p_hash':'b'*64},'outsider'),(400,))
 check('anonymous-no-identity-search-denied',rpc('twins_begin',args,None),(401,403))
 result={'p_search':search['id'],'p_state':'results','p_candidates':[candidate]}
 check('record-real-candidate',rpc('twins_finish',result,'outsider'));check('finish-idempotency',rpc('twins_finish',result,'outsider'))
 check('foreign-history-write-denied',rpc('twins_finish',result),(403,))
 check('own-history-projected',rpc('twins_history',role='outsider'),predicate=lambda rows:any(v['id']==search['id'] and len(v['candidates'])==1 for v in rows))
 check('owner-cannot-see-outsider-history',rpc('twins_history'),predicate=lambda rows:all(v['id']!=search['id'] for v in rows))
 check('block-masks-candidate',rpc('block_pet',{'p_pet':pet,'p_enabled':True},'outsider'))
 check('blocked-candidate-omitted',rpc('twins_candidates',{'p_species':'dog'},'outsider'),predicate=lambda rows:all(v['id']!=candidate for v in rows))
 check('blocked-history-masked',rpc('twins_history',role='outsider'),predicate=lambda rows:all(not v['candidates'] for v in rows if v['id']==search['id']))
 check('unblock',rpc('block_pet',{'p_pet':pet,'p_enabled':False},'outsider'))
 check('withdraw-purpose',rpc('consent',{'p_photo':photos[0],'p_purpose':'twins','p_allowed':False}))
 check('withdrawn-candidate-gateway-denied',c.call('/functions/v1/public-image?media='+candidate),(404,))
 check('withdrawn-history-masked',rpc('twins_history',role='outsider'),predicate=lambda rows:all(not v['candidates'] for v in rows if v['id']==search['id']))
 remaining=search.get('remaining',4)
 for i in range(remaining):check('daily-member-slot',rpc('twins_begin',{**args,'p_key':str(uuid4()),'p_hash':format(i+1,'064x')},'outsider'))
 check('member-sixth-search-denied',rpc('twins_begin',{**args,'p_key':str(uuid4())},'outsider'),(400,))
 card=check('save-private-card',rpc('save_card',{'p_pet':pet,'p_first':photos[0],'p_second':photos[1],'p_layout':{'text':'Owned <script> is escaped'},'p_key':str(uuid4())}))
 shareargs={'p_card':card,'p_key':str(uuid4()),'p_explicit':True}
 check('share-without-export-consents-denied',rpc('share_card',shareargs),(403,))
 for id in photos:check('external-consent',rpc('consent',{'p_photo':id,'p_purpose':'external_share','p_allowed':True}))
 check('family-cannot-share-owner-card',rpc('share_card',shareargs,'family'),(403,))
 share=check('explicit-card-share',rpc('share_card',shareargs));shared=share['id'];check('card-share-idempotency',rpc('share_card',shareargs),predicate=lambda v:v==share)
 check('pending-share-not-exposed',rpc('shared_projection',{'p_post':shared},None),predicate=lambda v:v is None)
 subprocess.run([sys.executable,str(ROOT/'scripts/process_publication_outbox.py')],check=True,capture_output=True)
 projection=check('guest-card-projection',rpc('shared_projection',{'p_post':shared},None),predicate=lambda v:set(v)=={'id','name','kind','text','layout','media'} and len(v['media'])==2 and all(set(m)=={'id','captured'} for m in v['media']))
 check('card-does-not-enter-SNS-feed',rpc('feed_page',{'p_mode':'all','p_query':'','p_species':'all','p_limit':50},None),predicate=lambda v:all(p['id']!=shared for p in v['items']))
 from backend import cloud_shares
 status,page=cloud_shares.page(shared);assert status==200 and '&lt;script&gt;' in page and '<script>' not in page and 'family-originals' not in page
 check('block-masks-card',rpc('block_pet',{'p_pet':pet,'p_enabled':True},'outsider'))
 check('blocked-card-projection-hidden',rpc('shared_projection',{'p_post':shared},'outsider'),predicate=lambda v:v is None)
 check('unblock-card',rpc('block_pet',{'p_pet':pet,'p_enabled':False},'outsider'))
 check('delete-source-card',rpc('delete_card',{'p_card':card}));card=None
 check('deleted-card-share-ended',rpc('shared_projection',{'p_post':shared},None),predicate=lambda v:v is None)
 assert cloud_shares.page(shared)[0]==404
 outcome={'passed':True,'scope':'owned synthetic Twins lifecycle/card projections/quota; real RPCs','checks':c.checks,'guest_identity_quota':False,'real_pet_quality_approved':False}
except Exception as e:outcome={'passed':False,'failure':str(e),'checks':c.checks}
finally:
 if card:rpc('delete_card',{'p_card':card})
 if shared:rpc('stop_publication',{'p_post':shared})
 if candidate:rpc('twins_withdraw',{'p_pet':c.pet})
 for id in photos:rpc('delete_photo',{'p_photo':id})
 rpc('set_public_profile',{'p_pet':c.pet,'p_enabled':False});rpc('block_pet',{'p_pet':c.pet,'p_enabled':False},'outsider')
 subprocess.run([sys.executable,str(ROOT/'scripts/process_deletion_outbox.py')],capture_output=True)
(ROOT/'docs/evidence/p1-twins-shares-server.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2));print(json.dumps({'passed':outcome['passed'],'checks':len(c.checks),'failure':outcome.get('failure')}));raise SystemExit(0 if outcome['passed'] else 1)
