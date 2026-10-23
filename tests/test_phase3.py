import unittest
from backend.social import SocialStore
from backend.domain import DomainError
A,B,C='demo-owner','demo-family','demo-outsider'

class SocialTests(unittest.TestCase):
    def setUp(self):
        self.s=SocialStore(); self.pet=self.s.create_pet(A,'非公開こむぎ','dog')['id']
        invite=self.s.invite(A,self.pet); self.s.accept(B,invite['token'],True)
        self.ids=[r['id'] for r in self.s.add_photos(B,self.pet,[{'asset':'pet-0','request_key':'1','captured':'2020'},{'asset':'pet-1','request_key':'2','captured':None}])]
    def tearDown(self): self.s.db.close()
    def publish(self):
        self.s.set_pet_public(A,self.pet,True,True)
        for pid in self.ids: self.s.consent(B,pid,'sns',True)
        return self.s.publish(A,self.pet,self.ids,'家族提供のテスト画像',explicit=True)['id']
    def test_seed_feed_zero_real_users_common_projection(self):
        posts=self.s.feed(); self.assertEqual(len(posts),10)
        for p in posts:
            self.assertEqual((p['likes'],p['comments']),(0,0))
            self.assertEqual(p['kind'],'post'); self.assertEqual(len(p['images']),1)
            for key in ('owner','provider','origin','rights','publisher_id','photo_ids'): self.assertNotIn(key,p)
        self.assertEqual(self.s.feed(A,following=True),[])
    def test_owner_publish_explicit_pet_and_provider_consent(self):
        self.assertEqual(self.s.search('非公開'),[])
        with self.assertRaises(DomainError): self.s.publish(A,self.pet,self.ids,explicit=True)
        with self.assertRaises(DomainError): self.s.set_pet_public(A,self.pet,True)
        self.s.set_pet_public(A,self.pet,True,True)
        with self.assertRaises(DomainError): self.s.publish(A,self.pet,self.ids,explicit=True)
        for pid in self.ids: self.s.consent(B,pid,'sns',True)
        with self.assertRaises(DomainError): self.s.publish(B,self.pet,self.ids,explicit=True)
        with self.assertRaises(DomainError): self.s.publish(A,self.pet,self.ids,explicit=False)
        post=self.s.publish(A,self.pet,self.ids,explicit=True)
        self.assertNotIn('provider',str(post))
    def test_consent_withdrawal_hides_all_projections_and_never_revives(self):
        post=self.publish(); self.s.react(C,post,'save',True)
        self.s.comment(C,post,'test')
        self.s.consent(B,self.ids[0],'sns',False)
        for read in (lambda:self.s.public_post(post),lambda:self.s.public_comments(post)):
            with self.assertRaises(DomainError): read()
        self.assertEqual(self.s.saved(C),[])
        self.assertNotIn(post,[p['id'] for p in self.s.feed()])
        self.s.consent(B,self.ids[0],'sns',True)
        with self.assertRaises(DomainError): self.s.public_post(post)
    def test_external_share_separate_consent_and_delete_cascade(self):
        self.publish()
        with self.assertRaises(DomainError): self.s.publish(A,self.pet,self.ids,kind='share',explicit=True)
        for pid in self.ids: self.s.consent(B,pid,'external_share',True)
        shared=self.s.publish(A,self.pet,self.ids,kind='share',explicit=True)['id']
        self.s.consent(B,self.ids[0],'sns',False)
        self.assertEqual(self.s.public_post(shared)['kind'],'share')
        self.s.delete_photo(A,self.pet,self.ids[0])
        with self.assertRaises(DomainError): self.s.public_post(shared)
    def test_reactions_follow_saved_comments_and_one_reply_depth(self):
        post=self.publish()
        self.s.react(C,post,'like',True);self.s.react(C,post,'like',True)
        self.assertEqual(self.s.public_post(post)['likes'],1)
        self.s.react(C,post,'like',False);self.assertEqual(self.s.public_post(post)['likes'],0)
        self.s.follow(C,self.pet,True);self.assertEqual(len(self.s.feed(C,True)),1)
        self.s.react(C,post,'save',True);self.assertEqual(len(self.s.saved(C)),1)
        parent=self.s.comment(C,post,'親')['id'];reply=self.s.comment(B,post,'返信',parent)['id']
        with self.assertRaises(DomainError): self.s.comment(A,post,'深すぎる返信',reply)
        self.s.withdraw(A,post);self.assertEqual(self.s.saved(C),[])
    def test_block_human_account_all_pet_names(self):
        first=self.publish(); second=self.s.create_pet(A,'別のPet','cat')['id']
        self.s.set_pet_public(A,second,True,True)
        photo=self.s.add_photos(A,second,[{'asset':'pet-2','request_key':'x','captured':None}])[0]['id']
        self.s.consent(A,photo,'sns',True)
        other=self.s.publish(A,second,[photo],explicit=True)['id']
        self.s.block_pet_owner(C,self.pet)
        for post in (first,other):
            with self.assertRaises(DomainError): self.s.public_post(post,C)
            with self.assertRaises(DomainError): self.s.react(C,post,'like',True)
        self.assertEqual(self.s.search('Pet',C),[])
    def test_report_and_pet_visibility_revocation(self):
        post=self.publish();self.assertTrue(self.s.report(C,post,'privacy')['received'])
        with self.assertRaises(DomainError): self.s.report(None,post,'privacy')
        self.s.set_pet_public(A,self.pet,False)
        self.assertEqual(self.s.search('非公開'),[])
        self.s.set_pet_public(A,self.pet,True,True)
        with self.assertRaises(DomainError): self.s.public_post(post)
    def test_image_and_body_limits(self):
        self.publish()
        for images,body in ((self.ids*3,''),(self.ids,'x'*501),([],'')):
            with self.assertRaises(DomainError): self.s.publish(A,self.pet,images,body,explicit=True)
