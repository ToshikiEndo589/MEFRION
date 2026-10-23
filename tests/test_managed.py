import os
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from backend.domain import DomainError
from backend.managed import ManagedStore

class ManagedTests(unittest.TestCase):
    def test_moderator_review_roles_idempotency_and_cross_pet_suspension(self):
        s=self.s
        report=s.report('demo-owner','demo-post-demo-0','rights')['id']
        for actor in ('demo-owner','demo-editor','demo-approver','demo-distributor'):
            with self.assertRaises(DomainError):s.reports_for_review(actor)
            with self.assertRaises(DomainError):s.review_report(actor,report,'hide_post','Synthetic review')
        with self.assertRaises(DomainError):s.review_report('demo-moderator',report,'hide_post','')
        s.review_report('demo-moderator',report,'hide_post','Synthetic review')
        with self.assertRaises(DomainError):s.public_post('demo-post-demo-0')
        s.public_post('demo-post-demo-1')
        before=len(s.audit_log('demo-moderator'))
        s.review_report('demo-moderator',report,'hide_post','Synthetic review')
        self.assertEqual(len(s.audit_log('demo-moderator')),before)
        with self.assertRaises(DomainError):s.review_report('demo-moderator',report,'dismiss','Changed decision')
        second=s.report('demo-owner','demo-post-demo-1','abuse')['id']
        s.react('demo-owner','demo-post-demo-2','save',True)
        s.review_report('demo-moderator',second,'suspend_account','Synthetic publisher suspension')
        self.assertEqual(s.search(''),[]);self.assertEqual(s.feed(),[]);self.assertEqual(s.saved('demo-owner'),[])
        self.assertTrue(all(row['state']=='cancelled' for row in s.admin_posts('demo-moderator')))
        self.assertEqual(s.reports_for_review('demo-moderator')[0]['decision'],'suspend_account')
        self.assertFalse(any('actor' in row for row in s.reports_for_review('demo-moderator')))
        with self.assertRaises(DomainError):s.create_managed('demo-editor',[{'id':'bypass','name':'Synthetic','species':'dog','asset':'pet-0'}],'after-suspension')
        self.assertTrue(any(row['action']=='operator.denied' for row in s.audit_log('demo-moderator')))

    def test_expired_managed_rights_hide_search_and_species_edit_is_checked(self):
        s=self.s
        s.db.execute("UPDATE managed_assets SET expires=? WHERE pet='demo-0'",(time.time()-1,));s.db.commit()
        self.assertNotIn('demo-0',[row['id'] for row in s.search('')])
        with self.assertRaises(DomainError):s.edit_managed('demo-editor','demo-0',1,'Updated','cat')

    def test_suspended_user_cannot_repost_with_another_pet(self):
        s=self.s
        pet=s.create_pet('demo-owner','Synthetic user','dog')['id']
        photo=s.add_photos('demo-owner',pet,[{'asset':'pet-0','captured':None,'request_key':'moderation-test'}])[0]['id']
        s.consent('demo-owner',photo,'sns',True);s.set_pet_public('demo-owner',pet,True,True)
        post=s.publish('demo-owner',pet,[photo],explicit=True)['id']
        report=s.report('demo-family',post,'abuse')['id']
        s.review_report('demo-moderator',report,'suspend_account','Synthetic account suspension')
        with self.assertRaises(DomainError):s.create_pet('demo-owner','Another pet','dog')
        with self.assertRaises(DomainError):s.publish('demo-owner',pet,[photo],explicit=True)
        with self.assertRaises(DomainError):s.react('demo-owner','demo-post-demo-1','like',True)
        s.consent('demo-owner',photo,'sns',False)
        s.set_pet_public('demo-owner',pet,False)
        s.delete_photo('demo-owner',pet,photo)
    def setUp(self):self.s=ManagedStore()
    def tearDown(self):self.s.db.close()
    def make(self,pid='ops-one'):
        self.s.create_managed('demo-editor',[{'id':pid,'name':'開発イラスト','species':'dog','asset':'pet-0'}],pid)
        material=next(p for p in self.s.list_managed('demo-editor') if p['pet']==pid)['materials'][0]['id']
        return pid,material
    def draft(self):
        pet,asset=self.make()
        return self.s.draft('demo-editor',pet,'人工イラストの試験',[asset]),asset
    def approve(self):
        d,a=self.draft()
        self.s.register_rights('demo-approver',a,'MEFRION test fixture','sns',None,'test-evidence')
        return self.s.approve('demo-approver',d['id'],1),a
    def test_bulk_preview_idempotency_and_no_user_identity(self):
        rows=[{'id':'bulk-'+str(i),'name':'合成Pet'+str(i),'species':'dog','asset':'pet-0'} for i in range(8)]
        self.assertTrue(all(r['valid'] for r in self.s.preview_profiles('demo-editor',rows)))
        first=self.s.create_managed('demo-editor',rows,'bulk')
        self.assertEqual(self.s.create_managed('demo-editor',rows,'bulk'),first)
        self.assertEqual(len(first['created']),8)
        self.assertEqual(self.s.list_pets('demo-owner'),[])
        self.assertEqual(len(self.s.list_managed('demo-editor')),18)
        self.assertEqual(self.s.db.execute('SELECT count(*) FROM operators').fetchone()[0],4)
        self.assertEqual(len(self.s.feed()),10)
        rows[0]['name']='changed'
        with self.assertRaisesRegex(DomainError,'idempotency_conflict'):self.s.create_managed('demo-editor',rows,'bulk')
        preview=self.s.preview_csv('demo-editor','id,name,species,asset\nx,犬,dog,pet-0\nx,重複,cat,pet-1\ny,鳥,bird,pet-3\n')
        self.assertEqual([r['valid'] for r in preview],[True,False,False])
    def test_roles_revocation_keeps_profiles_and_private_deny(self):
        for actor in [None,'demo-owner','demo-family','demo-outsider']:
            with self.assertRaises(DomainError):self.s.list_managed(actor)
        d,a=self.draft()
        for actor in ['demo-editor','demo-distributor']:
            with self.assertRaises(DomainError):self.s.approve(actor,d['id'],1)
        with self.assertRaises(DomainError):self.s.album('demo-editor',d['pet'])
        with self.s.db:self.s.db.execute("UPDATE operators SET active=0 WHERE id='demo-editor'")
        with self.assertRaises(DomainError):self.s.list_managed('demo-editor')
        self.assertEqual(len(self.s.list_managed('demo-approver')),11)
    def test_rights_required_and_private_projection(self):
        d,a=self.draft()
        with self.assertRaisesRegex(DomainError,'rights_required'):self.s.approve('demo-approver',d['id'],1)
        self.s.register_rights('demo-approver',a,'PRIVATE RIGHTS HOLDER','sns',None,'PRIVATE EVIDENCE')
        self.s.approve('demo-approver',d['id'],1)
        with self.assertRaisesRegex(DomainError,'explicit_publish_required'):self.s.distribute('demo-distributor',d['id'],1)
        result=self.s.distribute('demo-distributor',d['id'],1,explicit=True)
        public=self.s.public_post(result['post_id'])
        self.assertEqual(public['likes'],0);self.assertEqual(public['comments'],0)
        for word in ['PRIVATE','demo-editor','demo-approver','demo-publisher',a]:self.assertNotIn(word,str(public))
        audit=self.s.audit_log('demo-approver')
        self.assertEqual(audit[0]['operator_user_id'],'demo-distributor')
        self.assertEqual(audit[0]['approver'],'demo-approver')
    def test_reedit_invalidates_approval_and_optimistic_conflict(self):
        d,a=self.approve()
        self.s.draft('demo-editor',d['pet'],'修正',[a],d['id'],1)
        with self.assertRaisesRegex(DomainError,'revision_conflict'):self.s.draft('demo-editor',d['pet'],'古い修正',[a],d['id'],1)
        with self.assertRaisesRegex(DomainError,'approval_required'):self.s.distribute('demo-distributor',d['id'],2,explicit=True)
        self.s.edit_managed('demo-editor',d['pet'],1,'編集済み','dog')
        with self.assertRaisesRegex(DomainError,'revision_conflict'):self.s.edit_managed('demo-editor',d['pet'],1,'古い編集','dog')
    def test_schedule_cancel_and_rights_expiration_all_reads(self):
        d,a=self.approve();future=time.time()+100
        self.s.register_rights('demo-approver',a,'test','sns',time.time()+50,'evidence')
        with self.assertRaisesRegex(DomainError,'rights_expire_before_schedule'):self.s.distribute('demo-distributor',d['id'],1,future,True)
        with self.assertRaisesRegex(DomainError,'future_schedule_required'):self.s.distribute('demo-distributor',d['id'],1,time.time()-1,True)
        self.s.register_rights('demo-approver',a,'test','sns',None,'evidence')
        self.s.distribute('demo-distributor',d['id'],1,future,True)
        self.s.cancel('demo-distributor',d['id'])
        self.assertEqual(self.s.dispatch_due('demo-distributor',future+1)['results'],[])
        self.assertFalse(self.s.db.execute('SELECT public FROM pets WHERE id=?',(d['pet'],)).fetchone()[0])
        # A new approval is required after cancellation.
        self.s.draft('demo-editor',d['pet'],'retry',[a],d['id'],1)
        self.s.approve('demo-approver',d['id'],2)
        post=self.s.distribute('demo-distributor',d['id'],2,explicit=True)['post_id']
        self.s.react('demo-owner',post,'save',True)
        with self.s.db:self.s.db.execute('UPDATE managed_assets SET expires=? WHERE id=?',(time.time()-1,a))
        with self.assertRaisesRegex(DomainError,'not_found'):self.s.public_post(post)
        self.assertNotIn(post,[p['id'] for p in self.s.feed()])
        self.assertEqual(self.s.saved('demo-owner'),[])
    def test_rights_revocation_bulk_stop_never_revive(self):
        d,a=self.approve();post=self.s.distribute('demo-distributor',d['id'],1,explicit=True)['post_id']
        self.s.revoke_rights('demo-approver',a)
        self.s.register_rights('demo-approver',a,'test','sns',None,'evidence')
        with self.assertRaises(DomainError):self.s.public_post(post)
        self.s.stop_profiles('demo-distributor',['demo-0','demo-1'])
        self.assertEqual(len(self.s.feed()),8)
        self.assertFalse(any(p['id']=='demo-0' for p in self.s.search('')))
        with self.assertRaises(DomainError):self.s.public_post('demo-post-demo-0')
    def test_concurrent_workers_across_connections_deliver_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=os.path.join(tmp,'db.sqlite');s1=ManagedStore(path)
            rows=[{'id':'parallel','name':'合成試験','species':'cat','asset':'pet-1'}]
            s1.create_managed('demo-editor',rows,'one');a=s1.list_managed('demo-editor')[-1]['materials'][0]['id']
            s1.register_rights('demo-approver',a,'test','sns',None,'evidence')
            d=s1.draft('demo-editor','parallel','人工イラスト',[a]);s1.approve('demo-approver',d['id'],1)
            due=time.time()+10;s1.distribute('demo-distributor',d['id'],1,due,True)
            s2=ManagedStore(path)
            with ThreadPoolExecutor(max_workers=2) as pool:
                outcomes=list(pool.map(lambda s:s.dispatch_due('demo-distributor',due+1),[s1,s2]))
            self.assertEqual(sum(len(r['results']) for r in outcomes),1)
            self.assertEqual(s1.db.execute("SELECT count(*) FROM public_posts WHERE pet='parallel'").fetchone()[0],1)
            post=s1.editorial(d['id'])['public_post']
            self.assertTrue(s1.distribute('demo-distributor',d['id'],1,explicit=True)['already_published'])
            self.assertEqual(s1.editorial(d['id'])['public_post'],post)
            s1.db.close();s2.db.close()
