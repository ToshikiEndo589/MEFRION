"""Actual guest HTTP; secrets never sent to share origin."""
import json,urllib.request,urllib.error
from p1_test_support import ROOT
f=json.loads((ROOT/'.local/p1-web-proof.json').read_text());share=f['share'];share=share['id'] if isinstance(share,dict) else share
checks=[]
def get(base,path,expected,method='GET'):
 try:q=urllib.request.urlopen(urllib.request.Request(base+path,method=method),timeout=30)
 except urllib.error.HTTPError as e:q=e
 with q:body=q.read();item={'path_type':'share' if 'post=' in path or 'cloud-shared' in path else 'boundary','status':q.status,'content_type':q.headers.get('Content-Type'),'cache_control':q.headers.get('Cache-Control'),'passed':q.status==expected};checks.append(item);assert item['passed'];return item,body
external='https://pmrvzpuznwzuejbuhaqm.supabase.co/functions/v1/shared-page'
item,body=get(external,'?post='+share,200);assert 'text/plain' in item['content_type'] and b'family-originals' not in body
get(external,'?post=invalid',404);get(external,'?post='+share,405,'POST')
item,body=get('http://127.0.0.1:9792','/cloud-shared/'+share,200);assert 'text/html' in item['content_type'] and b'MEFRION' in body and b'family-originals' not in body
get('http://127.0.0.1:9792','/admin/cloud',404);get('http://127.0.0.1:9792','/v1/development/cloud-public-config',404)
(ROOT/'docs/evidence/p01-share-http.json').write_text(json.dumps({'passed':True,'checks':checks,'external_html_renderable':False,'dedicated_local_html_renderable':True,'pending':'selected HTTPS host/domain and native Universal Links','official_constraint':'https://supabase.com/docs/guides/functions/http-methods'},indent=2));print(json.dumps({'passed':True,'checks':len(checks),'external_html_renderable':False}))
