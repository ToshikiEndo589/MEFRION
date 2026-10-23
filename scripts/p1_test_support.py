"""No production endpoint or human identities accepted; no credentials logged."""
import json,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
class DevelopmentClient:
 def __init__(self):
  self.config=json.loads((ROOT/'.local/supabase-public.json').read_text());assert self.config['url']=='https://pmrvzpuznwzuejbuhaqm.supabase.co'
  self.people=json.loads((ROOT/'.local/supabase-test-identities.json').read_text());self.tokens={};self.checks=[]
  self.pet=json.loads((ROOT/'.local/supabase-test-sessions.json').read_text())['pet_id']
 def call(self,path,body=None,role=None,raw=None):
  headers={'apikey':self.config['anon_key']}
  if role:headers['Authorization']='Bearer '+self.tokens[role]
  if body is not None:raw=json.dumps(body).encode();headers['Content-Type']='application/json'
  elif raw is not None:headers['Content-Type']='image/jpeg'
  try:
   with urllib.request.urlopen(urllib.request.Request(self.config['url']+path,data=raw,headers=headers),timeout=40) as r:
    value=r.read();return r.status,json.loads(value) if 'json' in r.headers.get('Content-Type','') else value
  except urllib.error.HTTPError as e:
   data=e.read()
   return e.code,{}
 def rpc(self,name,body=None,role='owner'):return self.call('/rest/v1/rpc/mefrion_'+name,body or {},role)
 def check(self,label,result,statuses=(200,),predicate=lambda v:True):
  status,value=result;passed=status in statuses and predicate(value);self.checks.append({'check':label,'passed':passed,'status':status})
  if not passed:raise RuntimeError(label+' failed')
  return value
 def login(self):
  for p in self.people:
   assert p['email'].startswith('mefrion-test-') and p['email'].endswith('@example.invalid')
   self.tokens[p['role']]=self.check('login-'+p['role'],self.call('/auth/v1/token?grant_type=password',{'email':p['email'],'password':p['password']}))['access_token']
   user=self.check('identity-'+p['role'],self.call('/auth/v1/user',role=p['role']));assert user['id']==p['id'] and user['user_metadata']['test_only']
  assert any(v['id']==self.pet and v['name']=='E2E合成試験' for v in self.check('fixture-pet',self.rpc('list_pets')))
