"""Executable SEED editorial workflow, LOCAL synthetic data only.

Operator sessions remain fixtures. No private family album access is granted.
Real auth/MFA, original image ingestion and production workers are separate gates.
"""
import csv
import hashlib
import io
import json
import math
import re
import time
from uuid import uuid4
from .domain import DomainError
from .fixtures import PETS
from .social import SocialStore

class ManagedStore(SocialStore):
    def __init__(self, path=':memory:'):
        super().__init__(path)
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS operators(id TEXT PRIMARY KEY, role TEXT, active INTEGER DEFAULT 1);
        CREATE TABLE IF NOT EXISTS managed_profiles(pet TEXT PRIMARY KEY REFERENCES pets(id), publisher TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'active', revision INTEGER NOT NULL DEFAULT 1, updated_by TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS managed_assets(id TEXT PRIMARY KEY, pet TEXT REFERENCES managed_profiles(pet), asset TEXT NOT NULL, holder TEXT, verifier TEXT, verified_at REAL, scope TEXT, expires REAL, evidence TEXT, revoked INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS editorial(id TEXT PRIMARY KEY, pet TEXT REFERENCES managed_profiles(pet), body TEXT NOT NULL, assets TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'draft', revision INTEGER NOT NULL DEFAULT 1, approver TEXT, approved_revision INTEGER, due REAL, public_post TEXT UNIQUE REFERENCES public_posts(id));
        CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY AUTOINCREMENT, operator_user_id TEXT NOT NULL, managed_profile_id TEXT, action TEXT NOT NULL, target TEXT, created REAL NOT NULL, approver TEXT);
        CREATE TABLE IF NOT EXISTS managed_requests(operator TEXT, request_key TEXT, digest TEXT, result TEXT, PRIMARY KEY(operator,request_key));
        CREATE TABLE IF NOT EXISTS discovery_config(id INTEGER PRIMARY KEY CHECK(id=1), managed_fraction REAL NOT NULL DEFAULT 0.5);
        CREATE TABLE IF NOT EXISTS account_suspensions(account TEXT PRIMARY KEY, moderator TEXT NOT NULL, reason TEXT NOT NULL, created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS report_reviews(report TEXT PRIMARY KEY REFERENCES reports(id), moderator TEXT NOT NULL, decision TEXT NOT NULL, note TEXT NOT NULL, created REAL NOT NULL);
        INSERT OR IGNORE INTO discovery_config(id) VALUES(1);
        ''')
        with self.db:
            for op,role in [('demo-editor','editor'),('demo-approver','approver'),('demo-distributor','distributor'),('demo-moderator','moderator')]:
                self.db.execute('INSERT OR IGNORE INTO operators(id,role) VALUES(?,?)',(op,role))
            for p in PETS:
                self.db.execute("INSERT OR IGNORE INTO managed_profiles VALUES(?,'demo-publisher','active',1,'fixture-bootstrap')",(p['id'],))
                aid='seed-asset-'+p['id']
                self.db.execute("INSERT OR IGNORE INTO managed_assets VALUES(?,?,?,'MEFRION synthetic fixture','fixture-bootstrap',?,'sns',NULL,'design/ASSET_RIGHTS.md',0)",(aid,p['id'],p['asset'],time.time()))
                self.db.execute("INSERT OR IGNORE INTO editorial(id,pet,body,assets,state,approver,approved_revision,public_post) VALUES(?,?,?,?, 'published','fixture-bootstrap',1,?)",('seed-editorial-'+p['id'],p['id'],'犬猫を描いた開発用イラストです。',json.dumps([aid]),'demo-post-'+p['id']))

    def operator(self, actor, *roles):
        op=self.db.execute('SELECT * FROM operators WHERE id=? AND active=1',(actor,)).fetchone()
        if not op or (roles and op['role'] not in roles):
            with self.db:self.audit_action(actor or 'unauthenticated',None,'operator.denied')
            raise DomainError('operator_permission_required',403)
        return dict(op)

    def require_active_actor(self,actor):
        super().require_actor(actor)
        if self.db.execute('SELECT 1 FROM account_suspensions WHERE account=?',(actor,)).fetchone(): raise DomainError('account_suspended',403)

    # Moderation must not prevent a provider from withdrawing consent or deleting
    # private photos. Restrict new publishing/interactions, not privacy controls.
    def create_pet(self,actor,name,species):
        self.require_active_actor(actor);return super().create_pet(actor,name,species)

    def set_pet_public(self,actor,pet_id,allowed,explicit=False):
        if allowed:self.require_active_actor(actor)
        return super().set_pet_public(actor,pet_id,allowed,explicit)

    def publish(self,actor,pet_id,photo_ids,body='',kind='post',explicit=False):
        self.require_active_actor(actor);return super().publish(actor,pet_id,photo_ids,body,kind,explicit)

    def react(self,actor,post_id,kind,enabled):
        if enabled:self.require_active_actor(actor)
        return super().react(actor,post_id,kind,enabled)

    def follow(self,actor,pet_id,enabled):
        if enabled:self.require_active_actor(actor)
        return super().follow(actor,pet_id,enabled)

    def comment(self,actor,post_id,body,parent=None):
        self.require_active_actor(actor);return super().comment(actor,post_id,body,parent)

    def reports_for_review(self,actor):
        self.operator(actor,'moderator')
        return [dict(row) for row in self.db.execute('SELECT r.id,r.post,r.reason,r.state,p.pet,p.body,v.decision,v.note,v.moderator,v.created FROM reports r JOIN public_posts p ON p.id=r.post LEFT JOIN report_reviews v ON v.report=r.id ORDER BY r.rowid DESC LIMIT 200')]

    def review_report(self,actor,report,decision,note):
        self.operator(actor,'moderator')
        if decision not in ('dismiss','hide_post','suspend_account') or not isinstance(note,str) or not 1<=len(note.strip())<=1000: raise DomainError('review_reason_required')
        with self.lock,self.db:
            self.db.execute('BEGIN IMMEDIATE')
            row=self.db.execute('SELECT r.*,p.pet,t.owner FROM reports r JOIN public_posts p ON p.id=r.post JOIN pets t ON t.id=p.pet WHERE r.id=?',(report,)).fetchone()
            if not row: raise DomainError('not_found',404)
            prior=self.db.execute('SELECT * FROM report_reviews WHERE report=?',(report,)).fetchone()
            if prior:
                if prior['decision']!=decision or prior['note']!=note.strip(): raise DomainError('review_conflict',409)
                return {'resolved':True,'decision':decision}
            if decision=='hide_post':
                self.db.execute("UPDATE public_posts SET state='withdrawn' WHERE id=?",(row['post'],))
                self.db.execute("UPDATE editorial SET state='cancelled' WHERE public_post=?",(row['post'],))
            elif decision=='suspend_account':
                self.db.execute('INSERT OR IGNORE INTO account_suspensions VALUES(?,?,?,?)',(row['owner'],actor,note.strip(),time.time()))
                self.db.execute('UPDATE pets SET public=0 WHERE owner=?',(row['owner'],))
                self.db.execute("UPDATE public_posts SET state='withdrawn' WHERE pet IN (SELECT id FROM pets WHERE owner=?)",(row['owner'],))
                self.db.execute("UPDATE managed_profiles SET state='suspended',revision=revision+1,updated_by=? WHERE pet IN (SELECT id FROM pets WHERE owner=?)",(actor,row['owner']))
                self.db.execute("UPDATE editorial SET state='cancelled' WHERE pet IN (SELECT id FROM pets WHERE owner=?)",(row['owner'],))
            self.db.execute('INSERT INTO report_reviews VALUES(?,?,?,?,?)',(report,actor,decision,note.strip(),time.time()))
            self.db.execute("UPDATE reports SET state='resolved' WHERE id=?",(report,))
            self.audit_action(actor,row['pet'],'report.'+decision,report)
        return {'resolved':True,'decision':decision}

    def audit_action(self, actor, pet, action, target=None, approver=None):
        self.db.execute('INSERT INTO audit(operator_user_id,managed_profile_id,action,target,created,approver) VALUES(?,?,?,?,?,?)',(actor,pet,action,target,time.time(),approver))

    def profile(self, pet):
        row=self.db.execute('SELECT * FROM managed_profiles WHERE pet=?',(pet,)).fetchone()
        if not row: raise DomainError('managed_profile_not_found',404)
        return dict(row)

    def list_managed(self, actor):
        self.operator(actor)
        profiles=[]
        for row in self.db.execute('SELECT m.*,p.name,p.species,p.public FROM managed_profiles m JOIN pets p ON p.id=m.pet ORDER BY p.rowid'):
            p=dict(row)
            drafts=list(self.db.execute('SELECT state FROM editorial WHERE pet=?',(p['pet'],)))
            p['counts']={s:sum(d[0]==s for d in drafts) for s in ('draft','approved','scheduled','published')}
            p['materials']=[dict(a) for a in self.db.execute('SELECT * FROM managed_assets WHERE pet=?',(p['pet'],))]
            profiles.append(p)
        return profiles

    @staticmethod
    def valid_profile(row):
        if not isinstance(row,dict): raise DomainError('invalid_profile')
        pid=row.get('id'); name=row.get('name');species=row.get('species')
        if not isinstance(pid,str) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,64}',pid): raise DomainError('invalid_profile_id')
        if not isinstance(name,str) or not 1<=len(name.strip())<=40 or species not in ('dog','cat'): raise DomainError('invalid_pet')
        asset=row.get('asset')
        if asset not in {p['asset'] for p in PETS}: raise DomainError('owned_demo_asset_required')
        if next(p['species'] for p in PETS if p['asset']==asset)!=species: raise DomainError('asset_species_mismatch')
        return {'id':pid,'name':name.strip(),'species':species,'asset':asset}

    def preview_profiles(self, actor, rows):
        self.operator(actor,'editor')
        if not isinstance(rows,list) or not 1<=len(rows)<=50: raise DomainError('batch_limit')
        result=[];seen=set()
        for index,row in enumerate(rows):
            try:
                clean=self.valid_profile(row)
                if clean['id'] in seen or self.db.execute('SELECT 1 FROM pets WHERE id=?',(clean['id'],)).fetchone(): raise DomainError('duplicate_profile_id',409)
                seen.add(clean['id'])
                result.append({'row':index+1,'valid':True,'profile':clean,'rights':'not_verified; draft_only'})
            except DomainError as err: result.append({'row':index+1,'valid':False,'error':err.code})
        return result

    def preview_csv(self, actor, source):
        if not isinstance(source,str) or len(source)>50000: raise DomainError('csv_limit')
        reader=csv.DictReader(io.StringIO(source))
        if reader.fieldnames!=['id','name','species','asset']: raise DomainError('csv_header_required')
        return self.preview_profiles(actor,list(reader))

    def create_managed(self, actor, rows, request_key):
        self.operator(actor,'editor')
        if not isinstance(request_key,str) or not 1<=len(request_key)<=100: raise DomainError('invalid_request_key')
        digest=hashlib.sha256(json.dumps(rows,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
        with self.lock,self.db:
            self.db.execute('BEGIN IMMEDIATE')
            existing=self.db.execute('SELECT * FROM managed_requests WHERE operator=? AND request_key=?',(actor,request_key)).fetchone()
            if existing:
                if existing['digest']!=digest: raise DomainError('idempotency_conflict',409)
                return json.loads(existing['result'])
            if self.db.execute("SELECT 1 FROM account_suspensions WHERE account='demo-publisher'").fetchone(): raise DomainError('account_suspended',403)
            preview=self.preview_profiles(actor,rows)
            if any(not p['valid'] for p in preview): raise DomainError('preview_errors',409)
            ids=[]
            for item in preview:
                p=item['profile'];pid=p['id'];ids.append(pid)
                self.db.execute('INSERT INTO pets VALUES(?,?,?,?,0)',(pid,'demo-publisher',p['name'],p['species']))
                self.db.execute("INSERT INTO managed_profiles VALUES(?,'demo-publisher','active',1,?)",(pid,actor))
                self.db.execute('INSERT INTO managed_assets(id,pet,asset) VALUES(?,?,?)',(str(uuid4()),pid,p['asset']))
                self.audit_action(actor,pid,'profile.create',pid)
            result={'created':ids,'demo_only':True}
            self.db.execute('INSERT INTO managed_requests VALUES(?,?,?,?)',(actor,request_key,digest,json.dumps(result)))
            return result

    def edit_managed(self, actor, pet, revision, name, species):
        self.operator(actor,'editor')
        if not isinstance(name,str) or not 1<=len(name.strip())<=40 or species not in ('dog','cat'): raise DomainError('invalid_pet')
        with self.lock,self.db:
            self.db.execute('BEGIN IMMEDIATE')
            p=self.profile(pet)
            if p['revision']!=revision: raise DomainError('revision_conflict',409)
            materials=self.db.execute('SELECT asset FROM managed_assets WHERE pet=?',(pet,)).fetchall()
            if any(next(item['species'] for item in PETS if item['asset']==m['asset'])!=species for m in materials): raise DomainError('asset_species_mismatch')
            self.db.execute('UPDATE pets SET name=?,species=? WHERE id=?',(name.strip(),species,pet))
            self.db.execute('UPDATE managed_profiles SET revision=revision+1,updated_by=? WHERE pet=?',(actor,pet))
            self.audit_action(actor,pet,'profile.edit',pet)
        return {'revision':revision+1}

    def register_rights(self, actor, asset_id, holder, scope, expires, evidence):
        self.operator(actor,'approver')
        if not isinstance(holder,str) or not 1<=len(holder.strip())<=200 or scope!='sns' or not isinstance(evidence,str) or not 1<=len(evidence)<=500: raise DomainError('rights_evidence_required')
        if expires is not None and (isinstance(expires,bool) or not isinstance(expires,(float,int)) or not math.isfinite(expires) or expires<=time.time()): raise DomainError('future_expiry_required')
        with self.lock,self.db:
            row=self.db.execute('SELECT * FROM managed_assets WHERE id=?',(asset_id,)).fetchone()
            if not row: raise DomainError('not_found',404)
            self.db.execute('UPDATE managed_assets SET holder=?,verifier=?,verified_at=?,scope=?,expires=?,evidence=?,revoked=0 WHERE id=?',(holder.strip(),actor,time.time(),scope,expires,evidence,asset_id))
            self.audit_action(actor,row['pet'],'rights.verify',asset_id)
        return {'verified':True}

    def rights_valid(self, asset_id, pet, now=None):
        now=time.time() if now is None else now
        a=self.db.execute('SELECT * FROM managed_assets WHERE id=? AND pet=?',(asset_id,pet)).fetchone()
        return bool(a and a['holder'] and a['verifier'] and a['verified_at'] and a['scope']=='sns' and a['evidence'] and not a['revoked'] and (a['expires'] is None or a['expires']>now))

    def draft(self, actor, pet, body, assets, draft_id=None, revision=None):
        self.operator(actor,'editor');self.profile(pet)
        if not isinstance(body,str) or len(body)>500 or not isinstance(assets,list) or not 1<=len(assets)<=4 or any(not isinstance(a,str) for a in assets) or len(set(assets))!=len(assets): raise DomainError('invalid_draft')
        for aid in assets:
            if not self.db.execute('SELECT 1 FROM managed_assets WHERE id=? AND pet=?',(aid,pet)).fetchone(): raise DomainError('asset_profile_mismatch')
        with self.lock,self.db:
            self.db.execute('BEGIN IMMEDIATE')
            if draft_id:
                row=self.editorial(draft_id)
                if row['pet']!=pet or row['revision']!=revision: raise DomainError('revision_conflict',409)
                if row['public_post']: self.db.execute("UPDATE public_posts SET state='withdrawn' WHERE id=?",(row['public_post'],))
                self.db.execute("UPDATE editorial SET body=?,assets=?,revision=revision+1,state='draft',approver=NULL,approved_revision=NULL,due=NULL WHERE id=?",(body,json.dumps(assets),draft_id))
            else:
                draft_id=str(uuid4())
                self.db.execute('INSERT INTO editorial(id,pet,body,assets) VALUES(?,?,?,?)',(draft_id,pet,body,json.dumps(assets)))
            self.audit_action(actor,pet,'post.draft',draft_id)
        return self.editorial(draft_id)

    def editorial(self, draft_id):
        r=self.db.execute('SELECT * FROM editorial WHERE id=?',(draft_id,)).fetchone()
        if not r: raise DomainError('not_found',404)
        return dict(r)

    def approve(self, actor, draft_id, revision):
        self.operator(actor,'approver')
        with self.lock,self.db:
            self.db.execute('BEGIN IMMEDIATE')
            row=self.editorial(draft_id)
            if row['revision']!=revision or row['state']!='draft': raise DomainError('revision_conflict',409)
            if not all(self.rights_valid(a,row['pet']) for a in json.loads(row['assets'])): raise DomainError('rights_required',403)
            self.db.execute("UPDATE editorial SET state='approved',approver=?,approved_revision=revision WHERE id=?",(actor,draft_id))
            self.audit_action(actor,row['pet'],'post.approve',draft_id,actor)
        return self.editorial(draft_id)

    def distribute(self, actor, draft_id, revision, due=None, explicit=False):
        self.operator(actor,'distributor')
        if explicit is not True: raise DomainError('explicit_publish_required')
        now=time.time()
        if due is not None and (isinstance(due,bool) or not isinstance(due,(int,float)) or not math.isfinite(due) or due<=now): raise DomainError('future_schedule_required')
        with self.lock,self.db:
            self.db.execute('BEGIN IMMEDIATE')
            row=self.editorial(draft_id)
            if row['revision']!=revision or row['approved_revision']!=revision: raise DomainError('approval_required',403)
            if row['state']=='published': return {'post_id':row['public_post'],'already_published':True}
            if row['state'] not in ('approved','scheduled'): raise DomainError('approval_required',403)
            self.ready(row,now)
            if due is not None:
                if not all(self.rights_valid(a,row['pet'],due) for a in json.loads(row['assets'])): raise DomainError('rights_expire_before_schedule',403)
                self.db.execute("UPDATE editorial SET state='scheduled',due=? WHERE id=?",(due,draft_id))
                self.audit_action(actor,row['pet'],'post.schedule',draft_id,row['approver'])
                return {'scheduled':due}
            return self.deliver(row,actor,now)

    def ready(self,row,now):
        if self.db.execute('SELECT 1 FROM account_suspensions s JOIN pets p ON p.owner=s.account WHERE p.id=?',(row['pet'],)).fetchone(): raise DomainError('account_suspended',403)
        if self.profile(row['pet'])['state']!='active': raise DomainError('profile_stopped',409)
        if not all(self.rights_valid(a,row['pet'],now) for a in json.loads(row['assets'])): raise DomainError('rights_required',403)

    def deliver(self,row,actor,now):
        self.ready(row,now)
        post=row['public_post'] or str(uuid4()); photos=[]
        for aid in json.loads(row['assets']):
            asset=self.db.execute('SELECT asset FROM managed_assets WHERE id=?',(aid,)).fetchone()[0]
            pid='managed-photo-'+aid;photos.append(pid)
            self.db.execute("INSERT OR IGNORE INTO photos VALUES(?,?, 'demo-publisher',?,NULL,'unknown',?)",(pid,row['pet'],asset,aid))
            self.db.execute("INSERT INTO consents VALUES(?,'sns','demo-publisher',1,1) ON CONFLICT(photo,purpose) DO UPDATE SET allowed=1,version=version+1",(pid,))
        self.db.execute('UPDATE pets SET public=1 WHERE id=?',(row['pet'],))
        self.db.execute("INSERT INTO public_posts VALUES(?,?,?,'post',?,'published','managed_seed') ON CONFLICT(id) DO UPDATE SET body=excluded.body,photo_ids=excluded.photo_ids,state='published'",(post,row['pet'],row['body'],json.dumps(photos)))
        self.db.execute("UPDATE editorial SET state='published',public_post=?,due=NULL WHERE id=?",(post,row['id']))
        self.audit_action(actor,row['pet'],'post.publish',row['id'],row['approver'])
        return {'post_id':post,'already_published':False}

    def dispatch_due(self,actor,now=None):
        self.operator(actor,'distributor');now=time.time() if now is None else now
        result=[]
        with self.lock,self.db:
            self.db.execute('BEGIN IMMEDIATE')
            for item in list(self.db.execute("SELECT * FROM editorial WHERE state='scheduled' AND due<=?",(now,))):
                row=dict(item)
                try: result.append(self.deliver(row,actor,now))
                except DomainError as e:
                    self.db.execute("UPDATE editorial SET state='cancelled',due=NULL WHERE id=?",(row['id'],))
                    self.audit_action(actor,row['pet'],'post.schedule_blocked',row['id'],row['approver'])
                    result.append({'draft_id':row['id'],'error':e.code})
        return {'results':result}

    def cancel(self, actor, draft_id):
        self.operator(actor,'distributor')
        with self.lock,self.db:
            row=self.editorial(draft_id)
            self.db.execute("UPDATE editorial SET state='cancelled',due=NULL WHERE id=?",(draft_id,))
            if row['public_post']: self.db.execute("UPDATE public_posts SET state='withdrawn' WHERE id=?",(row['public_post'],))
            self.audit_action(actor,row['pet'],'post.cancel',draft_id,row['approver'])
        return {'cancelled':True}

    def stop_profiles(self, actor, pets, state='suspended'):
        self.operator(actor,'distributor')
        if not isinstance(pets,list) or not 1<=len(pets)<=50 or any(not isinstance(p,str) for p in pets) or state not in ('suspended','archived'): raise DomainError('batch_limit')
        with self.lock,self.db:
            self.db.execute('BEGIN IMMEDIATE')
            for pet in pets:self.profile(pet)
            for pet in pets:
                self.db.execute('UPDATE managed_profiles SET state=?,revision=revision+1,updated_by=? WHERE pet=?',(state,actor,pet))
                self.db.execute('UPDATE pets SET public=0 WHERE id=?',(pet,))
                self.db.execute("UPDATE public_posts SET state='withdrawn' WHERE pet=?",(pet,))
                self.db.execute("UPDATE editorial SET state='cancelled',due=NULL WHERE pet=? AND state IN ('published','scheduled','approved')",(pet,))
                self.audit_action(actor,pet,'profile.'+state,pet)
        return {'stopped':pets}

    def revoke_rights(self,actor,asset_id):
        self.operator(actor,'approver')
        with self.lock,self.db:
            row=self.db.execute('SELECT * FROM managed_assets WHERE id=?',(asset_id,)).fetchone()
            if not row: raise DomainError('not_found',404)
            self.db.execute('UPDATE managed_assets SET revoked=1 WHERE id=?',(asset_id,))
            for d in self.db.execute('SELECT * FROM editorial WHERE pet=?',(row['pet'],)):
                if asset_id in json.loads(d['assets']):
                    self.db.execute("UPDATE editorial SET state='cancelled',due=NULL WHERE id=?",(d['id'],))
                    if d['public_post']: self.db.execute("UPDATE public_posts SET state='withdrawn' WHERE id=?",(d['public_post'],))
            self.audit_action(actor,row['pet'],'rights.revoke',asset_id)
        return {'revoked':True}

    def public_post(self,post_id,actor=None):
        post=super().public_post(post_id,actor)
        if self.db.execute('SELECT 1 FROM account_suspensions s JOIN pets p ON p.owner=s.account WHERE p.id=?',(post['pet_id'],)).fetchone(): raise DomainError('not_found',404)
        row=self.db.execute('SELECT * FROM editorial WHERE public_post=?',(post_id,)).fetchone()
        if row:
            if row['state']!='published': raise DomainError('not_found',404)
            try:self.ready(dict(row),time.time())
            except DomainError: raise DomainError('not_found',404)
        return post

    def search(self,query,actor=None):
        results=[]
        for p in super().search(query,actor):
            if self.db.execute('SELECT 1 FROM account_suspensions s JOIN pets p ON p.owner=s.account WHERE p.id=?',(p['id'],)).fetchone(): continue
            profile=self.db.execute('SELECT state FROM managed_profiles WHERE pet=?',(p['id'],)).fetchone()
            if profile:
                if profile['state']!='active':continue
                if not self.db.execute("SELECT 1 FROM managed_assets WHERE pet=? AND verifier IS NOT NULL AND revoked=0 AND scope='sns' AND (expires IS NULL OR expires>?)",(p['id'],time.time())).fetchone():continue
            results.append(p)
        return results

    def admin_posts(self,actor):
        self.operator(actor)
        return [dict(r) for r in self.db.execute('SELECT * FROM editorial ORDER BY due IS NULL,due,id')]

    def audit_log(self,actor):
        self.operator(actor)
        return [dict(r) for r in self.db.execute('SELECT * FROM audit ORDER BY id DESC LIMIT 200')]

    def discovery(self,actor=None):
        posts=super().feed(actor);user=[];managed=[]
        fraction=self.db.execute('SELECT managed_fraction FROM discovery_config WHERE id=1').fetchone()[0]
        seen=set()
        for post in posts:
            fingerprint=tuple(i['asset'] for i in post['images'])
            if fingerprint in seen:continue
            seen.add(fingerprint)
            origin=self.db.execute('SELECT origin FROM public_posts WHERE id=?',(post['id'],)).fetchone()[0]
            (managed if origin=='managed_seed' else user).append(post)
        if not user:return managed
        # User content first; ratio applies while both pools have candidates. Never duplicate.
        result=[];mi=0;ui=0
        while ui<len(user) or mi<len(managed):
            if ui<len(user) and (not result or mi>=len(managed) or mi/max(1,len(result))>=fraction): result.append(user[ui]);ui+=1
            elif mi<len(managed) and fraction>0: result.append(managed[mi]);mi+=1
            elif ui<len(user):result.append(user[ui]);ui+=1
            else:break
        return result

    def configure_discovery(self,actor,fraction):
        self.operator(actor,'distributor')
        if isinstance(fraction,bool) or not isinstance(fraction,(int,float)) or not math.isfinite(fraction) or not 0<=fraction<=1:raise DomainError('invalid_fraction')
        with self.db:
            self.db.execute('UPDATE discovery_config SET managed_fraction=? WHERE id=1',(fraction,))
            self.audit_action(actor,None,'discovery.configure',str(fraction))
        return {'managed_fraction':fraction}
