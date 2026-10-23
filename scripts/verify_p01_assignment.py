"""Actual concurrent report claims; dedicated test staff, no human assignments."""
import base64,hashlib,hmac,json,secrets,struct,time,urllib.request,urllib.error
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4
from p1_test_support import ROOT
from process_account_retirement import execute
pub=json.loads((ROOT/'.local/supabase-public.json').read_text());srv=json.loads((ROOT/'.local/supabase-server.json').read_text());assert pub['url']==srv['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
f=json.loads((ROOT/'.local/operator-browser-fixture.json').read_text());case=json.loads((ROOT/'.local/p01-moderation-case.json').read_text());checks=[];second=None

def call(path,body=None,token=None,admin=False,method=None):
 key=srv['secret_key'] if admin else pub['anon_key'];h={'apikey':key};raw=None
 if token or admin:h['Authorization']='Bearer '+(token or key)
 if body is not None:raw=json.dumps(body).encode();h['Content-Type']='application/json'
 try:
  with urllib.request.urlopen(urllib.request.Request(pub['url']+path,data=raw,headers=h,method=method),timeout=40) as q:d=q.read();return q.status,json.loads(d) if d else None
 except urllib.error.HTTPError as e:return e.code,None

def check(label,result,codes=(200,),predicate=lambda v:True):
 s,v=result;ok=s in codes and predicate(v);checks.append({'check':label,'status':s,'passed':ok});assert ok,label;return v

def rpc(n,b={},t=None,admin=False):return call('/rest/v1/rpc/mefrion_'+n,b,t,admin)
def auth(person):
 x=check('reserved-password-login',call('/auth/v1/token?grant_type=password',{k:person[k] for k in ('email','password')}));assert x['user']['id']==person['id'] and x['user']['user_metadata']['test_only'];t=x['access_token']
 q=check('test-totp-challenge',call('/auth/v1/factors/'+person['factor']+'/challenge',{},t));key=base64.b32decode(person['secret']+'='*((8-len(person['secret'])%8)%8));d=hmac.new(key,struct.pack('>Q',int(time.time())//30),hashlib.sha1).digest();o=d[-1]&15;code=str((struct.unpack('>I',d[o:o+4])[0]&0x7fffffff)%1000000).zfill(6)
 return check('test-totp-verify',call('/auth/v1/factors/'+person['factor']+'/verify',{'challenge_id':q['id'],'code':code},t))['access_token']
try:
 firstToken=auth(f)
 second={'email':'mefrion-test-assignment-'+uuid4().hex+'@example.invalid','password':secrets.token_urlsafe(32)}
 user=check('create-reserved-second-staff',call('/auth/v1/admin/users',{**second,'email_confirm':True,'user_metadata':{'test_only':True}},admin=True),(200,201));second['id']=user['id'];path=ROOT/'.local/p01-assignment-staff.json';path.write_text(json.dumps(second));path.chmod(0o600)
 login=check('second-staff-password-login',call('/auth/v1/token?grant_type=password',{'email':second['email'],'password':second['password']}));enroll=check('second-test-factor',call('/auth/v1/factors',{'factor_type':'totp','friendly_name':'Synthetic assignment'},login['access_token']));second.update(factor=enroll['id'],secret=enroll['totp']['secret']);path.write_text(json.dumps(second));secondToken=auth(second);second['token']=secondToken;path.write_text(json.dumps(second));check('grant-reserved-second-staff',rpc('grant_test_operator',{'p_user':second['id'],'p_role':'moderator','p_active':True},admin=True))
 rows=check('queue',rpc('operator_queue',t=firstToken));row=next(r for r in rows if r['id']==case['report']);assert row['note']==case['note'] and not row['assignment']['assigned'];version=row['assignment']['version'];barrier=Barrier(2)
 def claim(t):barrier.wait();return rpc('operator_claim',{'p_report':case['report'],'p_version':version,'p_claim':True},t)
 with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(claim,[firstToken,secondToken]))
 assert sorted(s for s,_ in results)==[200,400];checks.append({'check':'simultaneous-claim-single-winner','passed':True})
 winner=0 if results[0][0]==200 else 1;tokens=[firstToken,secondToken];a=results[winner][1];assert a['mine'] and a['assigned'];loser=tokens[1-winner]
 check('other-active-staff-cannot-review',rpc('operator_review',{'p_report':case['report'],'p_decision':'dismiss','p_note':'Must not execute','p_request_key':str(uuid4())},loser),(403,))
 check('other-active-staff-cannot-steal-or-release',rpc('operator_claim',{'p_report':case['report'],'p_version':a['version'],'p_claim':False},loser),(403,))
 rows=check('loser-queue',rpc('operator_queue',t=loser));item=next(r for r in rows if r['id']==case['report']);assert item['assignment']['assigned'] and not item['assignment']['mine'];assert 'operator_id' not in json.dumps(item)
 release=check('winner-release',rpc('operator_claim',{'p_report':case['report'],'p_version':a['version'],'p_claim':False},tokens[winner]),predicate=lambda v:not v['assigned'] and not v['mine'])
 check('old-version-rejected',rpc('operator_claim',{'p_report':case['report'],'p_version':a['version'],'p_claim':True},loser),(400,))
 check('new-staff-can-claim-after-release',rpc('operator_claim',{'p_report':case['report'],'p_version':release['version'],'p_claim':True},loser))
 check('final-exact-release',rpc('operator_claim',{'p_report':case['report'],'p_version':release['version']+1,'p_claim':False},loser))
 outcome={'passed':True,'checks':checks}
except Exception as e:outcome={'passed':False,'checks':checks,'failure':str(e)}
finally:
 if second:
  check('disable-test-staff',rpc('grant_test_operator',{'p_user':second['id'],'p_role':'moderator','p_active':False},admin=True))
  if second.get('token'):check('remove-test-factor',call('/auth/v1/factors/'+second['factor'],token=second['token'],method='DELETE'))
  x=check('cleanup-second-login',call('/auth/v1/token?grant_type=password',{'email':second['email'],'password':second['password']}));check('retire-exact-test-staff',rpc('request_retirement',{'p_expected_user':second['id'],'p_explicit':True,'p_request_key':str(uuid4())},x['access_token']));assert execute(second['id'])['processed']==1;path.unlink()
 (ROOT/'docs/evidence/p01-assignment-race.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2));print(json.dumps({'passed':outcome['passed'],'checks':len(checks),'failure':outcome.get('failure')}))
if not outcome['passed']:raise SystemExit(1)
