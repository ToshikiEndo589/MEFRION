"""Create a dedicated synthetic target; never suspend an ordinary account."""
import io,json,secrets,subprocess,sys,urllib.request
from uuid import uuid4
from PIL import Image
from p1_test_support import DevelopmentClient,ROOT
c=DevelopmentClient();c.login();path=ROOT/'.local/p01-moderation-case.json';assert not path.exists()
service=json.loads((ROOT/'.local/supabase-server.json').read_text());assert service['url']==c.config['url']
identity={'email':'mefrion-test-moderation-case-'+uuid4().hex+'@example.invalid','password':secrets.token_urlsafe(32)}
request=urllib.request.Request(service['url']+'/auth/v1/admin/users',data=json.dumps({**identity,'email_confirm':True,'user_metadata':{'test_only':True}}).encode(),headers={'apikey':service['secret_key'],'Authorization':'Bearer '+service['secret_key'],'Content-Type':'application/json'})
with urllib.request.urlopen(request,timeout=30) as response:identity['id']=json.load(response)['id']
case={'target':identity,'pet':c.pet,'note':'P01 browser moderation '+uuid4().hex};path.write_text(json.dumps(case));path.chmod(0o600)
c.tokens['target']=c.check('target-reserved-login',c.call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']}))['access_token']
user=c.check('target-test-only',c.call('/auth/v1/user',role='target'));assert user['id']==identity['id'] and user['user_metadata']['test_only']
c.check('target-public-alias',c.rpc('set_social_name',{'p_name':'検証コメント担当'},'target'))
p=c.check('reserve-owned-moderation-photo',c.rpc('begin_photo',{'p_pet':c.pet,'p_request_key':str(uuid4()),'p_title':'P01 owned moderation only'}));case['photo']=p['id'];path.write_text(json.dumps(case))
image=io.BytesIO();Image.new('RGB',(256,256),(230,180,160)).save(image,'JPEG');c.check('upload',c.call('/storage/v1/object/family-originals/'+p['path'],raw=image.getvalue(),role='owner'),(200,201));c.check('finish',c.rpc('finish_photo',{'p_photo':p['id']}));c.check('sns-explicit',c.rpc('consent',{'p_photo':p['id'],'p_purpose':'sns','p_allowed':True}));c.check('profile-explicit',c.rpc('set_public_profile',{'p_pet':c.pet,'p_enabled':True,'p_explicit':True}))
post=c.check('owned-public-post',c.rpc('request_publication',{'p_pet':c.pet,'p_photos':[p['id']],'p_body':'P01 owned moderation source','p_kind':'post','p_request_key':str(uuid4()),'p_explicit':True}))['id'];case['post']=post;path.write_text(json.dumps(case))
subprocess.run([sys.executable,str(ROOT/'scripts/process_publication_outbox.py')],check=True,capture_output=True)
comment=c.check('dedicated-comment',c.rpc('comment',{'p_post':post,'p_body':'P01 synthetic comment for moderation','p_parent':None,'p_alias_pet':None,'p_request_key':str(uuid4())},'target'));case['comment']=comment
case['report']=c.check('report-actual-comment',c.rpc('report_comment',{'p_comment':comment,'p_reason':'other','p_note':case['note'],'p_request_key':str(uuid4())}));path.write_text(json.dumps(case));path.chmod(0o600)
print('Dedicated test-only report staged; no personal credentials printed.')
