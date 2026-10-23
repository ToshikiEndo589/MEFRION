"""Tagged post permissions/withdrawal on reserved dev accounts and owned JPEG."""
import io,json,subprocess,sys
from uuid import uuid4
from PIL import Image
from p1_test_support import ROOT,DevelopmentClient
c=DevelopmentClient();check=c.check;rpc=c.rpc;photo=None;post=None;tag=None;original=None;fixture=ROOT/'.local/p1-tag-fixture.json'
try:
 c.login();original=next(p for p in rpc('list_pets')[1] if p['id']==c.pet)
 if fixture.exists():
  tag=json.loads(fixture.read_text())['pet'];assert any(p['id']==tag and p['name']=='P1 owned tag fixture' and p['role']=='owner' for p in rpc('list_pets')[1])
 else:
  tag=check('create-reserved-tag-pet',rpc('create_pet',{'p_name':'P1 owned tag fixture','p_species':'dog'}))['id'];fixture.write_text(json.dumps({'pet':tag}));fixture.chmod(0o600)
 foreign=json.loads((ROOT/'.local/p1-twins-shared-fixture.json').read_text())['pet']
 for pet in (c.pet,tag):check('public-profile-explicit',rpc('set_public_profile',{'p_pet':pet,'p_enabled':True,'p_explicit':True}))
 p=check('reserve-owned-photo',rpc('begin_photo',{'p_pet':c.pet,'p_request_key':str(uuid4()),'p_captured':None,'p_title':'Owned tag API illustration'}));photo=p['id']
 data=io.BytesIO();Image.new('RGB',(128,128),(170,130,180)).save(data,'JPEG');check('upload-owned-photo',c.call('/storage/v1/object/family-originals/'+p['path'],role='owner',raw=data.getvalue()),(200,201));check('ready',rpc('finish_photo',{'p_photo':photo}));check('sns-purpose',rpc('consent',{'p_photo':photo,'p_purpose':'sns','p_allowed':True}))
 args={'p_pet':c.pet,'p_photos':[photo],'p_tags':[c.pet,tag],'p_body':'Owned illustration tag test; no real pet or experience.','p_request_key':str(uuid4()),'p_explicit':True}
 for label,tags in [('empty',[]),('duplicates',[c.pet,c.pet]),('missing-primary',[tag]),('too-many',[c.pet]+[str(uuid4()) for _ in range(5)])]:check('reject-'+label,rpc('request_tagged_publication',{**args,'p_tags':tags}),(400,))
 check('reject-foreign-tag',rpc('request_tagged_publication',{**args,'p_tags':[c.pet,foreign]}),(403,))
 check('reject-implicit-publish',rpc('request_tagged_publication',{**args,'p_explicit':False}),(400,))
 check('reject-outsider',rpc('request_tagged_publication',args,'outsider'),(403,))
 check('reject-anonymous',rpc('request_tagged_publication',args,None),(401,403))
 value=check('request-owned-two-tags',rpc('request_tagged_publication',args));post=value['id'];check('same-key-retry',rpc('request_tagged_publication',args),predicate=lambda v:v['id']==post)
 check('same-key-changed-tags-rejected',rpc('request_tagged_publication',{**args,'p_tags':[c.pet]}),(400,))
 result=subprocess.run([sys.executable,str(ROOT/'scripts/process_publication_outbox.py')],check=True,capture_output=True,text=True);assert json.loads(result.stdout)['failed']==0
 page=check('public-tags-projection',rpc('feed_page',{'p_query':original['name']},None),predicate=lambda v:any(row['id']==post and {t['id'] for t in row['tags']}=={c.pet,tag} for row in v['items']))
 row=next(r for r in page['items'] if r['id']==post);media=row['media'][0]
 check('derived-image-before-withdraw',c.call('/functions/v1/public-image?media='+media))
 check('tag-profile-withdraw',rpc('set_public_profile',{'p_pet':tag,'p_enabled':False}))
 check('old-post-hidden',rpc('feed_page',{'p_known_ids':[post]},None),predicate=lambda v:post not in v['valid_known_ids'] and all(r['id']!=post for r in v['items']))
 check('derived-image-immediately-hidden',c.call('/functions/v1/public-image?media='+media),(404,))
 check('re-enable-tag',rpc('set_public_profile',{'p_pet':tag,'p_enabled':True,'p_explicit':True}))
 check('old-post-does-not-revive',rpc('feed_page',{'p_known_ids':[post]},None),predicate=lambda v:post not in v['valid_known_ids'])
 outcome={'passed':True,'checks':c.checks,'scope':'reserved dev accounts, owned illustration only'}
except Exception as e:outcome={'passed':False,'failure':str(e),'checks':c.checks}
finally:
 if post:rpc('stop_publication',{'p_post':post})
 if photo:rpc('delete_photo',{'p_photo':photo})
 if tag:rpc('set_public_profile',{'p_pet':tag,'p_enabled':False})
 if original:rpc('set_public_profile',{'p_pet':c.pet,'p_enabled':False})
 subprocess.run([sys.executable,str(ROOT/'scripts/process_deletion_outbox.py')],capture_output=True)
(ROOT/'docs/evidence/p1-tags-server.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'passed':outcome['passed'],'checks':len(c.checks),'failure':outcome.get('failure')}));raise SystemExit(0 if outcome['passed'] else 1)
