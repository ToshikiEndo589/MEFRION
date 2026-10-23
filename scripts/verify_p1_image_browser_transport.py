"""Exact development browser origin with unchanged per-photo authorization."""
import json,urllib.request,urllib.error
from p1_test_support import ROOT,DevelopmentClient
c=DevelopmentClient();checks=[]
def probe(label,method,origin,auth=None,expected=204,allowed=False):
 headers={'Origin':origin,'apikey':c.config['anon_key']}
 if auth:headers['Authorization']='Bearer '+auth
 if method=='OPTIONS':headers.update({'Access-Control-Request-Method':'GET','Access-Control-Request-Headers':'authorization,apikey'})
 try:r=urllib.request.urlopen(urllib.request.Request(c.config['url']+'/functions/v1/private-image?photo=00000000-0000-0000-0000-000000000000',method=method,headers=headers),timeout=40)
 except urllib.error.HTTPError as e:r=e
 actual=r.status;returned=r.headers.get('Access-Control-Allow-Origin');ok=actual==expected and (returned==origin if allowed else returned is None) and r.headers.get('Cache-Control')=='private, no-store, max-age=0';checks.append({'check':label,'passed':ok,'status':actual});assert ok,label
try:
 probe('exact-loopback-preflight','OPTIONS','http://127.0.0.1:8781',allowed=True)
 probe('unlisted-origin-preflight-rejected','OPTIONS','https://untrusted.example',expected=403)
 probe('browser-get-still-needs-login','GET','http://127.0.0.1:8781',expected=401,allowed=True)
 c.login();probe('outsider-invalid-photo-not-readable','GET','http://127.0.0.1:8781',c.tokens['outsider'],404,True)
 outcome={'passed':True,'checks':checks}
except Exception as e:outcome={'passed':False,'failure':str(e),'checks':checks}
(ROOT/'docs/evidence/p1-image-browser-transport.json').write_text(json.dumps(outcome,indent=2)+'\n');print(json.dumps({'passed':outcome['passed'],'checks':len(checks),'failure':outcome.get('failure')}));raise SystemExit(0 if outcome['passed'] else 1)
