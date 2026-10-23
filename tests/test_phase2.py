import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from backend.family import FamilyStore
from backend.domain import DomainError

A,B,C='demo-owner','demo-family','demo-outsider'

class FamilyTests(unittest.TestCase):
    def setUp(self):
        self.s=FamilyStore(); self.pet=self.s.create_pet(A,'こむぎ','dog')['id']
        self.invite=self.s.invite(A,self.pet)
    def tearDown(self): self.s.db.close()
    def join(self): self.s.accept(B,self.invite['token'],True)
    def add(self,actor,key):
        return self.s.add_photos(actor,self.pet,[{'asset':'pet-0' if actor==A else 'pet-1','request_key':key,'captured':'2020'}])[0]['id']
    def test_authenticated_explicit_single_use_invitation(self):
        with self.assertRaises(DomainError): self.s.accept(None,self.invite['token'],True)
        with self.assertRaises(DomainError): self.s.accept(B,self.invite['token'],False)
        self.join()
        with self.assertRaises(DomainError): self.s.accept(C,self.invite['token'],True)
        with self.assertRaises(DomainError): self.s.invite(B,self.pet)
        stored=self.s.db.execute('SELECT token_hash FROM invitations').fetchone()[0]
        self.assertNotEqual(stored,self.invite['token'])
    def test_expiry_and_cancel(self):
        with self.s.db: self.s.db.execute('UPDATE invitations SET expires=0')
        with self.assertRaises(DomainError): self.join()
        new=self.s.invite(A,self.pet); self.s.cancel_invite(A,new['id'])
        with self.assertRaises(DomainError): self.s.accept(B,new['token'],True)
    def test_private_shared_album_and_unrelated_actor(self):
        self.join(); photo=self.add(B,'family-photo')
        self.assertEqual(self.s.album(A,self.pet)[0]['id'],photo)
        self.assertEqual(self.s.album(B,self.pet)[0]['provider'],B)
        for actor in (C,None,'local-operator'):
            with self.assertRaises(DomainError): self.s.photo(actor,photo)
            with self.assertRaises(DomainError): self.s.album(actor,self.pet)
    def test_provider_edit_and_owner_management(self):
        self.join(); owner=self.add(A,'owner'); family=self.add(B,'family')
        with self.assertRaises(DomainError): self.s.edit_photo(B,owner,'2021')
        with self.assertRaises(DomainError): self.s.delete_photo(B,self.pet,owner)
        self.s.edit_photo(B,family,'2022'); self.s.edit_photo(A,family,'2023')
        self.s.delete_photo(A,self.pet,family)
        self.assertEqual(len(self.s.album(A,self.pet)),1)
    def test_separate_purpose_consent_and_provider_only(self):
        self.join(); photo=self.add(B,'family')
        self.assertFalse(self.s.consent_allowed(photo,'sns'))
        with self.assertRaises(DomainError): self.s.consent(A,photo,'sns',True)
        self.s.consent(B,photo,'sns',True)
        self.assertTrue(self.s.consent_allowed(photo,'sns'))
        self.assertFalse(self.s.consent_allowed(photo,'twins'))
        self.assertFalse(self.s.consent_allowed(photo,'external_share'))
        self.s.consent(B,photo,'sns',False)
        self.assertFalse(self.s.consent_allowed(photo,'sns'))
    def test_immediate_revocation_on_all_private_reads(self):
        self.join(); photo=self.add(B,'family')
        self.s.consent(B,photo,'sns',True)
        self.s.remove_member(A,self.pet,B)
        for action in (lambda:self.s.album(B,self.pet),lambda:self.s.photo(B,photo),lambda:self.s.notifications(B,self.pet),lambda:self.add(B,'retry')):
            with self.assertRaises(DomainError): action()
        self.assertEqual(self.s.list_pets(B),[])
        self.assertTrue(self.s.request_removal(B,photo)['requested'])
        self.s.consent(B,photo,'sns',False) # Revocation remains possible after exit.
        self.assertFalse(self.s.consent_allowed(photo,'sns'))
        with self.assertRaises(DomainError): self.s.consent(B,photo,'sns',True)
    def test_notifications_only_current_family_and_off_setting(self):
        self.join(); self.add(A,'notice')
        self.assertEqual(len(self.s.notifications(B,self.pet)),1)
        self.s.notification_frequency(B,self.pet,'off')
        self.assertEqual(self.s.notifications(B,self.pet),[])
        with self.assertRaises(DomainError): self.s.notification_frequency(C,self.pet,'immediate')
        with self.assertRaises(DomainError): self.s.remove_member(B,self.pet,A)
    def test_concurrent_acceptance_across_database_connections(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'db'; left=FamilyStore(path); right=FamilyStore(path)
            try:
                pet=left.create_pet(A,'こむぎ','dog')['id']; invite=left.invite(A,pet)
                def attempt(store,actor):
                    try: store.accept(actor,invite['token'],True); return True
                    except DomainError: return False
                with ThreadPoolExecutor(max_workers=2) as pool:
                    results=list(pool.map(lambda pair:attempt(*pair),[(left,B),(right,C)]))
                self.assertEqual(sum(results),1)
                self.assertEqual(left.db.execute('SELECT count(*) FROM members').fetchone()[0],1)
            finally: left.db.close();right.db.close()
