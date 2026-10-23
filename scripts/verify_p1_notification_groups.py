"""Real dev reactions, settings, aggregation and consent invalidation."""
import io,json,subprocess,sys
from uuid import uuid4
from PIL import Image
from p1_test_support import ROOT,DevelopmentClient
c=DevelopmentClient();rpc=c.rpc;check=c.check;photo=None;post=None;preferences=None
try:
 c.login();preferences=check('original-notification-preferences',rpc('notification_preferences'))
 check('explicit-profile',rpc('set_public_profile',{'p_pet':c.pet,'p_enabled':True,'p_explicit':True}))
 p=check('reserve-owned-notification-photo',rpc('begin_photo',{'p_pet':c.pet,'p_request_key':str(uuid4()),'p_captured':None,'p_title':'Owned notification groups illustration'}));photo=p['id']
 stream=io.BytesIO();Image.new('RGB',(128,128),(170,180,140)).save(stream,'JPEG');check('upload-owned-photo',c.call('/storage/v1/object/family-originals/'+p['path'],role='owner',raw=stream.getvalue()),(200,201));check('ready',rpc('finish_photo',{'p_photo':photo}));check('sns-purpose',rpc('consent',{'p_photo':photo,'p_purpose':'sns','p_allowed':True}))
 post=check('request-test-publication',rpc('request_publication',{'p_pet':c.pet,'p_photos':[photo],'p_body':'Owned illustration notification test; no real pet or experience.','p_kind':'post','p_request_key':str(uuid4()),'p_explicit':True}))['id']
 out=subprocess.run([sys.executable,str(ROOT/'scripts/process_publication_outbox.py')],capture_output=True,text=True,check=True);assert json.loads(out.stdout)['failed']==0
 check('off',rpc('set_notification_preferences',{'p_settings':dict.fromkeys(['like','comment','follow','twins'],False)}))
 reaction={'p_post':post,'p_kind':'like','p_enabled':True}
 check('real-family-reaction-while-disabled',rpc('react',reaction,'family'))
 check('disabled-groups-not-visible',rpc('social_notification_groups'),predicate=lambda rows:all(v['post_id']!=post for v in rows))
 check('on',rpc('set_notification_preferences',{'p_settings':dict.fromkeys(['like','comment','follow','twins'],True)}))
 check('remove-test-reaction',rpc('react',{**reaction,'p_enabled':False},'family'));check('new-real-family-reaction',rpc('react',reaction,'family'));check('new-real-outsider-reaction',rpc('react',reaction,'outsider'))
 check('two-real-reactions-one-group',rpc('social_notification_groups'),predicate=lambda rows:any(v['post_id']==post and v['kind']=='like' and v['count']==2 for v in rows) and all('actor_id' not in v and 'recipient_id' not in v and 'email' not in v for v in rows))
 check('anonymous-groups-denied',rpc('social_notification_groups',role=None),(401,403))
 check('different-user-does-not-read-recipient-group',rpc('social_notification_groups',role='family'),predicate=lambda rows:all(v['post_id']!=post for v in rows))
 check('withdraw-source',rpc('consent',{'p_photo':photo,'p_purpose':'sns','p_allowed':False}))
 check('withdrawn-groups-masked-immediately',rpc('social_notification_groups'),predicate=lambda rows:all(v['post_id']!=post for v in rows))
 outcome={'passed':True,'checks':c.checks,'push_sent':False}
except Exception as e:outcome={'passed':False,'failure':str(e),'checks':c.checks}
finally:
 if preferences:rpc('set_notification_preferences',{'p_settings':preferences})
 if post:rpc('stop_publication',{'p_post':post})
 if photo:rpc('delete_photo',{'p_photo':photo})
 rpc('set_public_profile',{'p_pet':c.pet,'p_enabled':False});subprocess.run([sys.executable,str(ROOT/'scripts/process_deletion_outbox.py')],capture_output=True)
(ROOT/'docs/evidence/p1-notification-groups-server.json').write_text(json.dumps(outcome,indent=2)+'\n');print(json.dumps({'passed':outcome['passed'],'checks':len(c.checks),'failure':outcome.get('failure')}));raise SystemExit(0 if outcome['passed'] else 1)
