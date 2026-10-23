"""Family-only, self-selected aliases; no email/full identity in projections."""
import json,sys,subprocess
from p1_test_support import ROOT,DevelopmentClient
c=DevelopmentClient();rpc=c.rpc;check=c.check;joined=False;names={};family=None
try:
 c.login();family=next(p['id'] for p in c.people if p['role']=='family');members=check('original-members',rpc('members',{'p_pet':c.pet}));names={p['id']:p.get('display_name','') for p in members}
 if not any(p['id']==family for p in members):
  invite=check('invite',rpc('invite',{'p_pet':c.pet}));check('family-join',rpc('accept_invite',{'p_token':invite['token'],'p_confirm_scope':True},'family'));joined=True
 args={'p_pet':c.pet,'p_name':'Owned family alias fixture'}
 check('guest-alias-denied',rpc('set_family_name',args,None),(401,403));check('outsider-alias-denied',rpc('set_family_name',args,'outsider'),(403,))
 check('overlong-alias-rejected',rpc('set_family_name',{**args,'p_name':'x'*41}),(400,));check('foreign-user-parameter-not-supported',rpc('set_family_name',{**args,'p_user':family}),(404,))
 check('owner-selects-private-alias',rpc('set_family_name',args));check('family-selects-own-alias',rpc('set_family_name',{**args,'p_name':'Owned provider alias fixture'},'family'))
 owner=next(p['id'] for p in c.people if p['role']=='owner')
 check('family-names-visible-only-in-members',rpc('members',{'p_pet':c.pet},'family'),predicate=lambda rows:any(p['id']==owner and p['display_name']==args['p_name'] for p in rows) and any(p['id']==family and p['display_name']=='Owned provider alias fixture' for p in rows))
 check('outsider-member-list-denied',rpc('members',{'p_pet':c.pet},'outsider'),(403,))
 check('private-activity-no-email-no-full-actor-id',rpc('family_activity',{'p_pet':c.pet},'family'),predicate=lambda rows:all(set(p)=={'id','action','mine','created_at','actor_name'} for p in rows) and any(p['mine'] and p['actor_name']=='Owned provider alias fixture' for p in rows))
 check('outsider-activity-denied',rpc('family_activity',{'p_pet':c.pet},'outsider'),(403,))
 check('album-provider-name-only',rpc('album',{'p_pet':c.pet}),predicate=lambda rows:all('provider_name' in p and 'provider_id' not in p and 'email' not in p for p in rows))
 check('clear-family-private-name',rpc('set_family_name',{**args,'p_name':''},'family'))
 check('cleared-name-default',rpc('members',{'p_pet':c.pet}),predicate=lambda rows:any(p['id']==family and p['display_name']=='家族メンバー' for p in rows))
 check('family-exit',rpc('remove_member',{'p_pet':c.pet,'p_user':family},'family'));joined=False
 check('exited-alias-change-denied',rpc('set_family_name',args,'family'),(403,));check('exited-activity-denied',rpc('family_activity',{'p_pet':c.pet},'family'),(403,))
 check('exited-notifications-omit-pet',rpc('family_notifications',role='family'),predicate=lambda rows:all(p['pet_id']!=c.pet for p in rows))
 outcome={'passed':True,'checks':c.checks}
except Exception as e:outcome={'passed':False,'failure':str(e),'checks':c.checks}
finally:
 rpc('set_family_name',{'p_pet':c.pet,'p_name':next((v for k,v in names.items() if k==next(p['id'] for p in c.people if p['role']=='owner') and v not in ('あなた','家族メンバー')),'')})
 if joined:rpc('set_family_name',{'p_pet':c.pet,'p_name':''},'family');rpc('remove_member',{'p_pet':c.pet,'p_user':family})
 # Existing test family membership is restored if this test temporarily removed it.
 if family in names:
  invite=rpc('invite',{'p_pet':c.pet})[1];rpc('accept_invite',{'p_token':invite['token'],'p_confirm_scope':True},'family');rpc('set_family_name',{'p_pet':c.pet,'p_name':names[family]},'family')
(ROOT/'docs/evidence/p1-family-names-server.json').write_text(json.dumps(outcome,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'passed':outcome['passed'],'checks':len(c.checks),'failure':outcome.get('failure')}));raise SystemExit(0 if outcome['passed'] else 1)
