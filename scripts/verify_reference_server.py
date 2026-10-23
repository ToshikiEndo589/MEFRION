"""Live stock-only development checks. Never accesses family originals or human accounts."""
import concurrent.futures,json,struct,time,urllib.error,urllib.request,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def main():
 public=json.loads((ROOT/'.local/supabase-public.json').read_text())
 service=json.loads((ROOT/'.local/supabase-server.json').read_text())
 assert public['url']==service['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
 catalog=json.loads((ROOT/'.local/TwinsServerIndex/catalog.json').read_text())['assets']
 vectors=(ROOT/'.local/TwinsServerIndex/vectors.bin').read_bytes();checks=[]
 def call(path,body=None,privileged=False,token=None):
  key=service['secret_key'] if privileged else public['anon_key'];headers={'apikey':key}
  if privileged:headers['Authorization']='Bearer '+key
  elif token:headers['Authorization']='Bearer '+token
  data=None
  if body is not None:data=json.dumps(body,allow_nan=False).encode();headers['Content-Type']='application/json'
  start=time.monotonic()
  try:
   with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=data,headers=headers),timeout=40) as r:
    raw=r.read();value=json.loads(raw) if 'json' in r.headers.get('Content-Type','') else raw
    return r.status,value,dict(r.headers),time.monotonic()-start
  except urllib.error.HTTPError as e:
   raw=e.read()
   try:value=json.loads(raw)
   except ValueError:value={}
   return e.code,value,dict(e.headers),time.monotonic()-start
 def check(label,result,condition):
  assert condition,label
  checks.append({'check':label,'status':result[0],'seconds':round(result[3],4),'passed':True})
 def rpc(name,body,privileged=False):return call('/rest/v1/rpc/mefrion_reference_'+name,body,privileged)
 counts={}
 for species in ('dog','cat'):
  r=rpc('stats',{'p_species':species});check('count-'+species,r,r[0]==200 and r[1]['count']>1000);counts[species]=r[1]['count']
  preview=r[1]['assets'][0];r=call('/functions/v1/public-image?reference='+preview['id']);check('stock-image-'+species,r,r[0]==200 and r[1].startswith(b'\xff\xd8') and len(r[1])<=200000 and 'no-store' in r[2].get('Cache-Control',r[2].get('cache-control','')))
 r=call('/rest/v1/mefrion_reference_assets?select=embedding');check('vectors-not-public',r,r[0] in (401,403))
 r=call('/rest/v1/mefrion_reference_usage?select=*');check('usage-not-public',r,r[0] in (401,403))
 r=rpc('activate',{'p_ids':[catalog[0]['id']]});check('anonymous-cannot-activate',r,r[0] in (401,403,404))
 r=call('/storage/v1/object/public/reference-thumbnails/'+catalog[0]['file']);check('bucket-is-private',r,r[0] in (400,401,403,404))
 r=call('/functions/v1/public-image?reference=pexels-0');check('unknown-image-hidden',r,r[0]==404)
 r=call('/functions/v1/public-image?reference='+catalog[0]['id']+'&media='+str(uuid.uuid4()));check('mixed-image-parameters-rejected',r,r[0]==404)
 r=call('/functions/v1/public-image?media=invalid');check('old-public-image-input-guard',r,r[0]==404)
 bodies=[]
 first_result=None
 for species in ('dog','cat'):
  i,a=next((i,a) for i,a in enumerate(catalog) if a['species']==species)
  values=list(struct.unpack_from('<768f',vectors,i*768*4))
  body={'p_species':species,'p_query':json.dumps(values),'p_fingerprint':a['fingerprint'],'p_mean':a['mean'],'p_revision':2,'p_consent':True,'p_guest':str(uuid.uuid4()),'p_request':str(uuid.uuid4())};bodies.append(body)
  r=rpc('search',body);check('rank-'+species,r,r[0]==200 and 1<=len(r[1])<=3 and all(x['species']==species and x['demoOnly'] and x['id']!=a['id'] for x in r[1]))
  repeated=rpc('search',body);check('idempotent-'+species,repeated,repeated[0]==200 and repeated[1]==r[1])
  if species=='dog':first_result=r[1]
 for field,value in [('p_consent',False),('p_revision',1),('p_species','bird'),('p_fingerprint','1'),('p_query','[1,2]'),('p_query','x'*32001)]:
  body=dict(bodies[0]);body[field]=value;body['p_request']=str(uuid.uuid4());r=rpc('search',body);check('reject-'+field+'-'+str(value)[:10],r,r[0]>=400)
 # Independent installation UUID, same request concurrently: both succeed, counter charged once.
 body=dict(bodies[0]);body.update(p_guest=str(uuid.uuid4()),p_request=str(uuid.uuid4()))
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(lambda _:rpc('search',body),range(2)))
 check('concurrent-replay',results[0],all(r[0]==200 for r in results) and results[0][1]==results[1][1])
 r=call('/rest/v1/mefrion_reference_usage?select=count&actor=eq.guest:'+body['p_guest'],privileged=True);check('replay-charged-once',r,r[0]==200 and r[1][0]['count']==1)
 # Guest daily cap; no photos sent, same stock feature used in every request.
 body=dict(bodies[0]);body['p_guest']=str(uuid.uuid4())
 for i in range(11):
  body['p_request']=str(uuid.uuid4());r=rpc('search',body)
  check('guest-quota-'+str(i+1),r,r[0]==200 if i<10 else r[0]>=400 and r[1].get('message')=='reference_search_limit')
 # Authenticated boundary uses only an existing disposable synthetic test identity.
 identity=next(x for x in json.loads((ROOT/'.local/supabase-test-identities.json').read_text()) if x['role']=='owner')
 assert identity['email'].startswith('mefrion-test-') and identity['email'].endswith('@example.invalid')
 r=call('/auth/v1/token?grant_type=password',{'email':identity['email'],'password':identity['password']})
 check('synthetic-member-login',r,r[0]==200 and r[1]['user']['id']==identity['id'] and r[1]['user']['user_metadata']['test_only'])
 token=r[1]['access_token']
 from datetime import datetime
 from zoneinfo import ZoneInfo
 today=datetime.now(ZoneInfo('Asia/Tokyo')).date().isoformat()
 # Arrange the last allowed attempt without submitting 49 redundant searches.
 # Use PATCH on the existing synthetic counter, or insert after one initial request.
 headers={'apikey':service['secret_key'],'Authorization':'Bearer '+service['secret_key'],'Content-Type':'application/json'}
 path='/rest/v1/mefrion_reference_usage?actor=eq.user:'+identity['id']+'&day=eq.'+today
 with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=b'{"count":0}',headers=headers,method='PATCH'),timeout=40) as response:assert response.status==204
 body=dict(bodies[0]);body['p_request']=str(uuid.uuid4())
 r=call('/rest/v1/rpc/mefrion_reference_search',body,token=token)
 check('member-query',r,r[0]==200)
 headers={'apikey':service['secret_key'],'Authorization':'Bearer '+service['secret_key'],'Content-Type':'application/json'}
 path='/rest/v1/mefrion_reference_usage?actor=eq.user:'+identity['id']+'&day=eq.'+today
 with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=b'{"count":49}',headers=headers,method='PATCH'),timeout=40) as response:assert response.status==204
 for allowed in (True,False):
  body['p_request']=str(uuid.uuid4());r=call('/rest/v1/rpc/mefrion_reference_search',body,token=token)
  check('member-last-allowed' if allowed else 'member-limit-enforced',r,r[0]==200 if allowed else r[0]>=400 and r[1].get('message')=='reference_search_limit')
 r=call('/storage/v1/object/sign/reference-thumbnails/'+catalog[0]['file'],{'expiresIn':3600},token=token)
 check('member-cannot-sign-stock-path',r,r[0]>=400)
 with urllib.request.urlopen(urllib.request.Request(public['url']+path,data=b'{"count":0}',headers=headers,method='PATCH'),timeout=40) as response:assert response.status==204
 # Metadata tables do not contain any feature/image columns for ephemeral query records.
 r=call('/rest/v1/mefrion_reference_retries?select=*&limit=1',privileged=True)
 check('query-not-persisted',r,r[0]==200 and all(set(row)=={'id','actor','species','candidates','expires'} for row in r[1]))
 # Withdraw one newly imported development stock reference, never family data.
 fixture=ROOT/'.local/reference-withdrawal-fixture.json'
 if not fixture.exists():
  target=first_result[0]['id'];fixture.write_text(json.dumps({'id':target,'scope':'new development Pexels stock reference test only'}))
 else:target=json.loads(fixture.read_text())['id']
 r=rpc('withdraw',{'p_id':target},True);check('stock-withdrawal',r,r[0]==200 and r[1] is True)
 r=rpc('lookup',{'p_ids':[target]});check('withdrawn-metadata-hidden',r,r[0]==200 and r[1]==[])
 r=call('/functions/v1/public-image?reference='+target);check('withdrawn-image-hidden',r,r[0]==404)
 r=rpc('search',bodies[0]);check('cached-results-honor-withdrawal',r,r[0]==200 and all(a['id']!=target for a in r[1]))
 r=rpc('activate',{'p_ids':[target]},True);check('withdrawn-cannot-reactivate',r,r[0]==200 and r[1]==0)
 for species in ('dog','cat'):
  r=rpc('stats',{'p_species':species});check('final-count-'+species,r,r[0]==200);counts[species]=r[1]['count']
 report={'counts':counts,'checks':checks,'passed':len(checks),'query_source':'Pexels stock only','private_family_data_accessed':False,'query_images_uploaded':False}
 (ROOT/'docs/evidence/server-reference-live-checks.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'counts':counts,'passed':len(checks)}))

if __name__=='__main__':main()
