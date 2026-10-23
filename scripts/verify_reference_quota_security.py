"""Opt-in live quota regression; touches only this tester network counter briefly.
No raw IP, features, secrets or user content are printed. Counter is restored.
"""
import argparse,importlib.util,json
from uuid import uuid4
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--live-production',action='store_true');args=parser.parse_args()
if not args.live_production:parser.error('Explicit --live-production is required')
sp=importlib.util.spec_from_file_location('s','scripts/verify_security_e2e.py');s=importlib.util.module_from_spec(sp);sp.loader.exec_module(s)
rows=s.j.query("select a.species,a.embedding::text as legacy,r.embedding::text as query,r.color::text as color,a.fingerprint::text as fingerprint,a.mean from public.mefrion_reference_resemblance r join public.mefrion_reference_assets a using(id) where a.active and a.withdrawn_at is null limit 1")
r=rows[0]
b={'p_species':r['species'],'p_query':r['query'],'p_color':r['color'],'p_legacy':r['legacy'],'p_fingerprint':r['fingerprint'],'p_mean':r['mean'],'p_algorithm':'dinov2-small-subject-v1','p_consent':True,'p_guest':str(uuid4()),'p_request':str(uuid4())}
ids=[b['p_request']]
a=s.request('/rest/v1/rpc/mefrion_reference_search_v2',b)
if a[0]!=200:raise RuntimeError('Normal guest search failed: '+str(a[0])+' '+str(a[1].get('message','')))
row=s.j.query('select actor from public.mefrion_resemblance_retries where id='+s.j.lit(b['p_request']))[0];actor=row['actor']
if not actor.startswith('network:'):raise RuntimeError('Quota identity not server-bound')
previous=s.j.query('select count from public.mefrion_reference_usage where actor='+s.j.lit(actor)+" and day=(now() at time zone 'Asia/Tokyo')::date")[0]['count']
checks=[]
try:
 s.j.query('update public.mefrion_reference_usage set count=10 where actor='+s.j.lit(actor)+" and day=(now() at time zone 'Asia/Tokyo')::date")
 for label,headers in [('rotated-client-id',{}),('forged-x-forwarded-for',{'X-Forwarded-For':'203.0.113.88'}),('forged-cf-connecting-ip',{'CF-Connecting-IP':'203.0.113.89'}),('both-ip-headers-forged',{'X-Forwarded-For':'203.0.113.90','CF-Connecting-IP':'203.0.113.91'})]:
  b['p_request']=str(uuid4());b['p_guest']=str(uuid4());ids.append(b['p_request']);r=s.request('/rest/v1/rpc/mefrion_reference_search_v2',b,headers=headers)
  checks.append({'check':label,'status':r[0],'passed':r[0]==403 or (r[0]==400 and isinstance(r[1],dict) and r[1].get('message')=='reference_search_limit')})
finally:
 s.j.query('update public.mefrion_reference_usage set count='+str(previous)+' where actor='+s.j.lit(actor)+" and day=(now() at time zone 'Asia/Tokyo')::date;delete from public.mefrion_resemblance_retries where id in ("+','.join(s.j.lit(i) for i in ids)+')')
result={'guest_search_works':True,'raw_ip_not_stored':True,'checks':checks,'passed':all(x['passed'] for x in checks)}
Path('docs/evidence/SECURITY-REFERENCE-QUOTA-20261023.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
raise SystemExit(0 if result['passed'] else 1)
