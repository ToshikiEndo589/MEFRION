"""Bounded dev test: reserved accounts, owned illustrations, no human content."""
import io,json,subprocess,sys
from uuid import uuid4
from PIL import Image
from p1_test_support import ROOT,DevelopmentClient
c=DevelopmentClient();check=c.check;rpc=c.rpc;photos=[];candidate=None;share=None
fixture=ROOT/'.local/p1-twins-shared-fixture.json'
try:
 c.login();owner_pet=c.pet
 family_pets=check('family-pets',rpc('list_pets',role='family'))
 if fixture.exists():
  saved=json.loads(fixture.read_text());family_pet=saved['pet'];assert any(v['id']==family_pet and v['name']=='P1 Twins owned illustration' and v['role']=='owner' for v in family_pets)
 else:
  family_pet=check('reserved-family-owned-pet',rpc('create_pet',{'p_name':'P1 Twins owned illustration','p_species':'dog'},'family'))['id'];fixture.write_text(json.dumps({'pet':family_pet}));fixture.chmod(0o600)
 for role,pet,color in [('owner',owner_pet,(200,160,130)),('family',family_pet,(120,170,180))]:
  check('explicit-public-profile-'+role,rpc('set_public_profile',{'p_pet':pet,'p_enabled':True,'p_explicit':True},role))
  photo=check('reserve-'+role,rpc('begin_photo',{'p_pet':pet,'p_request_key':str(uuid4()),'p_captured':None,'p_title':'Owned illustration shared lifecycle'},role));photos.append((role,photo['id']))
  data=io.BytesIO();Image.new('RGB',(256,256),color).save(data,'JPEG');check('upload-'+role,c.call('/storage/v1/object/family-originals/'+photo['path'],role=role,raw=data.getvalue()),(200,201));check('finish-'+role,rpc('finish_photo',{'p_photo':photo['id']},role))
 query=photos[0][1];other=photos[1][1]
 check('candidate-twins-consent',rpc('consent',{'p_photo':other,'p_purpose':'twins','p_allowed':True},'family'))
 candidate=check('candidate-enrol',rpc('twins_enroll',{'p_pet':family_pet,'p_photo':other,'p_key':str(uuid4()),'p_explicit':True},'family'))['id']
 subprocess.run([sys.executable,str(ROOT/'scripts/process_twins_outbox.py')],check=True,capture_output=True)
 search=check('member-search',rpc('twins_begin',{'p_key':str(uuid4()),'p_hash':'c'*64,'p_species':'dog'}))['id']
 check('candidate-result',rpc('twins_finish',{'p_search':search,'p_state':'results','p_candidates':[candidate]}))
 check('demo-only-labelled',rpc('twins_candidates',{'p_species':'dog'}),predicate=lambda rows:any(v['id']==candidate and v['demo_only'] is True for v in rows))
 check('public-pet-current',rpc('public_pet',{'p_pet':family_pet},None),predicate=lambda v:v['name']=='P1 Twins owned illustration' and 'owner_id' not in v)
 check('recent-posts-projection',rpc('pet_recent_posts',{'p_pet':family_pet},None),predicate=lambda v:isinstance(v,list))
 feedback={'p_search':search,'p_candidate':candidate,'p_similar':True}
 check('own-feedback',rpc('twins_feedback',feedback));check('feedback-idempotent',rpc('twins_feedback',feedback));check('feedback-change',rpc('twins_feedback',{**feedback,'p_similar':False}))
 check('foreign-feedback-denied',rpc('twins_feedback',feedback,'outsider'),(403,));check('guest-feedback-denied',rpc('twins_feedback',feedback,None),(401,403))
 args={'p_search':search,'p_query':query,'p_candidate':candidate,'p_key':str(uuid4()),'p_explicit':True}
 cat_pet=next(v['id'] for v in check('owned-cat-fixture-list',rpc('list_pets')) if v['name']=='P0 native withdrawal synthetic only' and v['species']=='cat' and v['role']=='owner')
 check('owned-cat-profile',rpc('set_public_profile',{'p_pet':cat_pet,'p_enabled':True,'p_explicit':True}))
 cat=check('owned-cat-query-reserve',rpc('begin_photo',{'p_pet':cat_pet,'p_request_key':str(uuid4()),'p_captured':None,'p_title':'Owned species-mismatch illustration'}));photos.append(('owner',cat['id']))
 data=io.BytesIO();Image.new('RGB',(256,256),(200,160,150)).save(data,'JPEG');check('owned-cat-query-upload',c.call('/storage/v1/object/family-originals/'+cat['path'],role='owner',raw=data.getvalue()),(200,201));check('owned-cat-query-ready',rpc('finish_photo',{'p_photo':cat['id']}))
 check('cross-species-query-cannot-share-dog-result',rpc('share_twins',{**args,'p_query':cat['id']}),(403,))
 check('both-purposes-required',rpc('share_twins',args),(403,))
 for role,id in photos:check('provider-external-'+role,rpc('consent',{'p_photo':id,'p_purpose':'external_share','p_allowed':True},role))
 check('implicit-share-denied',rpc('share_twins',{**args,'p_explicit':False}),(400,))
 check('foreign-result-denied',rpc('share_twins',args,'outsider'),(403,))
 value=check('share-own-result',rpc('share_twins',args));share=value['id'];check('retry-same-share',rpc('share_twins',args),predicate=lambda v:v==value)
 check('pending-projection-hidden',rpc('shared_projection',{'p_post':share},None),predicate=lambda v:v is None)
 subprocess.run([sys.executable,str(ROOT/'scripts/process_twins_share_outbox.py')],check=True,capture_output=True)
 projected=check('shared-derivative-projection',rpc('shared_projection',{'p_post':share},None),predicate=lambda v:v['kind']=='twins' and len(v['media'])==2 and not any(k in json.dumps(v) for k in ['family-originals','provider_id','object_path','input_hash']))
 media=[v['id'] for v in projected['media']]
 for id in media:check('shared-image',c.call('/functions/v1/public-image?media='+id),predicate=lambda v:v.startswith(b'\xff\xd8'))
 check('other-provider-withdraw',rpc('consent',{'p_photo':other,'p_purpose':'external_share','p_allowed':False},'family'))
 check('other-masked-query-retained',rpc('shared_projection',{'p_post':share},None),predicate=lambda v:len(v['media'])==1 and v['candidate_name'] is None and v['text']=='相手の掲載は終了しました')
 check('other-image-immediate-denial',c.call('/functions/v1/public-image?media='+media[1]),(404,))
 check('query-image-still-allowed',c.call('/functions/v1/public-image?media='+media[0]),predicate=lambda v:v.startswith(b'\xff\xd8'))
 check('external-share-withdrawal-keeps-twins-feedback-purpose-separate',rpc('twins_feedback',feedback))
 check('other-regrant',rpc('consent',{'p_photo':other,'p_purpose':'external_share','p_allowed':True},'family'))
 check('old-share-not-resurrected',rpc('shared_projection',{'p_post':share},None),predicate=lambda v:len(v['media'])==1 and v['candidate_name'] is None)
 check('foreign-stop-denied',rpc('stop_twins_share',{'p_share':share},'family'),(403,))
 check('query-provider-withdraw',rpc('consent',{'p_photo':query,'p_purpose':'external_share','p_allowed':False}))
 check('whole-share-ended',rpc('shared_projection',{'p_post':share},None),predicate=lambda v:v is None)
 check('query-image-ended',c.call('/functions/v1/public-image?media='+media[0]),(404,))
 outcome={'passed':True,'checks':c.checks,'scope':'actual dev RPC/derivative lifecycle; owned synthetic illustrations only'}
except Exception as e:outcome={'passed':False,'failure':str(e),'checks':c.checks}
finally:
 if share:rpc('stop_twins_share',{'p_share':share})
 if candidate:rpc('twins_withdraw',{'p_pet':family_pet},'family')
 for role,id in photos:rpc('delete_photo',{'p_photo':id},role)
 rpc('set_public_profile',{'p_pet':c.pet,'p_enabled':False})
 if 'cat_pet' in locals():rpc('set_public_profile',{'p_pet':cat_pet,'p_enabled':False})
 if 'family_pet' in locals():rpc('set_public_profile',{'p_pet':family_pet,'p_enabled':False},'family')
 subprocess.run([sys.executable,str(ROOT/'scripts/process_deletion_outbox.py')],capture_output=True)
(ROOT/'docs/evidence/p1-twins-shared-lifecycle.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2));print(json.dumps({'passed':outcome['passed'],'checks':len(c.checks),'failure':outcome.get('failure')}));raise SystemExit(0 if outcome['passed'] else 1)
