"""Actual dev family cards, export consent, new activity and keyset pagination."""
import io,json,subprocess,sys
from uuid import uuid4
from PIL import Image
from p1_test_support import DevelopmentClient,ROOT
c=DevelopmentClient();check=c.check;rpc=c.rpc;photos=[];posts=[];cards=[];joined=False;original=None
try:
 c.login();pet=c.pet
 original=next(v for v in rpc('list_pets')[1] if v['id']==pet)
 family_id=next(p['id'] for p in c.people if p['role']=='family')
 members=check('members',rpc('members',{'p_pet':pet}))
 if not any(v['id']==family_id for v in members):
  invitation=check('invite',rpc('invite',{'p_pet':pet}));check('explicit-family-join',rpc('accept_invite',{'p_token':invitation['token'],'p_confirm_scope':True},'family'));joined=True
 check('mark-family-read',rpc('mark_family_read',{'p_pet':pet},'family'))
 for i in range(3):
  p=check('reserve',rpc('begin_photo',{'p_pet':pet,'p_request_key':str(uuid4()),'p_captured':'2020' if i==0 else '2020-10-09','p_title':'Synthetic card/paging only'}));photos.append(p['id'])
  out=io.BytesIO();Image.new('RGB',(128,128),(200,150+i*20,130)).save(out,'JPEG')
  check('upload',c.call('/storage/v1/object/family-originals/'+p['path'],role='owner',raw=out.getvalue()),(200,201));check('finish',rpc('finish_photo',{'p_photo':p['id']}))
 check('family-new-three',rpc('family_new',{'p_pet':pet},'family'),predicate=lambda v:v>=3)
 check('family-mark-read',rpc('mark_family_read',{'p_pet':pet},'family'))
 check('family-new-zero',rpc('family_new',{'p_pet':pet},'family'),predicate=lambda v:v==0)
 check('outsider-new-denied',rpc('family_new',{'p_pet':pet},'outsider'),(403,))
 check('family-activity-no-identities-or-originals',rpc('family_activity',{'p_pet':pet},'family'),predicate=lambda rows:any(v['action']=='photo.finish' for v in rows) and all(set(v)=={'id','action','mine','created_at','actor_name'} for v in rows))
 layout={'text':'Synthetic private comparison','first_zoom':1.2,'first_x':0.3,'first_y':0.5,'second_zoom':1,'second_x':0.5,'second_y':0.5}
 args={'p_pet':pet,'p_first':photos[0],'p_second':photos[1],'p_layout':layout,'p_key':str(uuid4())}
 card=check('save-family-card',rpc('save_card',args));cards.append(card)
 check('card-idempotency',rpc('save_card',args),predicate=lambda v:v==card)
 check('card-key-conflict',rpc('save_card',{**args,'p_layout':{**layout,'text':'changed'}}),(400,))
 check('card-invalid-crop-denied',rpc('save_card',{**args,'p_key':str(uuid4()),'p_layout':{'first_zoom':0.5}}),(400,))
 check('card-cross-pet-denied',rpc('save_card',{**args,'p_key':str(uuid4()),'p_second':str(uuid4())}),(400,))
 check('family-card-visible',rpc('cards',{'p_pet':pet},'family'),predicate=lambda v:any(row['id']==card and row['layout']==layout for row in v))
 check('outsider-card-denied',rpc('cards',{'p_pet':pet},'outsider'),(403,))
 check('anonymous-card-denied',rpc('cards',{'p_pet':pet},None),(401,403))
 check('no-implicit-export',rpc('authorize_card_export',{'p_card':card,'p_explicit':False}),(400,))
 check('no-export-without-provider-purpose',rpc('authorize_card_export',{'p_card':card,'p_explicit':True}),(403,))
 for id in photos[:2]:check('provide-export-consent',rpc('consent',{'p_photo':id,'p_purpose':'external_share','p_allowed':True}))
 check('explicit-authorized-export',rpc('authorize_card_export',{'p_card':card,'p_explicit':True}),predicate=lambda v:v is True)
 check('family-cannot-export-owner-card',rpc('authorize_card_export',{'p_card':card,'p_explicit':True},'family'),(403,))
 check('withdraw-export-consent',rpc('consent',{'p_photo':photos[0],'p_purpose':'external_share','p_allowed':False}))
 check('withdrawn-export-rejected',rpc('authorize_card_export',{'p_card':card,'p_explicit':True}),(403,))
 check('private-card-retained-after-public-withdrawal',rpc('cards',{'p_pet':pet}),predicate=lambda rows:any(v['id']==card for v in rows))
 check('public-profile-explicit',rpc('set_public_profile',{'p_pet':pet,'p_enabled':True,'p_explicit':True}))
 for id in photos:
  check('provide-sns',rpc('consent',{'p_photo':id,'p_purpose':'sns','p_allowed':True}))
  post=check('request-post',rpc('request_publication',{'p_pet':pet,'p_photos':[id],'p_body':'Synthetic P1 page','p_kind':'post','p_request_key':str(uuid4()),'p_explicit':True}));posts.append(post['id'])
 result=subprocess.run([sys.executable,str(ROOT/'scripts/process_publication_outbox.py')],capture_output=True,text=True,check=True);assert json.loads(result.stdout)['failed']==0
 pageargs={'p_mode':'all','p_query':original['name'],'p_species':'all','p_limit':1}
 page=check('first-keyset-page',rpc('feed_page',pageargs,None),predicate=lambda v:len(v['items'])==1 and v['next_id'] is not None)
 seen=[page['items'][0]['id']]
 for i in range(2):
  page=check('next-keyset-page',rpc('feed_page',{**pageargs,'p_before':page['next_date'],'p_before_id':page['next_id'],'p_known_ids':seen},None),predicate=lambda v:len(v['items'])==1 and v['items'][0]['id'] not in seen and set(v['valid_known_ids'])==set(seen));seen.append(page['items'][0]['id'])
 check('pages-find-all-three', (200,seen),predicate=lambda v:set(posts).issubset(v))
 check('cat-filter-excludes-dogs',rpc('feed_page',{**pageargs,'p_species':'cat'},None),predicate=lambda v:not v['items'])
 check('reset-reserved-fixture-follow',rpc('follow',{'p_pet':pet,'p_enabled':False},'outsider'))
 check('unfollowed-feed-excludes-seeds',rpc('feed_page',{'p_mode':'following','p_query':original['name']},'outsider'),predicate=lambda v:not v['items'])
 check('anonymous-following-denied',rpc('feed_page',{'p_mode':'following'},None),(401,403))
 check('invalid-cursor-pair-denied',rpc('feed_page',{'p_before_id':str(uuid4())},None),(400,))
 private={ 'p_pet':pet,'p_name':original['name'],'p_breed':'Hidden private breed marker','p_introduction':original['introduction'],'p_details':original.get('details',{}),'p_public_fields':[]}
 check('hide-breed',rpc('update_pet',private))
 check('search-does-not-match-private-breed',rpc('feed_page',{'p_query':'Hidden private breed marker'},None),predicate=lambda v:not v['items'])
 check('feed-does-not-return-private-breed',rpc('feed_page',{'p_query':original['name']},None),predicate=lambda v:all(r['breed']=='' for r in v['items']))
 check('stop-one-public-post',rpc('stop_publication',{'p_post':posts[0]}))
 check('known-page-rechecks-withdrawal',rpc('feed_page',{'p_known_ids':posts},None),predicate=lambda v:posts[0] not in v['valid_known_ids'])
 check('delete-card-source',rpc('delete_photo',{'p_photo':photos[0]}));photos.remove(photos[0])
 check('source-deletion-removes-card',rpc('cards',{'p_pet':pet}),predicate=lambda v:all(r['id']!=card for r in v));cards.remove(card)
 outcome={'passed':True,'scope':'synthetic family cards/export purposes/new activity/public keyset pages','checks':c.checks}
except Exception as e:outcome={'passed':False,'failure':str(e),'checks':c.checks}
finally:
 for id in cards:check('cleanup-card',rpc('delete_card',{'p_card':id}))
 for id in photos:check('cleanup-photo',rpc('delete_photo',{'p_photo':id}))
 if original:
  check('restore-profile',rpc('update_pet',{'p_pet':c.pet,'p_name':original['name'],'p_breed':original['breed'],'p_introduction':original['introduction'],'p_details':original.get('details',{}),'p_public_fields':original.get('public_fields',[])}));check('keep-private',rpc('set_public_profile',{'p_pet':c.pet,'p_enabled':False}))
 if joined:check('cleanup-family-membership',rpc('remove_member',{'p_pet':c.pet,'p_user':family_id}))
 (ROOT/'docs/evidence/p1-cards-paging-server.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'passed':outcome['passed'],'checks':len(c.checks),'failure':outcome.get('failure')}))
if not outcome['passed']:raise SystemExit(1)
