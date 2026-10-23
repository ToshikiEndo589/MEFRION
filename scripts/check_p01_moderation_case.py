"""Verify notices and appeals for this task's reserved synthetic case only."""
import sys,json,urllib.request,urllib.error
from pathlib import Path
from uuid import uuid4
from p1_test_support import DevelopmentClient,ROOT
c=DevelopmentClient();c.login();f=json.loads((ROOT/'.local/p01-moderation-case.json').read_text());u=f['target'];assert u['email'].startswith('mefrion-test-moderation-case-') and u['email'].endswith('@example.invalid')
x=c.check('target-login',c.call('/auth/v1/token?grant_type=password',{'email':u['email'],'password':u['password']}));c.tokens['target']=x['access_token'];c.check('target-identity',c.call('/auth/v1/user',role='target'),predicate=lambda v:v['id']==u['id'] and v['user_metadata']['test_only'])
rows=c.check('own-moderation-notices',c.rpc('my_moderation',role='target'));row=next(v for v in rows if v['id']==f['report']);assert 'P01 owned moderation' not in json.dumps(rows) and 'reporter' not in json.dumps(rows)
mode=sys.argv[1]
if mode=='appeal':
 assert row['decision']=='suspend_account';c.check('suspended-user-comment-denied',c.rpc('comment',{'p_post':f['post'],'p_body':'Cannot comment while suspended','p_parent':None,'p_alias_pet':None,'p_request_key':str(uuid4())},'target'),(403,))
 c.check('submit-own-appeal',c.rpc('appeal',{'p_report':f['report'],'p_note':'P01 synthetic appeal after browser suspension'},'target'))
 c.check('ordinary-owner-claim-denied',c.rpc('operator_claim',{'p_report':f['report'],'p_version':1,'p_claim':True}),(403,))
 c.check('anonymous-claim-denied',c.rpc('operator_claim',{'p_report':f['report'],'p_version':1,'p_claim':True},None),(401,403))
else:
 assert row['decision']=='restore_account';comments=c.check('visible-comments-after-restore',c.rpc('comments',{'p_post':f['post']},'owner'));assert not any(v['id']==f['comment'] for v in comments)
result={'passed':True,'mode':mode,'checks':c.checks,'scope':'reserved synthetic user and this task report only','internal_reason_and_reporter_absent':True};(ROOT/f'docs/evidence/p01-moderation-{mode}.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps({'passed':True,'checks':len(c.checks),'mode':mode}))
