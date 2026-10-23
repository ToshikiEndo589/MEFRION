"""Notification projection test in the approved dev fixture only; no Push sent."""
import io,json,subprocess,sys
from datetime import datetime,timezone,timedelta
from zoneinfo import ZoneInfo
from uuid import uuid4
from PIL import Image
from p1_test_support import ROOT,DevelopmentClient
c=DevelopmentClient();rpc=c.rpc;check=c.check;photo=None;events=[];original=None;pref=None;joined=False
try:
 c.login();pet=c.pet;original=next(v for v in check('original-pet',rpc('list_pets')) if v['id']==pet)
 family_id=next(v['id'] for v in c.people if v['role']=='family')
 members=check('fixture-members',rpc('members',{'p_pet':pet}))
 if not any(v['id']==family_id for v in members):
  invite=check('reserved-family-invite',rpc('invite',{'p_pet':pet}));check('reserved-family-join',rpc('accept_invite',{'p_token':invite['token'],'p_confirm_scope':True},'family'));joined=True
 pref=check('original-notification-settings',rpc('get_pet_notifications',{'p_pet':pet}))
 check('guest-notifications-denied',rpc('family_notifications',role=None),(401,403))
 check('outsider-family-notifications-private',rpc('family_notifications',role='outsider'),predicate=lambda rows:all(v['pet_id']!=pet for v in rows))
 setting={'p_pet':pet,'p_frequency':'immediate','p_milestones':False,'p_paused_until':None}
 check('immediate-setting',rpc('pet_notifications',setting))
 photo=check('family-private-reserve',rpc('begin_photo',{'p_pet':pet,'p_request_key':str(uuid4()),'p_captured':None,'p_title':'Owned notification illustration'},'family'))
 data=io.BytesIO();Image.new('RGB',(256,256),(160,140,150)).save(data,'JPEG');check('family-upload',c.call('/storage/v1/object/family-originals/'+photo['path'],role='family',raw=data.getvalue()),(200,201));check('family-finish',rpc('finish_photo',{'p_photo':photo['id']},'family'))
 check('immediate-other-provider-photo',rpc('family_notifications'),predicate=lambda rows:any(v['id']==photo['id'] and v['kind']=='family_photo' for v in rows))
 check('pause',rpc('pet_notifications',{**setting,'p_paused_until':(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()}))
 check('paused-photo-omitted',rpc('family_notifications'),predicate=lambda rows:all(v['pet_id']!=pet for v in rows))
 check('off',rpc('pet_notifications',{**setting,'p_frequency':'off'}))
 check('off-omits-photo',rpc('family_notifications'),predicate=lambda rows:all(v['id']!=photo['id'] for v in rows))
 check('daily-setting',rpc('pet_notifications',{**setting,'p_frequency':'batched'}))
 check('same-day-not-premature-digest',rpc('family_notifications'),predicate=lambda rows:all(v['pet_id']!=pet for v in rows))
 today=datetime.now(ZoneInfo('Asia/Tokyo')).strftime('%Y-%m-%d')
 for date in [None,today[:4],today[:7],today]:
  events.append(check('milestone-create',rpc('save_event',{'p_pet':pet,'p_key':str(uuid4()),'p_captured':date,'p_title':'Owned synthetic anniversary','p_kind':'anniversary','p_note':''})))
 check('milestone-optin',rpc('pet_notifications',{**setting,'p_frequency':'off','p_milestones':True}))
 profile={'p_pet':pet,'p_name':original['name'],'p_breed':original['breed'],'p_introduction':original['introduction'],'p_details':{**original.get('details',{}),'life_status':'living'},'p_public_fields':original.get('public_fields',[])}
 check('living-status',rpc('update_pet',profile))
 check('known-date-only-milestone',rpc('family_notifications'),predicate=lambda rows:any(v['id'].startswith(events[-1]+':') for v in rows) and all(not any(v['id'].startswith(e+':') for e in events[:-1]) for v in rows))
 check('deceased-status',rpc('update_pet',{**profile,'p_details':{**profile['p_details'],'life_status':'deceased'}}))
 check('deceased-no-automated-celebration',rpc('family_notifications'),predicate=lambda rows:all(not any(v['id'].startswith(e+':') for e in events) for v in rows))
 check('deceased-album-preserved',rpc('album',{'p_pet':pet}),predicate=lambda rows:any(v['id']==photo['id'] for v in rows))
 check('delete-provider-photo',rpc('delete_photo',{'p_photo':photo['id']},'family'));photo=None
 check('groups-exclude-private-family-fields',rpc('social_notification_groups'),predicate=lambda rows:all('provider_id' not in v and 'count' in v for v in rows))
 outcome={'passed':True,'checks':c.checks,'apns_delivered':False,'scope':'actual dev notification projection; no Push service or human notifications'}
except Exception as e:outcome={'passed':False,'failure':str(e),'checks':c.checks}
finally:
 if photo:rpc('delete_photo',{'p_photo':photo['id']},'family')
 for id in events:rpc('delete_event',{'p_event':id})
 if original:rpc('update_pet',{'p_pet':c.pet,'p_name':original['name'],'p_breed':original['breed'],'p_introduction':original['introduction'],'p_details':original.get('details',{}),'p_public_fields':original.get('public_fields',[])})
 if joined:rpc('remove_member',{'p_pet':c.pet,'p_user':family_id})
 if pref:rpc('pet_notifications',{'p_pet':c.pet,'p_frequency':pref['frequency'],'p_milestones':pref['milestones'],'p_paused_until':pref.get('paused_until')})
 subprocess.run([sys.executable,str(ROOT/'scripts/process_deletion_outbox.py')],capture_output=True)
(ROOT/'docs/evidence/p1-notifications-server.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2));print(json.dumps({'passed':outcome['passed'],'checks':len(c.checks),'failure':outcome.get('failure')}));raise SystemExit(0 if outcome['passed'] else 1)
