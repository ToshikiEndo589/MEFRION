"""Approved dev project; only reserved synthetic owner/family/outsider identities."""
import io,json,urllib.request,urllib.error,hashlib
from pathlib import Path
from uuid import uuid4
from PIL import Image
root=Path(__file__).resolve().parent.parent
cfg=json.loads((root/'.local/supabase-public.json').read_text());assert cfg['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
people=json.loads((root/'.local/supabase-test-identities.json').read_text());tokens={};checks=[];photo_ids=[];event_ids=[];original=None
pet=json.loads((root/'.local/supabase-test-sessions.json').read_text())['pet_id']
def call(path,body=None,role=None,raw=None):
 h={'apikey':cfg['anon_key']}
 if role:h['Authorization']='Bearer '+tokens[role]
 if body is not None:raw=json.dumps(body).encode();h['Content-Type']='application/json'
 elif raw is not None:h['Content-Type']='image/jpeg'
 try:
  with urllib.request.urlopen(urllib.request.Request(cfg['url']+path,data=raw,headers=h),timeout=30) as r:
   data=r.read();return r.status,json.loads(data) if 'json' in r.headers.get('Content-Type','') else data
 except urllib.error.HTTPError as e:return e.code,{}
def check(label,result,statuses=(200,),predicate=lambda v:True):
 status,value=result;ok=status in statuses and predicate(value);checks.append({'check':label,'passed':ok,'status':status})
 if not ok:raise RuntimeError(label+' failed')
 return value
def rpc(name,body=None,role='owner'):return call('/rest/v1/rpc/mefrion_'+name,body or {},role)
try:
 for p in people:
  assert p['email'].startswith('mefrion-test-') and p['email'].endswith('@example.invalid')
  tokens[p['role']]=check('login-'+p['role'],call('/auth/v1/token?grant_type=password',{'email':p['email'],'password':p['password']}))['access_token']
 original=next(v for v in check('private-pets',rpc('list_pets')) if v['id']==pet)
 assert original['name']=='E2E合成試験'
 profile={'p_pet':pet,'p_name':original['name'],'p_breed':'Synthetic private breed','p_introduction':'Family only','p_details':{'sex':'female','birthday':'2020-02','arrival':'2021','age_basis':'estimated','temperament':'family private','life_status':'deceased'},'p_public_fields':[]}
 check('full-private-profile-update',rpc('update_pet',profile))
 check('profile-roundtrip',rpc('list_pets'),predicate=lambda rows:next(v for v in rows if v['id']==pet)['details']==profile['p_details'])
 check('outsider-profile-edit-denied',rpc('update_pet',profile,'outsider'),(403,))
 check('family-profile-edit-denied',rpc('update_pet',profile,'family'),(403,))
 check('anonymous-profile-edit-denied',rpc('update_pet',profile,None),(401,403))
 check('invalid-birthday-denied',rpc('update_pet',{**profile,'p_details':{'birthday':'2021-02-29'}}),(400,))
 check('unknown-public-field-denied',rpc('update_pet',{**profile,'p_public_fields':['owner_id']}),(400,))
 check('cross-pet-profile-photo-denied',rpc('update_pet',{**profile,'p_details':{'icon_photo':str(uuid4())}}),(400,))
 check('public-profile-explicit',rpc('set_public_profile',{'p_pet':pet,'p_enabled':True,'p_explicit':True}))
 check('public-fields-exclude-family-metadata',rpc('public_pet',{'p_pet':pet},None),predicate=lambda v:set(v)=={'id','name','species'})
 check('public-field-selected',rpc('update_pet',{**profile,'p_public_fields':['sex']}))
 check('public-field-projection',rpc('public_pet',{'p_pet':pet},None),predicate=lambda v:v.get('sex')=='female' and 'birthday' not in v and 'temperament' not in v)
 check('profile-withdraw',rpc('set_public_profile',{'p_pet':pet,'p_enabled':False}))
 check('withdrawn-public-profile-denied',rpc('public_pet',{'p_pet':pet},None),(401,403))
 for date in [None,'2020','2020-02','2020-02-29']:
  key=str(uuid4());args={'p_pet':pet,'p_key':key,'p_captured':date,'p_title':'Synthetic milestone','p_kind':'other','p_note':'owned fixture'}
  event=check('event-date-precision',rpc('save_event',args));event_ids.append(event)
  check('event-idempotency',rpc('save_event',args),predicate=lambda v:v==event)
  check('event-key-conflict',rpc('save_event',{**args,'p_note':'changed'}),(400,))
 check('unknown-event-date-preserved',rpc('events',{'p_pet':pet}),predicate=lambda rows:any(v['id']==event_ids[0] and v['captured'] is None for v in rows))
 check('outsider-events-denied',rpc('events',{'p_pet':pet},'outsider'),(403,))
 check('invalid-event-date-denied',rpc('save_event',{'p_pet':pet,'p_key':str(uuid4()),'p_captured':'2023-02-29','p_title':'bad','p_kind':'other','p_note':''}),(400,))
 check('pet-notifications-off',rpc('pet_notifications',{'p_pet':pet,'p_frequency':'off','p_milestones':False,'p_paused_until':None}))
 check('pet-notification-roundtrip',rpc('get_pet_notifications',{'p_pet':pet}),predicate=lambda v:v['frequency']=='off' and not v['milestones'])
 check('outsider-pet-preferences-denied',rpc('pet_notifications',{'p_pet':pet,'p_frequency':'immediate','p_milestones':True,'p_paused_until':None},'outsider'),(403,))
 settings={'like':False,'comment':False,'follow':False,'twins':False}
 oldprefs=check('notification-defaults',rpc('notification_preferences'))
 check('notification-settings-applied',rpc('set_notification_preferences',{'p_settings':settings}))
 check('notification-settings-roundtrip',rpc('notification_preferences'),predicate=lambda v:v==settings)
 check('other-user-settings-isolated',rpc('notification_preferences',role='outsider'),predicate=lambda v:v!=settings)
 check('notification-invalid-schema-denied',rpc('set_notification_preferences',{'p_settings':{**settings,'other':True}}),(400,))
 check('anonymous-notification-settings-denied',rpc('notification_preferences',role=None),(401,403))
 check('restore-notification-settings',rpc('set_notification_preferences',{'p_settings':oldprefs}))
 stream=io.BytesIO();Image.new('RGB',(120,120),(200,170,155)).save(stream,'JPEG');jpeg=stream.getvalue();fingerprint=hashlib.sha256(jpeg).hexdigest()
 for number in range(2):
  photo=check('reserve-photo',rpc('begin_photo',{'p_pet':pet,'p_request_key':str(uuid4()),'p_captured':None,'p_title':'Synthetic P1 only'}));photo_ids.append(photo['id'])
  check('register-fingerprint',rpc('record_fingerprint',{'p_photo':photo['id'],'p_fingerprint':fingerprint}),predicate=lambda v:len(v)==number)
  check('upload-jpeg',call('/storage/v1/object/family-originals/'+photo['path'],role='owner',raw=jpeg),(200,201))
  check('finish-jpeg',rpc('finish_photo',{'p_photo':photo['id']}))
 edit={'p_photo':photo_ids[0],'p_captured':'2020-02','p_title':'Synthetic edit','p_event_kind':'hospital','p_note':'Family note'}
 check('provider-photo-edit',rpc('edit_photo',edit))
 check('outsider-photo-edit-denied',rpc('edit_photo',edit,'outsider'),(403,))
 check('invalid-photo-date-denied',rpc('edit_photo',{**edit,'p_captured':'2021-02-29'}),(400,))
 check('photo-edit-roundtrip',rpc('album',{'p_pet':pet}),predicate=lambda rows:any(v['id']==photo_ids[0] and v['event_kind']=='hospital' and v['captured']=='2020-02' and v['note']=='Family note' for v in rows))
 check('family-profile-image',rpc('update_pet',{**profile,'p_details':{'icon_photo':photo_ids[0],'cover_photo':photo_ids[0]}}))
 check('delete-profile-source',rpc('delete_photo',{'p_photo':photo_ids[0]}));photo_ids.remove(photo_ids[0])
 check('deleted-profile-image-cleared',rpc('list_pets'),predicate=lambda rows:next(v for v in rows if v['id']==pet)['details']=={})
 outcome={'passed':True,'scope':'reserved synthetic profiles/events/photos/notification RPCs','checks':checks}
except Exception as e:outcome={'passed':False,'failure':str(e),'checks':checks}
finally:
 for id in photo_ids:check('cleanup-photo',rpc('delete_photo',{'p_photo':id}))
 for id in event_ids:check('cleanup-event',rpc('delete_event',{'p_event':id}))
 if original:
  check('restore-private-profile',rpc('update_pet',{'p_pet':pet,'p_name':original['name'],'p_breed':original['breed'],'p_introduction':original['introduction'],'p_details':original.get('details',{}),'p_public_fields':original.get('public_fields',[])}))
  check('keep-profile-private',rpc('set_public_profile',{'p_pet':pet,'p_enabled':False}))
 (root/'docs/evidence/p1-album-server.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'passed':outcome['passed'],'checks':len(checks),'failure':outcome.get('failure')}))
if not outcome['passed']:raise SystemExit(1)
