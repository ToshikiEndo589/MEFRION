"""Loopback-only fixture API. Fixed demo sessions are NOT production auth."""
import json
import os
import threading
import html
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
from urllib.parse import parse_qs
from .fixtures import PETS, feed
from .domain import Store, DomainError
from .family import FamilyStore
from .social import SocialStore
from .managed import ManagedStore
from . import cloud_shares

ROOT = Path(__file__).resolve().parent.parent
DEMO_SESSIONS = {'Bearer local-owner':'demo-owner', 'Bearer local-family':'demo-family', 'Bearer local-outsider':'demo-outsider'}
OPERATOR_SESSIONS = {'Bearer local-editor':'demo-editor', 'Bearer local-approver':'demo-approver', 'Bearer local-distributor':'demo-distributor', 'Bearer local-moderator':'demo-moderator', 'Bearer local-operator':'demo-editor'}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass

    def respond(self, status, value):
        self.raw(status, json.dumps(value, ensure_ascii=False).encode(), 'application/json; charset=utf-8')

    def raw(self, status, raw, content_type):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        connect="https://pmrvzpuznwzuejbuhaqm.supabase.co" if self.path.split("?")[0]=="/admin/cloud" else ""
        self.send_header('Content-Security-Policy', f"default-src 'self'; img-src 'self' blob:; style-src 'self'; script-src 'self'; connect-src 'self' {connect}; frame-ancestors 'none'")
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers(); self.wfile.write(raw)

    @property
    def actor(self): return DEMO_SESSIONS.get(self.headers.get('Authorization'))

    @property
    def operator_actor(self):
        actor=OPERATOR_SESSIONS.get(self.headers.get('Authorization'))
        self.server.store.operator(actor)
        now=time.monotonic(); recent=self.server.operator_calls.setdefault(actor,[])
        recent[:]=[t for t in recent if t>now-60]
        if len(recent)>=120: raise DomainError('rate_limit',429)
        recent.append(now)
        return actor

    def handle_route(self, method):
        # Loopback binding alone does not prevent browser DNS rebinding.
        if self.headers.get('Host') != f'127.0.0.1:{self.server.server_port}':
            return self.respond(403, {'error':'host_denied'})
        # Browser workbench must be same-origin, credential-free mock sessions.
        origin=self.headers.get('Origin')
        if origin and origin != f'http://127.0.0.1:{self.server.server_port}':
            return self.respond(403, {'error':'origin_denied'})
        path=urlsplit(self.path).path
        try:
            with self.server.domain_lock:
                if method=='GET': return self.get_route(path)
                length=int(self.headers.get('Content-Length','0'))
                if not 0 < length <= 65536: raise DomainError('invalid_body_size',413)
                if self.headers.get('Content-Type','').split(';')[0] != 'application/json': raise DomainError('json_required',415)
                body=json.loads(self.rfile.read(length))
                if not isinstance(body,dict): raise DomainError('object_required')
                return self.post_route(path,body)
        except DomainError as e: return self.respond(e.status, {'error':e.code})
        except (ValueError,TypeError,KeyError): return self.respond(400, {'error':'invalid_request'})

    def do_GET(self): self.handle_route('GET')
    def do_POST(self): self.handle_route('POST')

    def get_route(self,path):
        s=self.server.store
        if path.startswith('/cloud-shared/'):
            parts=path.strip('/').split('/')
            try:
                if len(parts)==2:
                    status,page=cloud_shares.page(parts[1]);return self.raw(status,page.encode(),'text/html; charset=utf-8')
                if len(parts)==4 and parts[2]=='image':
                    image=cloud_shares.image(parts[1],parts[3])
                    return self.raw(200,image,'image/jpeg') if image else self.respond(404,{'error':'share_ended'})
            except (OSError,ValueError,KeyError):return self.respond(503,{'error':'share_unavailable'})
            return self.respond(404,{'error':'not_found'})
        if path=='/health': return self.respond(200,{'product':'MEFRION','mode':'local_mock','production_ready':False})
        if path=='/v1/demo/feed': return self.respond(200,{'mode':'local_mock','posts':s.discovery(self.actor)})
        if path=='/v1/demo/social/following': return self.respond(200,{'posts':s.feed(self.actor,True)})
        if path=='/v1/demo/social/saved': return self.respond(200,{'posts':s.saved(self.actor)})
        if path=='/v1/demo/social/search':
            query=parse_qs(urlsplit(self.path).query).get('q',[''])[0]
            return self.respond(200,{'pets':s.search(query,self.actor)})
        if path.startswith('/v1/demo/social/posts/'):
            return self.respond(200,s.public_post(path.rsplit('/',1)[1],self.actor))
        if path.startswith('/v1/demo/social/comments/'):
            return self.respond(200,{'comments':s.public_comments(path.rsplit('/',1)[1],self.actor)})
        if path.startswith('/shared/') and path!='/shared/demo':
            post=s.public_post(path.rsplit('/',1)[1])
            if post['kind']!='share': raise DomainError('not_found',404)
            pictures=''.join('<figure><img alt="公開を許可した開発イラスト" src="/assets/'+html.escape(p['asset'],quote=True)+'.png"><figcaption>'+html.escape(p['captured'] or '日付不明')+'</figcaption></figure>' for p in post['images'])
            page='<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MEFRION · 思い出カード</title><link rel="stylesheet" href="/shared.css"><main><p class="notice">開発環境の共有プレビュー</p><article><h1>'+html.escape(post['name'])+'</h1><p>あの頃と今</p>'+pictures+'<p>'+html.escape(post['body'])+'</p><strong>MEFRION</strong></article><p>公開は取り消せます。保存された外部画像の回収は保証しません。</p></main></html>'
            return self.raw(200,page.encode(),'text/html; charset=utf-8')
        if path=='/v1/pets': return self.respond(200,{'pets':s.list_pets(self.actor)})
        if path.startswith('/v1/albums/'):
            return self.respond(200,{'photos':s.album(self.actor,path.rsplit('/',1)[1])})
        if path.startswith('/v1/demo/private-images/'):
            photo=s.photo(self.actor,path.rsplit('/',1)[1])
            return self.raw(200,(ROOT/'web/assets'/f"{photo['asset']}.png").read_bytes(),'image/png')
        if path.startswith('/v1/demo/family/notifications/'):
            return self.respond(200,{'notifications':s.notifications(self.actor,path.rsplit('/',1)[1]),'mode':'local_mock'})
        if path=='/v1/demo/managed':
            return self.respond(200,{'profiles':s.list_managed(self.operator_actor),'mode':'local_editorial_fixture'})
        if path=='/v1/demo/managed/posts': return self.respond(200,{'posts':s.admin_posts(self.operator_actor)})
        if path=='/v1/demo/managed/audit': return self.respond(200,{'audit':s.audit_log(self.operator_actor)})
        if path=='/v1/demo/managed/reports': return self.respond(200,{'reports':s.reports_for_review(self.operator_actor)})
        if path=='/v1/development/cloud-public-config':
            config=ROOT/'.local/supabase-public.json'
            if not config.exists(): return self.respond(503,{'error':'not_configured'})
            public=json.loads(config.read_text())
            if public.get('url')!='https://pmrvzpuznwzuejbuhaqm.supabase.co' or not public.get('anon_key','').startswith('sb_publishable_'): return self.respond(503,{'error':'invalid_public_config'})
            return self.respond(200,{'url':public['url'],'anon_key':public['anon_key']})
        static={'/':('web/index.html','text/html; charset=utf-8'),
                '/app.js':('web/app.js','text/javascript; charset=utf-8'),
                '/style.css':('web/style.css','text/css; charset=utf-8'),
                '/shared.css':('web/shared.css','text/css; charset=utf-8'),
                '/admin/cloud':('admin/cloud.html','text/html; charset=utf-8'),
                '/admin-seed.js':('admin/seed.js','text/javascript; charset=utf-8'),
                '/admin-cloud.js':('admin/cloud.js','text/javascript; charset=utf-8'),
                '/admin':('admin/index.html','text/html; charset=utf-8'),
                '/admin.js':('admin/app.js','text/javascript; charset=utf-8'),
                '/admin.css':('admin/style.css','text/css; charset=utf-8'),
                '/shared/demo':('web/shared.html','text/html; charset=utf-8')}
        for i in range(10): static[f'/assets/pet-{i}.png']=(f'web/assets/pet-{i}.png','image/png')
        if path in static:
            file,ct=static[path];return self.raw(200,(ROOT/file).read_bytes(),ct)
        return self.respond(404,{'error':'not_found'})

    def post_route(self,path,b):
        s=self.server.store
        if path.startswith('/v1/demo/managed/'):
            actor=self.operator_actor
            if path.endswith('/preview'): return self.respond(200,{'rows':s.preview_csv(actor,b['csv']) if 'csv' in b else s.preview_profiles(actor,b.get('rows'))})
            if path.endswith('/create'): return self.respond(201,s.create_managed(actor,b.get('rows'),b.get('request_key')))
            if path.endswith('/edit'): return self.respond(200,s.edit_managed(actor,b.get('pet_id'),b.get('revision'),b.get('name'),b.get('species')))
            if path.endswith('/rights'): return self.respond(200,s.register_rights(actor,b.get('asset_id'),b.get('holder'),b.get('scope'),b.get('expires'),b.get('evidence')))
            if path.endswith('/revoke-rights'): return self.respond(200,s.revoke_rights(actor,b.get('asset_id')))
            if path.endswith('/draft'): return self.respond(201,s.draft(actor,b.get('pet_id'),b.get('body',''),b.get('asset_ids'),b.get('draft_id'),b.get('revision')))
            if path.endswith('/approve'): return self.respond(200,s.approve(actor,b.get('draft_id'),b.get('revision')))
            if path.endswith('/distribute'): return self.respond(200,s.distribute(actor,b.get('draft_id'),b.get('revision'),b.get('due'),b.get('explicit',False)))
            if path.endswith('/dispatch'): return self.respond(200,s.dispatch_due(actor))
            if path.endswith('/cancel'): return self.respond(200,s.cancel(actor,b.get('draft_id')))
            if path.endswith('/stop'): return self.respond(200,s.stop_profiles(actor,b.get('pet_ids'),b.get('state','suspended')))
            if path.endswith('/discovery'): return self.respond(200,s.configure_discovery(actor,b.get('managed_fraction')))
            if path.endswith('/review-report'): return self.respond(200,s.review_report(actor,b.get('report_id'),b.get('decision'),b.get('note')))
            return self.respond(404,{'error':'not_found'})
        if path=='/v1/pets': return self.respond(201,s.create_pet(self.actor,b.get('name'),b.get('species')))
        if path=='/v1/photos': return self.respond(200,{'results':s.add_photos(self.actor,b.get('pet_id'),b.get('items'))})
        if path=='/v1/cards': return self.respond(201,s.make_card(self.actor,b.get('pet_id'),b.get('photo_ids')))
        if path=='/v1/photos/delete': return self.respond(200,s.delete_photo(self.actor,b.get('pet_id'),b.get('photo_id')))
        if path=='/v1/demo/family/invite': return self.respond(201,s.invite(self.actor,b.get('pet_id')))
        if path=='/v1/demo/family/accept': return self.respond(200,s.accept(self.actor,b.get('token'),b.get('confirm_scope',False)))
        if path=='/v1/demo/family/cancel': return self.respond(200,s.cancel_invite(self.actor,b.get('invitation_id')))
        if path=='/v1/demo/family/remove': return self.respond(200,s.remove_member(self.actor,b.get('pet_id'),b.get('member')))
        if path=='/v1/demo/family/consent': return self.respond(200,s.consent(self.actor,b.get('photo_id'),b.get('purpose'),b.get('allowed')))
        if path=='/v1/demo/family/frequency': return self.respond(200,s.notification_frequency(self.actor,b.get('pet_id'),b.get('frequency')))
        if path=='/v1/demo/family/removal-request': return self.respond(201,s.request_removal(self.actor,b.get('photo_id')))
        if path=='/v1/demo/family/edit-photo': return self.respond(200,s.edit_photo(self.actor,b.get('photo_id'),b.get('captured')))
        if path=='/v1/demo/social/pet-visibility': return self.respond(200,s.set_pet_public(self.actor,b.get('pet_id'),b.get('allowed'),b.get('explicit',False)))
        if path=='/v1/demo/social/publish': return self.respond(201,s.publish(self.actor,b.get('pet_id'),b.get('photo_ids'),b.get('body',''),b.get('kind','post'),b.get('explicit',False)))
        if path=='/v1/demo/social/react': return self.respond(200,s.react(self.actor,b.get('post_id'),b.get('kind'),b.get('enabled')))
        if path=='/v1/demo/social/follow': return self.respond(200,s.follow(self.actor,b.get('pet_id'),b.get('enabled')))
        if path=='/v1/demo/social/comment': return self.respond(201,s.comment(self.actor,b.get('post_id'),b.get('body'),b.get('parent')))
        if path=='/v1/demo/social/block': return self.respond(200,s.block_pet_owner(self.actor,b.get('pet_id')))
        if path=='/v1/demo/social/report': return self.respond(201,s.report(self.actor,b.get('post_id'),b.get('reason')))
        if path=='/v1/demo/social/withdraw': return self.respond(200,s.withdraw(self.actor,b.get('post_id')))
        if path=='/v1/demo/twins': return self.respond(200,s.twins(b.get('species'),b.get('scenario','results'),b.get('exclude')))
        if path=='/v1/demo/feedback': return self.respond(201,s.feedback(b.get('choice')))
        return self.respond(404,{'error':'not_found'})

def make_server(port=8765, db_path=':memory:'):
    if os.environ.get('MEFRION_ENV','local')!='local': raise RuntimeError('Mock server cannot run outside local environment')
    if os.environ.get('MEFRION_HOST','127.0.0.1')!='127.0.0.1': raise RuntimeError('Mock server must bind loopback only')
    server=ThreadingHTTPServer(('127.0.0.1',port),Handler)
    server.store=ManagedStore(db_path);server.domain_lock=threading.RLock();server.operator_calls={}
    return server

if __name__=='__main__':
    db=Path(os.environ.get('MEFRION_DB','.local/mefrion.sqlite3'))
    db.parent.mkdir(parents=True,exist_ok=True)
    server=make_server(int(os.environ.get('MEFRION_PORT','8765')),str(db))
    print(f'MEFRION local mock: http://127.0.0.1:{server.server_port}',flush=True)
    try: server.serve_forever()
    finally: server.store.db.close();server.server_close()
