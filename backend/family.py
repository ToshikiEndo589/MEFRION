"""Phase 2 executable authorization reference; FIXED DEMO AUTH, fixture media only.

No real OAuth, uploads, email, or public storage. The same policy is exercised by
API tests before an approved managed-auth/storage project is connected.
"""
import hashlib
import secrets
import threading
import time
from uuid import uuid4
from .domain import Store, DomainError, POLICY, valid_date

class FamilyStore(Store):
    def __init__(self, path=':memory:'):
        super().__init__(path)
        self.lock = threading.RLock()
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS members(pet TEXT REFERENCES pets(id), actor TEXT, active INTEGER DEFAULT 1, frequency TEXT DEFAULT 'batched', PRIMARY KEY(pet,actor));
        CREATE TABLE IF NOT EXISTS invitations(id TEXT PRIMARY KEY, pet TEXT REFERENCES pets(id), token_hash TEXT UNIQUE, expires REAL, state TEXT NOT NULL DEFAULT 'pending');
        CREATE TABLE IF NOT EXISTS consents(photo TEXT REFERENCES photos(id) ON DELETE CASCADE, purpose TEXT, provider TEXT, allowed INTEGER, version INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(photo,purpose));
        CREATE TABLE IF NOT EXISTS notices(id TEXT PRIMARY KEY, pet TEXT REFERENCES pets(id), photo TEXT REFERENCES photos(id) ON DELETE CASCADE, actor TEXT, created REAL);
        CREATE TABLE IF NOT EXISTS removal_requests(id TEXT PRIMARY KEY, photo TEXT, provider TEXT, created REAL);
        ''')

    def owner(self, actor, pet_id):
        self.require_actor(actor)
        p=self.db.execute('SELECT * FROM pets WHERE id=? AND owner=?',(pet_id,actor)).fetchone()
        if not p: raise DomainError('not_found',404)
        return dict(p)

    def pet(self, actor, pet_id, write=False):
        self.require_actor(actor)
        p=self.db.execute('SELECT * FROM pets WHERE id=?',(pet_id,)).fetchone()
        if not p: raise DomainError('not_found',404)
        member=self.db.execute('SELECT 1 FROM members WHERE pet=? AND actor=? AND active=1',(pet_id,actor)).fetchone()
        if p['owner']!=actor and not member: raise DomainError('not_found',404)
        return dict(p)

    def list_pets(self, actor):
        self.require_actor(actor)
        return [dict(p) for p in self.db.execute('SELECT p.* FROM pets p WHERE p.owner=? OR EXISTS(SELECT 1 FROM members m WHERE m.pet=p.id AND m.actor=? AND m.active=1)',(actor,actor))]

    def invite(self, actor, pet_id):
        self.owner(actor,pet_id)
        with self.lock, self.db:
            pending=self.db.execute("SELECT count(*) FROM invitations WHERE pet=? AND state='pending' AND expires>?",(pet_id,time.time())).fetchone()[0]
            if pending >= POLICY['provisional']['pending_invitations']: raise DomainError('invitation_limit',409)
            token=secrets.token_urlsafe(32); iid=str(uuid4())
            expires=time.time()+POLICY['provisional']['invite_days']*86400
            self.db.execute('INSERT INTO invitations(id,pet,token_hash,expires) VALUES(?,?,?,?)',(iid,pet_id,self.digest(token),expires))
        # Raw token returned once, never stored or logged. Local tests do not email it.
        return {'id':iid,'token':token,'expires':expires,'pet_id':pet_id}

    @staticmethod
    def digest(token):
        if not isinstance(token,str) or not 20 <= len(token) <= 200: raise DomainError('invalid_invitation',404)
        return hashlib.sha256(token.encode()).hexdigest()

    def accept(self, actor, token, confirm_scope=False):
        self.require_actor(actor)
        if confirm_scope is not True: raise DomainError('scope_confirmation_required')
        with self.lock, self.db:
            self.db.execute('BEGIN IMMEDIATE')
            row=self.db.execute('SELECT * FROM invitations WHERE token_hash=?',(self.digest(token),)).fetchone()
            if not row or row['state']!='pending' or row['expires']<=time.time(): raise DomainError('invalid_invitation',404)
            p=self.db.execute('SELECT * FROM pets WHERE id=?',(row['pet'],)).fetchone()
            if p['owner']==actor: raise DomainError('already_owner',409)
            if self.db.execute('SELECT 1 FROM members WHERE pet=? AND actor=? AND active=1',(p['id'],actor)).fetchone(): raise DomainError('already_member',409)
            self.db.execute("UPDATE invitations SET state='accepted' WHERE id=?",(row['id'],))
            self.db.execute("INSERT INTO members(pet,actor,active) VALUES(?,?,1) ON CONFLICT(pet,actor) DO UPDATE SET active=1",(p['id'],actor))
        return {'pet_id':p['id'],'role':'family','external_publish':False}

    def cancel_invite(self, actor, iid):
        row=self.db.execute('SELECT * FROM invitations WHERE id=?',(iid,)).fetchone()
        if not row: raise DomainError('not_found',404)
        self.owner(actor,row['pet'])
        with self.db: self.db.execute("UPDATE invitations SET state='revoked' WHERE id=?",(iid,))
        return {'revoked':True}

    def remove_member(self, actor, pet_id, member):
        self.pet(actor,pet_id)
        if actor!=member: self.owner(actor,pet_id)
        if self.db.execute('SELECT owner FROM pets WHERE id=?',(pet_id,)).fetchone()[0]==member: raise DomainError('owner_cannot_leave')
        with self.db: self.db.execute('UPDATE members SET active=0 WHERE pet=? AND actor=?',(pet_id,member))
        return {'access_revoked':True,'provided_photos':'retained_private; provider can request removal'}

    def photo(self, actor, photo_id, edit=False):
        self.require_actor(actor)
        row=self.db.execute('SELECT * FROM photos WHERE id=?',(photo_id,)).fetchone()
        if not row: raise DomainError('not_found',404)
        p=self.pet(actor,row['pet'])
        if edit and actor not in (p['owner'],row['provider']): raise DomainError('not_found',404)
        return dict(row)

    def add_photos(self, actor, pet_id, items):
        results=super().add_photos(actor,pet_id,items)
        with self.db:
            for r in results:
                if r['status']=='saved': self.db.execute('INSERT INTO notices VALUES(?,?,?,?,?)',(str(uuid4()),pet_id,r['id'],actor,time.time()))
        return results

    def edit_photo(self, actor, photo_id, captured):
        self.photo(actor,photo_id,True); precision=valid_date(captured)
        with self.db: self.db.execute('UPDATE photos SET captured=?,precision=? WHERE id=?',(captured,precision,photo_id))
        return {'updated':True}

    def delete_photo(self, actor, pet_id, photo_id):
        p=self.photo(actor,photo_id,True)
        if p['pet']!=pet_id: raise DomainError('not_found',404)
        return super().delete_photo(actor,pet_id,photo_id)

    def consent(self, actor, photo_id, purpose, allowed):
        self.require_actor(actor)
        row=self.db.execute('SELECT * FROM photos WHERE id=?',(photo_id,)).fetchone()
        if not row: raise DomainError('not_found',404)
        if actor!=row['provider']: raise DomainError('provider_required',403)
        if purpose not in ('sns','twins','external_share') or not isinstance(allowed,bool): raise DomainError('invalid_consent')
        if allowed: self.pet(actor,row['pet'])
        with self.db:
            self.db.execute('INSERT INTO consents(photo,purpose,provider,allowed) VALUES(?,?,?,?) ON CONFLICT(photo,purpose) DO UPDATE SET allowed=excluded.allowed,version=version+1',(photo_id,purpose,actor,int(allowed)))
        return {'purpose':purpose,'allowed':allowed}

    def consent_allowed(self, photo_id, purpose):
        return bool(self.db.execute('SELECT 1 FROM consents c JOIN photos p ON p.id=c.photo WHERE c.photo=? AND c.purpose=? AND c.allowed=1 AND c.provider=p.provider',(photo_id,purpose)).fetchone())

    def notification_frequency(self, actor, pet_id, frequency):
        self.pet(actor,pet_id)
        if frequency not in ('off','immediate','batched'): raise DomainError('invalid_frequency')
        with self.db:
            self.db.execute('INSERT INTO members(pet,actor,active,frequency) VALUES(?,?,1,?) ON CONFLICT(pet,actor) DO UPDATE SET frequency=excluded.frequency',(pet_id,actor,frequency))
        return {'frequency':frequency}

    def notifications(self, actor, pet_id):
        self.pet(actor,pet_id) # Recheck every read; revoked members cannot read old notices.
        pref=self.db.execute('SELECT frequency FROM members WHERE pet=? AND actor=?',(pet_id,actor)).fetchone()
        if pref and pref[0]=='off': return []
        return [dict(r) for r in self.db.execute('SELECT id,photo,actor,created FROM notices WHERE pet=? AND actor!=?',(pet_id,actor))]

    def request_removal(self, actor, photo_id):
        self.require_actor(actor)
        row=self.db.execute('SELECT provider FROM photos WHERE id=?',(photo_id,)).fetchone()
        if not row or row[0]!=actor: raise DomainError('not_found',404)
        with self.db: self.db.execute('INSERT INTO removal_requests VALUES(?,?,?,?)',(str(uuid4()),photo_id,actor,time.time()))
        return {'requested':True}
