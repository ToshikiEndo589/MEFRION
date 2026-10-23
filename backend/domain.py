"""Executable reference domain for local demo fixtures, not production storage."""
from pathlib import Path
import json
import sqlite3
import time
from datetime import date
from uuid import uuid4
from .fixtures import PETS

POLICY = json.loads((Path(__file__).resolve().parent.parent / 'config/prototype.json').read_text())
LIMITS = {'pets': POLICY['provisional']['pets_per_account'], 'album_batch': POLICY['provisional']['album_batch'],
          'post_images': POLICY['baseline']['public_post_images'], 'post_characters': POLICY['baseline']['public_post_characters']}

class DomainError(Exception):
    def __init__(self, code, status=400):
        self.code, self.status = code, status
        super().__init__(code)

def valid_date(value):
    if value is None: return 'unknown'
    if not isinstance(value, str): raise DomainError('invalid_date')
    try:
        if len(value) == 4:
            if not 1 <= int(value) <= 9999: raise ValueError()
            return 'year'
        if len(value) == 7:
            date.fromisoformat(value+'-01'); return 'month'
        if len(value) == 10:
            date.fromisoformat(value); return 'day'
    except ValueError:
        pass
    raise DomainError('invalid_date')

class Store:
    def __init__(self, path=':memory:'):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS pets(id TEXT PRIMARY KEY, owner TEXT NOT NULL, name TEXT NOT NULL, species TEXT NOT NULL, public INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS photos(id TEXT PRIMARY KEY, pet TEXT NOT NULL REFERENCES pets(id), provider TEXT NOT NULL, asset TEXT NOT NULL, captured TEXT, precision TEXT NOT NULL, request_key TEXT NOT NULL, UNIQUE(pet,request_key));
        CREATE TABLE IF NOT EXISTS cards(id TEXT PRIMARY KEY, pet TEXT NOT NULL REFERENCES pets(id), first TEXT NOT NULL REFERENCES photos(id) ON DELETE CASCADE, second TEXT NOT NULL REFERENCES photos(id) ON DELETE CASCADE, public INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS feedback(id TEXT PRIMARY KEY, choice TEXT NOT NULL);
        ''')
        self.metrics = []

    def require_actor(self, actor):
        if actor not in ('demo-owner', 'demo-family', 'demo-outsider'):
            raise DomainError('authentication_required',401)

    def pet(self, actor, pet_id, write=False):
        self.require_actor(actor)
        p=self.db.execute('SELECT * FROM pets WHERE id=?',(pet_id,)).fetchone()
        if not p or p['owner'] != actor: raise DomainError('not_found',404)
        return dict(p)

    def create_pet(self, actor, name, species):
        self.require_actor(actor)
        if not isinstance(name,str) or not 1 <= len(name.strip()) <= 40 or species not in ('dog','cat'):
            raise DomainError('invalid_pet')
        if self.db.execute('SELECT count(*) FROM pets WHERE owner=?',(actor,)).fetchone()[0] >= LIMITS['pets']:
            raise DomainError('pet_limit',409)
        p={'id':str(uuid4()),'owner':actor,'name':name.strip(),'species':species,'public':False}
        with self.db: self.db.execute('INSERT INTO pets VALUES(?,?,?,?,0)',(p['id'],actor,p['name'],species))
        return p

    def list_pets(self, actor):
        self.require_actor(actor)
        return [dict(p) for p in self.db.execute('SELECT * FROM pets WHERE owner=?',(actor,))]

    def add_photos(self, actor, pet_id, items):
        self.pet(actor,pet_id,True)
        if not isinstance(items,list) or not 1 <= len(items) <= LIMITS['album_batch']:
            raise DomainError('batch_limit')
        # Per-item result allows successful items to survive retries.
        results=[]
        for item in items:
            try:
                if not isinstance(item,dict): raise DomainError('invalid_photo')
                key=item.get('request_key')
                if not isinstance(key,str) or not 1<=len(key)<=100: raise DomainError('invalid_request_key')
                captured=item.get('captured'); precision=valid_date(captured)
                asset=item.get('asset')
                if asset not in {p['asset'] for p in PETS}: raise DomainError('owned_demo_asset_required')
                existing=self.db.execute('SELECT * FROM photos WHERE pet=? AND request_key=?',(pet_id,key)).fetchone()
                if existing:
                    if (existing['asset'],existing['captured']) != (asset,captured): raise DomainError('idempotency_conflict',409)
                    results.append({'id':existing['id'],'status':'already_saved'});continue
                duplicate=self.db.execute('SELECT count(*) FROM photos WHERE pet=? AND asset=?',(pet_id,asset)).fetchone()[0]>0
                if duplicate and item.get('allow_duplicate') is not True:
                    raise DomainError('duplicate_confirmation_required',409)
                pid=str(uuid4())
                with self.db:
                    self.db.execute('INSERT INTO photos VALUES(?,?,?,?,?,?,?)',(pid,pet_id,actor,asset,captured,precision,key))
                results.append({'id':pid,'status':'saved','duplicate':duplicate})
            except DomainError as e:
                results.append({'status':'failed','error':e.code})
        return results

    def album(self, actor, pet_id):
        self.pet(actor,pet_id)
        return [dict(p) for p in self.db.execute('SELECT * FROM photos WHERE pet=? ORDER BY captured IS NULL, captured, id',(pet_id,))]

    def make_card(self, actor, pet_id, photo_ids):
        self.pet(actor,pet_id,True)
        if not isinstance(photo_ids,list) or len(photo_ids)!=2 or len(set(photo_ids))!=2:
            raise DomainError('select_two_distinct_photos')
        ids={p['id'] for p in self.album(actor,pet_id)}
        if not set(photo_ids)<=ids: raise DomainError('not_found',404)
        cid=str(uuid4())
        with self.db: self.db.execute('INSERT INTO cards VALUES(?,?,?,?,0)',(cid,pet_id,*photo_ids))
        return {'id':cid,'photo_ids':photo_ids,'public':False,'aspect':'9:16'}

    def delete_photo(self, actor, pet_id, photo_id):
        self.pet(actor,pet_id,True)
        with self.db:
            self.db.execute('DELETE FROM photos WHERE pet=? AND id=?',(pet_id,photo_id))
        # SQLite cascades private card records. External projections don't exist yet.
        return {'deleted':True}

    def twins(self, species, scenario='results', exclude=None):
        start=time.perf_counter()
        if species not in ('dog','cat') or scenario not in ('results','insufficient','poor_photo','failure'):
            raise DomainError('invalid_twins_input')
        candidates=[]
        if scenario=='results':
            candidates=[{'id':p['id'],'name':p['name'],'species':p['species'],'asset':p['asset'],'demo_only':True}
                        for p in PETS if p['species']==species and p['id']!=exclude and p['public'] and p['twins_consent']][:3]
        result={'status':scenario,'candidates':candidates,'mode':'fixture_not_image_similarity','external_cost_yen':0}
        self.metrics.append({'event':'twins_finished','result':scenario,'duration_ms':(time.perf_counter()-start)*1000,'external_cost_yen':0})
        return result

    def feedback(self, choice):
        if choice not in ('similar','different'): raise DomainError('invalid_feedback')
        fid=str(uuid4())
        with self.db: self.db.execute('INSERT INTO feedback VALUES(?,?)',(fid,choice))
        return {'id':fid,'recorded':True}
