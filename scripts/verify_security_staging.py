"""Bounded, owner-authorized attacks against MEFRION development fixtures only.

Never targets customer IDs; credentials remain in ignored .local files.
Reuses the established HTTP attack suite with an explicit development allowlist.
"""
import argparse, importlib.util, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from configure_stock_rotation import query
spec=importlib.util.spec_from_file_location('security_suite',ROOT/'scripts/verify_security_e2e.py')
suite=importlib.util.module_from_spec(spec);spec.loader.exec_module(suite)
STATE=ROOT/'.local/security-staging-20261025-state.json'
suite.STATE=STATE;suite.j.STATE=STATE
suite.j.BASE='https://pmrvzpuznwzuejbuhaqm.supabase.co'
suite.j.PUBLIC=json.loads((ROOT/'ios/MEFRION/DevelopmentPublicConfiguration.json').read_text())
assert suite.j.PUBLIC['url']==suite.j.BASE
suite.j.query=lambda sql:query('development',sql)

def extra_attacks(s):
 denied=(400,401,403,404)
 for name,body in [
  ('my_pet_icon',{'p_pet':s['pet']}),
  ('update_pet_profile',{'p_pet':s['pet'],'p_name':'UNAUTHORIZED CHANGE','p_breed':'','p_introduction':'','p_details':{},'p_public_fields':[],'p_icon':None,'p_icon_changed':True}),
  ('pending_invites',{'p_pet':s['pet']}),
  ('replace_invites',{'p_pet':s['pet'],'p_explicit':True})]:
  suite.rpc(s,name,body,'outsider',codes=denied,label='new-feature-idor-'+name+'-denied')
  suite.rpc(s,name,body,None,codes=denied,label='new-feature-anonymous-'+name+'-denied')
 for name,body in [('account_profile',{}),('set_account_profile',{'p_name':'ATTACK','p_icon':None,'p_icon_changed':False})]:
  suite.rpc(s,name,body,None,codes=denied,label='anonymous-'+name+'-denied')
 suite.rpc(s,'set_account_profile',{'p_name':'QA attacker only','p_icon':'not-a-jpeg','p_icon_changed':True},'outsider',codes=(400,),label='malformed-profile-icon-rejected')
 suite.rpc(s,'set_account_profile',{'p_name':None,'p_icon':'x'*22501,'p_icon_changed':True},'outsider',codes=(400,),label='oversized-profile-icon-rejected')

def main():
 p=argparse.ArgumentParser();p.add_argument('action',choices=['setup','verify','cleanup']);args=p.parse_args()
 result={'environment':'development','date':'2026-10-25','action':args.action,'scope':'dedicated disposable QA identities/media only; no brute force or load test'}
 try:
  if args.action=='setup':s=suite.setup()
  else:
   s=json.loads(STATE.read_text())
   if s.get('phase')=='retirement_requested':raise RuntimeError('QA accounts already retired; cannot reuse')
   suite.j.login(s)
   if args.action=='verify':
    suite.auth_and_idor(s);extra_attacks(s);suite.public_checks(s)
    result['successful_attacks']=[{'id':'CONTENT-01','severity':'medium','result':'Confirmed: non-animal solid-colour JPEG accepted and publicly served through direct API, bypassing client-only pet detection.','impact':'Authenticated users with their own Pet can bypass the dog/cat content rule; no cross-account access was needed.','previously_known':True}]
   else:suite.retirement(s)
  result.update(passed=all(c['passed'] for c in suite.CHECKS),checks=suite.CHECKS,failed_checks=[c['check'] for c in suite.CHECKS if not c['passed']])
 except Exception as error:
  # Errors must never include credential-bearing HTTP bodies.
  result.update(passed=False,checks=suite.CHECKS,failure_type=type(error).__name__)
 target=ROOT/('docs/evidence/SECURITY-STAGING-20261025-'+args.action.upper()+'.json')
 target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'action':args.action,'passed':result['passed'],'checks':len(result['checks']),'failed_checks':result.get('failed_checks'),'failure_type':result.get('failure_type'),'successful_attacks':result.get('successful_attacks',[])},ensure_ascii=False))
 return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
