"""Phase 3 LOCAL preview policies. Fixed demo accounts and owned assets only.

Public here means a loopback preview projection, never deployment or publication.
Managed profiles have no individual credentials. Full SEED editorial operations
and real iPhone networking remain release blockers.
"""
import json
import unicodedata
from uuid import uuid4
from .family import FamilyStore
from .domain import DomainError, LIMITS
from .fixtures import PETS

class SocialStore(FamilyStore):
    def __init__(self,path=':memory:'):
        super().__init__(path)
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS public_posts(id TEXT PRIMARY KEY, pet TEXT REFERENCES pets(id), body TEXT, kind TEXT, photo_ids TEXT, state TEXT DEFAULT 'published', origin TEXT DEFAULT 'user');
        CREATE TABLE IF NOT EXISTS reactions(actor TEXT, post TEXT REFERENCES public_posts(id), kind TEXT, PRIMARY KEY(actor,post,kind));
        CREATE TABLE IF NOT EXISTS follows(actor TEXT, pet TEXT REFERENCES pets(id), PRIMARY KEY(actor,pet));
        CREATE TABLE IF NOT EXISTS blocks(actor TEXT, target TEXT, PRIMARY KEY(actor,target));
        CREATE TABLE IF NOT EXISTS comments(id TEXT PRIMARY KEY, post TEXT REFERENCES public_posts(id), actor TEXT, body TEXT, parent TEXT REFERENCES comments(id));
        CREATE TABLE IF NOT EXISTS reports(id TEXT PRIMARY KEY, actor TEXT, post TEXT REFERENCES public_posts(id), reason TEXT, state TEXT DEFAULT 'open');
        ''')
        # Development-only bootstrap. Never import fixture approvals into production.
        with self.db:
            for item in PETS:
                pet=item['id']; photo='seed-photo-'+pet; post='demo-post-'+pet
                self.db.execute('INSERT OR IGNORE INTO pets VALUES(?,?,?,?,1)',(pet,'demo-publisher',item['name'],item['species']))
                self.db.execute('INSERT OR IGNORE INTO photos VALUES(?,?,?,?,?,?,?)',(photo,pet,'demo-publisher',item['asset'],None,'unknown','seed-'+pet))
                self.db.execute("INSERT OR IGNORE INTO consents VALUES(?,'sns','demo-publisher',1,1)",(photo,))
                self.db.execute("INSERT OR IGNORE INTO public_posts(id,pet,body,kind,photo_ids,origin) VALUES(?,?,?,'post',?,'managed_seed')",(post,pet,'犬猫を描いた開発用イラストです。',json.dumps([photo])))

    def blocked(self,actor,owner):
        if actor is None: return False
        return bool(self.db.execute('SELECT 1 FROM blocks WHERE (actor=? AND target=?) OR (actor=? AND target=?)',(actor,owner,owner,actor)).fetchone())

    def set_pet_public(self,actor,pet_id,allowed,explicit=False):
        self.owner(actor,pet_id)
        if not isinstance(allowed,bool) or (allowed and explicit is not True): raise DomainError('explicit_publish_required')
        with self.db:
            self.db.execute('UPDATE pets SET public=? WHERE id=?',(int(allowed),pet_id))
            if not allowed: self.db.execute("UPDATE public_posts SET state='withdrawn' WHERE pet=?",(pet_id,))
        return {'public':allowed}

    def publish(self,actor,pet_id,photo_ids,body='',kind='post',explicit=False):
        p=self.owner(actor,pet_id)
        if explicit is not True: raise DomainError('explicit_publish_required')
        if not p['public']: raise DomainError('pet_private',409)
        if kind not in ('post','share'): raise DomainError('invalid_post')
        if not isinstance(body,str) or len(body)>LIMITS['post_characters']: raise DomainError('body_limit')
        if not isinstance(photo_ids,list) or not 1<=len(photo_ids)<=LIMITS['post_images'] or any(not isinstance(i,str) for i in photo_ids) or len(set(photo_ids))!=len(photo_ids): raise DomainError('image_limit')
        if kind=='share' and len(photo_ids)!=2: raise DomainError('select_two_distinct_photos')
        purpose='sns' if kind=='post' else 'external_share'
        for pid in photo_ids:
            photo=self.photo(actor,pid)
            if photo['pet']!=pet_id: raise DomainError('photo_pet_mismatch')
            if not self.consent_allowed(pid,purpose): raise DomainError('provider_consent_required',403)
        post=str(uuid4())
        with self.db: self.db.execute('INSERT INTO public_posts(id,pet,body,kind,photo_ids) VALUES(?,?,?,?,?)',(post,pet_id,body,kind,json.dumps(photo_ids)))
        return self.public_post(post,actor)

    def public_post(self,post_id,actor=None):
        if actor is not None: self.require_actor(actor)
        post=self.db.execute('SELECT * FROM public_posts WHERE id=?',(post_id,)).fetchone()
        if not post or post['state']!='published': raise DomainError('not_found',404)
        pet=self.db.execute('SELECT * FROM pets WHERE id=?',(post['pet'],)).fetchone()
        if not pet or not pet['public'] or self.blocked(actor,pet['owner']): raise DomainError('not_found',404)
        ids=json.loads(post['photo_ids']); purpose='sns' if post['kind']=='post' else 'external_share'
        photos=[]
        for pid in ids:
            p=self.db.execute('SELECT * FROM photos WHERE id=? AND pet=?',(pid,pet['id'])).fetchone()
            if not p or not self.consent_allowed(pid,purpose): raise DomainError('not_found',404)
            photos.append({'asset':p['asset'],'captured':p['captured']})
        # Never project human owner/provider, private photo IDs, or editorial metadata.
        return {'id':post_id,'pet_id':pet['id'],'name':pet['name'],'species':pet['species'],'body':post['body'],'kind':post['kind'],'images':photos,'asset':photos[0]['asset'],'demo_only':True,
                'liked':bool(self.db.execute("SELECT 1 FROM reactions WHERE actor=? AND post=? AND kind='like'",(actor,post_id)).fetchone()),
                'saved':bool(self.db.execute("SELECT 1 FROM reactions WHERE actor=? AND post=? AND kind='save'",(actor,post_id)).fetchone()),
                'following':bool(self.db.execute('SELECT 1 FROM follows WHERE actor=? AND pet=?',(actor,pet['id'])).fetchone()),
                'likes':self.db.execute("SELECT count(*) FROM reactions WHERE post=? AND kind='like'",(post_id,)).fetchone()[0],
                'comments':len(self._visible_comments(post_id,actor))}

    def _visible_comments(self,post_id,actor=None):
        # Caller checks the parent post first. Project only explicit demo display names.
        return [{'id':r['id'],'body':r['body'],'parent':r['parent'],'display_name':'開発テスト利用者'} for r in self.db.execute('SELECT * FROM comments WHERE post=? ORDER BY rowid',(post_id,)) if not self.blocked(actor,r['actor'])]

    def public_comments(self,post_id,actor=None):
        self.public_post(post_id,actor)
        return self._visible_comments(post_id,actor)

    def feed(self,actor=None,following=False):
        if actor is not None: self.require_actor(actor)
        if following and actor is None: raise DomainError('authentication_required',401)
        posts=[]
        for r in self.db.execute("SELECT id,pet FROM public_posts WHERE kind='post' ORDER BY rowid DESC"):
            if following and not self.db.execute('SELECT 1 FROM follows WHERE actor=? AND pet=?',(actor,r['pet'])).fetchone(): continue
            try: posts.append(self.public_post(r['id'],actor))
            except DomainError: pass
        return posts

    def search(self,query,actor=None):
        if actor is not None: self.require_actor(actor)
        if not isinstance(query,str) or len(query)>100: raise DomainError('invalid_query')
        q=unicodedata.normalize('NFKC',query).casefold()
        return [{'id':p['id'],'name':p['name'],'species':p['species']} for p in self.db.execute('SELECT * FROM pets WHERE public=1') if q in unicodedata.normalize('NFKC',p['name']).casefold() and not self.blocked(actor,p['owner'])]

    def react(self,actor,post_id,kind,enabled):
        self.require_actor(actor); self.public_post(post_id,actor)
        if kind not in ('like','save') or not isinstance(enabled,bool): raise DomainError('invalid_reaction')
        with self.db:
            if enabled: self.db.execute('INSERT OR IGNORE INTO reactions VALUES(?,?,?)',(actor,post_id,kind))
            else: self.db.execute('DELETE FROM reactions WHERE actor=? AND post=? AND kind=?',(actor,post_id,kind))
        return {'enabled':enabled}

    def saved(self,actor):
        self.require_actor(actor);posts=[]
        for row in self.db.execute("SELECT post FROM reactions WHERE actor=? AND kind='save'",(actor,)):
            try: posts.append(self.public_post(row[0],actor))
            except DomainError: pass
        return posts

    def follow(self,actor,pet_id,enabled):
        self.require_actor(actor)
        pet=self.db.execute('SELECT * FROM pets WHERE id=? AND public=1',(pet_id,)).fetchone()
        if not pet or self.blocked(actor,pet['owner']): raise DomainError('not_found',404)
        if not isinstance(enabled,bool): raise DomainError('invalid_follow')
        with self.db:
            if enabled: self.db.execute('INSERT OR IGNORE INTO follows VALUES(?,?)',(actor,pet_id))
            else: self.db.execute('DELETE FROM follows WHERE actor=? AND pet=?',(actor,pet_id))
        return {'following':enabled}

    def comment(self,actor,post_id,body,parent=None):
        self.require_actor(actor); self.public_post(post_id,actor)
        if not isinstance(body,str) or not 1<=len(body.strip())<=500: raise DomainError('invalid_comment')
        if parent is not None:
            row=self.db.execute('SELECT * FROM comments WHERE id=? AND post=?',(parent,post_id)).fetchone()
            if not row or row['parent'] is not None or self.blocked(actor,row['actor']): raise DomainError('reply_depth_or_target')
        cid=str(uuid4())
        with self.db: self.db.execute('INSERT INTO comments VALUES(?,?,?,?,?)',(cid,post_id,actor,body.strip(),parent))
        return {'id':cid}

    def block_pet_owner(self,actor,pet_id):
        self.require_actor(actor)
        pet=self.db.execute('SELECT owner FROM pets WHERE id=?',(pet_id,)).fetchone()
        if not pet or pet[0]==actor: raise DomainError('invalid_block')
        with self.db: self.db.execute('INSERT OR IGNORE INTO blocks VALUES(?,?)',(actor,pet[0]))
        return {'blocked':True,'scope':'human_account_all_pets'}

    def report(self,actor,post_id,reason):
        self.require_actor(actor); self.public_post(post_id,actor)
        if reason not in ('privacy','rights','abuse','other'): raise DomainError('invalid_reason')
        rid=str(uuid4())
        with self.db: self.db.execute('INSERT INTO reports(id,actor,post,reason) VALUES(?,?,?,?)',(rid,actor,post_id,reason))
        return {'received':True,'id':rid}

    def withdraw(self,actor,post_id):
        post=self.db.execute('SELECT * FROM public_posts WHERE id=?',(post_id,)).fetchone()
        if not post: raise DomainError('not_found',404)
        self.owner(actor,post['pet'])
        with self.db: self.db.execute("UPDATE public_posts SET state='withdrawn' WHERE id=?",(post_id,))
        return {'withdrawn':True}

    def invalidate_photo(self,photo_id,purpose=None):
        with self.db:
            for p in self.db.execute('SELECT id,photo_ids,kind FROM public_posts').fetchall():
                required='sns' if p['kind']=='post' else 'external_share'
                if photo_id in json.loads(p['photo_ids']) and (purpose is None or purpose==required): self.db.execute("UPDATE public_posts SET state='withdrawn' WHERE id=?",(p['id'],))

    def consent(self,actor,photo_id,purpose,allowed):
        result=super().consent(actor,photo_id,purpose,allowed)
        if not allowed: self.invalidate_photo(photo_id,purpose)
        return result

    def delete_photo(self,actor,pet_id,photo_id):
        self.photo(actor,photo_id,True)
        result=super().delete_photo(actor,pet_id,photo_id)
        self.invalidate_photo(photo_id)
        return result
