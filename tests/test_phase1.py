import tempfile
import unittest
from pathlib import Path
from backend.domain import Store, DomainError, valid_date

class PhaseOneTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.s=Store(str(Path(self.tmp.name)/'test.sqlite'))
        self.pet=self.s.create_pet('demo-owner','こむぎ','dog')['id']
    def tearDown(self):
        self.s.db.close(); self.tmp.cleanup()
    def add(self,asset='pet-0',captured=None,key='one',**kw):
        return self.s.add_photos('demo-owner',self.pet,[dict(asset=asset,captured=captured,request_key=key,**kw)])[0]
    def test_pet_zero_photos_private_duplicate_names(self):
        self.assertEqual(self.s.album('demo-owner',self.pet),[])
        self.assertEqual(self.s.pet('demo-owner',self.pet)['public'],0)
        self.s.create_pet('demo-owner','こむぎ','cat')
    def test_date_precision_and_invalid_dates(self):
        for v,p in [(None,'unknown'),('2020','year'),('2020-02','month'),('2020-02-29','day')]: self.assertEqual(valid_date(v),p)
        for v in ['2021-02-29','2020-13','0000','yesterday','2020-1',False]:
            with self.assertRaises(DomainError): valid_date(v)
    def test_old_photo_insert_unknown_last_no_fake_day(self):
        self.add('pet-0','2025-01-01','new');self.add('pet-1',None,'unknown');self.add('pet-2','2020','old')
        a=self.s.album('demo-owner',self.pet)
        self.assertEqual([p['captured'] for p in a],['2020','2025-01-01',None])
        self.assertEqual(a[0]['precision'],'year')
    def test_partial_failure_retry_idempotency(self):
        batch=[dict(asset='pet-0',captured='2020',request_key='ok'),dict(asset='pet-1',captured='2020-13',request_key='bad')]
        r=self.s.add_photos('demo-owner',self.pet,batch)
        self.assertEqual([p['status'] for p in r],['saved','failed'])
        batch[1]['captured']='2020-12'
        r=self.s.add_photos('demo-owner',self.pet,batch)
        self.assertEqual([p['status'] for p in r],['already_saved','saved'])
        self.assertEqual(len(self.s.album('demo-owner',self.pet)),2)
    def test_thirty_item_batch_one_failure_retry_only_failure(self):
        batch=[dict(asset=f'pet-{i%10}',captured='2020',request_key=str(i),allow_duplicate=True) for i in range(30)]
        batch[12]['captured']='2020-99'
        result=self.s.add_photos('demo-owner',self.pet,batch)
        self.assertEqual(sum(r['status']=='saved' for r in result),29)
        batch[12]['captured']=None
        result=self.s.add_photos('demo-owner',self.pet,[batch[12]])
        self.assertEqual(result[0]['status'],'saved')
        self.assertEqual(len(self.s.album('demo-owner',self.pet)),30)
        result=self.s.add_photos('demo-owner',self.pet,batch)
        self.assertTrue(all(r['status']=='already_saved' for r in result))
        self.assertEqual(len(self.s.album('demo-owner',self.pet)),30)

    def test_idempotency_conflict(self):
        self.add(); self.assertEqual(self.add(captured='2020')['error'],'idempotency_conflict')
    def test_duplicate_needs_human_confirmation(self):
        self.add();self.assertEqual(self.add(key='two')['error'],'duplicate_confirmation_required')
        self.assertEqual(self.add(key='two',allow_duplicate=True)['status'],'saved')
    def test_limit_preserves_existing(self):
        self.add()
        with self.assertRaises(DomainError): self.s.add_photos('demo-owner',self.pet,[{}]*31)
        self.assertEqual(len(self.s.album('demo-owner',self.pet)),1)
    def test_unrelated_and_guest_cannot_read_or_mutate(self):
        photo=self.add()['id']
        for actor in [None,'demo-outsider','demo-family','operator']:
            for fn in [lambda:self.s.album(actor,self.pet),lambda:self.s.delete_photo(actor,self.pet,photo)]:
                with self.assertRaises(DomainError): fn()
        self.assertEqual(len(self.s.album('demo-owner',self.pet)),1)
    def test_card_private_two_distinct_same_pet(self):
        a=self.add()['id']; b=self.add('pet-1',key='two')['id']
        c=self.s.make_card('demo-owner',self.pet,[a,b]);self.assertFalse(c['public']);self.assertEqual(c['aspect'],'9:16')
        for ids in [[a,a],[a], [a,'other']]:
            with self.assertRaises(DomainError): self.s.make_card('demo-owner',self.pet,ids)
    def test_photo_delete_cascades_private_card(self):
        a=self.add()['id'];b=self.add('pet-1',key='two')['id']
        self.s.make_card('demo-owner',self.pet,[a,b]);self.s.delete_photo('demo-owner',self.pet,a)
        self.assertEqual(self.s.db.execute('SELECT count(*) FROM cards').fetchone()[0],0)
    def test_fixture_twins_cap_species_and_exclusion(self):
        for species in ['dog','cat']:
            r=self.s.twins(species,exclude='demo-0')
            self.assertLessEqual(len(r['candidates']),3)
            self.assertTrue(all(p['species']==species and p['id']!='demo-0' for p in r['candidates']))
            self.assertNotIn('percentage',str(r))
            self.assertEqual(r['external_cost_yen'],0)
    def test_twins_failure_insufficient_poor_are_separate(self):
        for status in ['failure','insufficient','poor_photo']:
            r=self.s.twins('dog',status);self.assertEqual(r['status'],status);self.assertEqual(r['candidates'],[])
        for m in self.s.metrics:
            self.assertEqual(set(m),{'event','result','duration_ms','external_cost_yen'})
    def test_feedback_only_allowed_values(self):
        self.assertTrue(self.s.feedback('similar')['recorded'])
        with self.assertRaises(DomainError): self.s.feedback('secret user text')
    def test_persist_reopen(self):
        self.add(); dbpath=self.s.db.execute('PRAGMA database_list').fetchone()['file']
        other=Store(dbpath)
        try: self.assertEqual(len(other.album('demo-owner',self.pet)),1)
        finally:other.db.close()
