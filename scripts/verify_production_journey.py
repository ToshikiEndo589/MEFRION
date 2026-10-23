"""Production acceptance through normal Auth, Storage and customer RPCs.

Creates only explicitly synthetic QA identities and media. Never selects a
customer or changes production settings. Email-delivery verification is separate.
Credentials are restricted to ignored .local files; evidence contains checks only.
"""
import argparse,io,json,secrets,time,urllib.error,urllib.request
from pathlib import Path
from uuid import uuid4
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];STATE=ROOT/'.local/production-journey-state.json'
BASE='https://pbnimpqrthvznbwewtcf.supabase.co';PUBLIC=json.loads((ROOT/'ios/MEFRION/ProductionPublicConfiguration.json').read_text());assert PUBLIC['url']==BASE
CHECKS=[]
def query(sql):
 token=(ROOT/'.local/cloud-migration-token').read_text().strip()
 req=urllib.request.Request('https://api.supabase.com/v1/projects/pbnimpqrthvznbwewtcf/database/query',data=json.dumps({'query':sql}).encode(),headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(req,timeout=120) as f:return json.load(f)
 except urllib.error.HTTPError as e:raise RuntimeError('SQL failed: '+e.read().decode()[:500]) from None
def lit(v):return "'"+str(v).replace("'","''")+"'"
def save(s):STATE.touch(mode=0o600,exist_ok=True);STATE.chmod(0o600);STATE.write_text(json.dumps(s))
def call(path,body=None,token=None,raw=None,mime='image/jpeg',method=None):
 headers={'apikey':PUBLIC['anon_key']}
 if token:headers['Authorization']='Bearer '+token
 if body is not None:raw=json.dumps(body).encode();headers['Content-Type']='application/json'
 elif raw is not None:headers['Content-Type']=mime
 try:
  with urllib.request.urlopen(urllib.request.Request(BASE+path,data=raw,headers=headers,method=method),timeout=90) as f:
   b=f.read();return f.status,json.loads(b) if 'json' in f.headers.get('Content-Type','') else b
 except urllib.error.HTTPError as e:
  try:d=json.loads(e.read())
  except ValueError:d={}
  return e.code,d

def check(label,result,statuses=(200,),predicate=lambda d:True):
 code,data=result;ok=code in statuses and predicate(data);CHECKS.append({'check':label,'status':code,'passed':ok})
 if not ok:raise RuntimeError(label+': HTTP '+str(code)+' code '+str(data.get('message',data.get('error_code','')))[:150] if isinstance(data,dict) else label+' failed')
 return data

def rpc(s,name,body=None,role='owner',statuses=(200,),predicate=lambda d:True):
 return check(name,call('/rest/v1/rpc/mefrion_'+name,body or {},s['users'][role]['token'] if role else None),statuses,predicate)
def login(s):
 for role,u in s['users'].items():
  session=check('password-login-'+role,call('/auth/v1/token?grant_type=password',{'email':u['email'],'password':u['password']}));u['token']=session['access_token']
 save(s)
def setup():
 if STATE.exists():raise RuntimeError('Existing fixture; inspect instead of creating another')
 s={'users':{r:{'id':str(uuid4()),'email':'mefrion-qa-'+uuid4().hex+'@example.invalid','password':secrets.token_urlsafe(32)} for r in ['owner','family','outsider']},'photos':[]};save(s)
 statements=['begin']
 for u in s['users'].values():
  statements.append("insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,reauthentication_token,phone_change_token,raw_app_meta_data,raw_user_meta_data) values("+lit(u['id'])+",'00000000-0000-0000-0000-000000000000','authenticated','authenticated',"+lit(u['email'])+",extensions.crypt("+lit(u['password'])+",extensions.gen_salt('bf',10)),now(),now(),now(),'','','','','','','','{\"provider\":\"email\",\"providers\":[\"email\"]}','{\"deployment_fixture\":true}')")
 statements.append('commit');query(';'.join(statements)+';');login(s)
 rpc(s,'list_pets',predicate=lambda d:d==[])
 rpc(s,'feed_page',{'p_limit':10},predicate=lambda d:isinstance(d['items'],list))
 s['pet']=rpc(s,'create_pet',{'p_name':'QAサーバー確認','p_species':'dog','p_breed':'','p_introduction':'合成データの動作確認です'})['id'];save(s)
 rpc(s,'album',{'p_pet':s['pet']},role='outsider',statuses=(401,403))
 invitation=rpc(s,'invite',{'p_pet':s['pet']});rpc(s,'accept_invite',{'p_token':invitation['token'],'p_confirm_scope':True},role='family')
 rpc(s,'accept_invite',{'p_token':invitation['token'],'p_confirm_scope':True},role='outsider',statuses=(400,))
 image=Image.new('RGB',(1200,800),(222,180,155));stream=io.BytesIO();image.save(stream,'JPEG');jpeg=stream.getvalue()
 for kind in ['image','video']:
  reservation=rpc(s,'begin_photo' if kind=='image' else 'begin_video',{'p_pet':s['pet'],'p_request_key':str(uuid4()),**({'p_duration':2} if kind=='video' else {})})
  s['photos'].append(reservation);save(s)
  data=jpeg if kind=='image' else (ROOT/'.local/cloud-video-fixture.mp4').read_bytes()
  check('original-upload-'+kind,call('/storage/v1/object/family-originals/'+reservation['path'],token=s['users']['owner']['token'],raw=data,mime='image/jpeg' if kind=='image' else 'video/mp4'),(200,201))
  if kind=='video':check('poster-upload',call('/storage/v1/object/family-originals/'+reservation['preview_path'],token=s['users']['owner']['token'],raw=jpeg),(200,201))
  rpc(s,'finish_photo' if kind=='image' else 'finish_video',{'p_photo':reservation['id']})
  rpc(s,'consent',{'p_photo':reservation['id'],'p_purpose':'sns','p_allowed':True})
 rpc(s,'album',{'p_pet':s['pet']},role='family',predicate=lambda d:len(d)==2)
 check('private-image-family',call('/functions/v1/private-image?photo='+s['photos'][0]['id'],token=s['users']['family']['token']),predicate=lambda d:d==jpeg)
 check('private-image-outsider-denied',call('/functions/v1/private-image?photo='+s['photos'][0]['id'],token=s['users']['outsider']['token']),(401,403,404))
 rpc(s,'set_public_profile',{'p_pet':s['pet'],'p_enabled':True,'p_explicit':True})
 body={'p_pet':s['pet'],'p_photos':[p['id'] for p in s['photos']],'p_body':'合成データによる本番動作確認','p_kind':'post','p_request_key':str(uuid4()),'p_explicit':True}
 post=rpc(s,'request_publication',body);s['post']=post['id'];save(s)
 rpc(s,'request_publication',body,predicate=lambda d:d['id']==s['post'])
 s['phase']='publication_requested';save(s);return s

def verify(s):
 login(s)
 rows=rpc(s,'public_feed',role='outsider');post=next((r for r in rows if r['id']==s['post']),None)
 if post is None:raise RuntimeError('Waiting for cloud publication')
 assert len(post['media'])==2
 for i,media in enumerate(post['media']):
  # Legacy projection exposes ordered IDs; detailed media kinds have their own RPC.
  mid=media if isinstance(media,str) else media['id']
  check('public-media-'+str(i),call('/functions/v1/'+('public-image' if i==0 else 'public-video')+'?media='+mid),predicate=lambda d:isinstance(d,bytes) and len(d)>100)
 rpc(s,'set_social_name',{'p_name':'QA閲覧'},role='outsider')
 rpc(s,'react',{'p_post':s['post'],'p_kind':'like','p_enabled':True},role='outsider')
 rpc(s,'react',{'p_post':s['post'],'p_kind':'save','p_enabled':True},role='outsider')
 rpc(s,'saved_feed',role='outsider',predicate=lambda d:any(r['id']==s['post'] for r in d))
 rpc(s,'follow',{'p_pet':s['pet'],'p_enabled':True},role='outsider')
 rpc(s,'comment',{'p_post':s['post'],'p_body':'合成データのコメント確認','p_parent':None,'p_alias_pet':None,'p_request_key':str(uuid4())},role='outsider')
 rpc(s,'comments',{'p_post':s['post']},predicate=lambda d:len(d)==1)
 rpc(s,'report',{'p_post':s['post'],'p_pet':s['pet'],'p_reason':'other','p_note':'Synthetic QA intake; no real person/content','p_request_key':str(uuid4())},role='outsider')
 rpc(s,'report_queue',role='outsider',statuses=(403,))
 rpc(s,'block_pet',{'p_pet':s['pet'],'p_enabled':True},role='outsider')
 rpc(s,'public_feed',role='outsider',predicate=lambda d:all(r['id']!=s['post'] for r in d))
 rpc(s,'block_pet',{'p_pet':s['pet'],'p_enabled':False},role='outsider')
 s['phase']='verified';save(s);return s

def retire(s):
 login(s)
 for role in ['family','outsider','owner']:
  rpc(s,'request_retirement',{'p_request_key':str(uuid4()),'p_explicit':True,'p_expected_user':s['users'][role]['id']},role=role)
 s['phase']='retirement_requested';save(s);return s

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('action',choices=['setup','verify','retire']);args=parser.parse_args()
 try:
  s=setup() if args.action=='setup' else (verify if args.action=='verify' else retire)(json.loads(STATE.read_text()))
  report={'action':args.action,'passed':True,'checks':CHECKS,'email_delivery_tested':False,'scope':'real production Auth login / customer RPC / synthetic fixtures only'}
 except Exception as e:
  report={'action':args.action,'passed':False,'checks':CHECKS,'failure':str(e)}
 path=ROOT/'docs/evidence'/('PRODUCTION-JOURNEY-'+args.action.upper()+'-20261023.json');path.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n');print(json.dumps({'action':args.action,'passed':report['passed'],'checks':len(CHECKS),'failure':report.get('failure')},ensure_ascii=False))
 raise SystemExit(0 if report['passed'] else 1)
