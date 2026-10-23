"""Actual concurrent RPCs, reserved dev identities and private synthetic Pet only."""
import io,json,threading
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4
from PIL import Image
from p1_test_support import ROOT,DevelopmentClient
c=DevelopmentClient();photos=[];pet=None;winner=None
try:
 c.login();pet=c.check('private-race-pet',c.rpc('create_pet',{'p_name':'P01 owned concurrency only','p_species':'dog'}))['id']
 invite=c.check('single-use-invite',c.rpc('invite',{'p_pet':pet}));barrier=threading.Barrier(2)
 def accept(role):barrier.wait();return role,c.rpc('accept_invite',{'p_token':invite['token'],'p_confirm_scope':True},role)
 with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(accept,['family','outsider']))
 successful=[role for role,(status,data) in results if status==200];assert len(successful)==1 and sorted(status for role,(status,data) in results)==[200,400];winner=successful[0]
 c.check('single-invite-one-committed-member',(200,True));members=c.check('only-owner-and-one-family',c.rpc('members',{'p_pet':pet}),predicate=lambda v:len(v)==2)
 p=c.check('owner-photo',c.rpc('begin_photo',{'p_pet':pet,'p_request_key':str(uuid4()),'p_title':'Owned concurrency illustration'}));photos.append(p['id']);data=io.BytesIO();Image.new('RGB',(256,256),(170,140,120)).save(data,'JPEG');c.check('upload',c.call('/storage/v1/object/family-originals/'+p['path'],raw=data.getvalue(),role='owner'),(200,201));c.check('finish',c.rpc('finish_photo',{'p_photo':p['id']}));c.check('winner-private-read-before-exit',c.rpc('photo',{'p_photo':p['id']},winner))
 actor=next(v['id'] for v in c.people if v['role']==winner);barrier=threading.Barrier(2)
 def add():barrier.wait();return c.rpc('begin_photo',{'p_pet':pet,'p_request_key':str(uuid4()),'p_title':'Owned concurrent pending only'},winner)
 def remove():barrier.wait();return c.rpc('remove_member',{'p_pet':pet,'p_user':actor})
 with ThreadPoolExecutor(max_workers=2) as pool:
  future_add=pool.submit(add);future_remove=pool.submit(remove);added=future_add.result();removed=future_remove.result()
 c.check('concurrent-exit-committed',removed);c.check('concurrent-add-authorized-before-exit-or-rejected',added,(200,403))
 if added[0]==200:
  photos.append(added[1]['id']);c.check('pending-photo-cannot-finish-after-exit',c.rpc('finish_photo',{'p_photo':added[1]['id']},winner),(403,))
 c.check('post-commit-old-member-album-denied',c.rpc('album',{'p_pet':pet},winner),(403,));c.check('post-commit-old-member-photo-denied',c.rpc('photo',{'p_photo':p['id']},winner),(403,));c.check('post-commit-old-member-image-denied',c.call('/functions/v1/private-image?photo='+p['id'],role=winner),(404,))
 c.check('anonymous-private-image-denied',c.call('/functions/v1/private-image?photo='+p['id']),(401,));c.check('expired-member-cannot-consent-owner-photo',c.rpc('consent',{'p_photo':p['id'],'p_purpose':'sns','p_allowed':True},winner),(403,))
 outcome={'passed':True,'scope':'actual two concurrent single-use joins and membership removal/write race','checks':c.checks}
except Exception as e:outcome={'passed':False,'failure':str(e),'checks':c.checks}
finally:
 for id in photos:c.check('cleanup-owned-photo',c.rpc('delete_photo',{'p_photo':id}))
 if pet:c.check('keep-race-pet-private',c.rpc('set_public_profile',{'p_pet':pet,'p_enabled':False}))
 (ROOT/'docs/evidence/p01-family-concurrency.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2));print(json.dumps({'passed':outcome['passed'],'checks':len(c.checks),'failure':outcome.get('failure')}))
if not outcome['passed']:raise SystemExit(1)
