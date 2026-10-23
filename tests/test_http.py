import json
import threading
import unittest
import urllib.request
import urllib.error
from backend.server import make_server

class HTTPTests(unittest.TestCase):
    def test_dns_rebinding_cannot_read_local_workbench(self):
        request=urllib.request.Request(self.url+'/health',headers={'Host':'untrusted.example'})
        with self.assertRaises(urllib.error.HTTPError) as response:
            urllib.request.urlopen(request)
        self.assertEqual(response.exception.code,403)
        self.assertEqual(json.load(response.exception)['error'],'host_denied')

    def test_report_review_http_role_and_visibility(self):
        report=self.req('/v1/demo/social/report',{'post_id':'demo-post-demo-0','reason':'rights'})[1]['id']
        self.assertEqual(self.req('/v1/demo/managed/reports')[0],403)
        self.assertEqual(self.req('/v1/demo/managed/reports',token='local-editor')[0],403)
        rows=self.req('/v1/demo/managed/reports',token='local-moderator')[1]['reports']
        self.assertEqual(rows[0]['id'],report)
        self.assertNotIn('actor',rows[0])
        body={'report_id':report,'decision':'hide_post','note':'Synthetic HTTP review'}
        self.assertEqual(self.req('/v1/demo/managed/review-report',body,token='local-distributor')[0],403)
        self.assertEqual(self.req('/v1/demo/managed/review-report',body,token='local-moderator')[0],200)
        self.assertEqual(self.req('/v1/demo/social/posts/demo-post-demo-0')[0],404)
        self.assertEqual(self.req('/v1/demo/managed/reports',token='local-moderator')[1]['reports'][0]['state'],'resolved')
    def setUp(self):
        self.srv=make_server(0);self.th=threading.Thread(target=self.srv.serve_forever,daemon=True);self.th.start()
        self.url=f'http://127.0.0.1:{self.srv.server_port}'
    def tearDown(self): self.srv.shutdown();self.th.join();self.srv.server_close();self.srv.store.db.close()
    def req(self,path,body=None,token='local-owner',origin=None):
        headers={'Content-Type':'application/json'}
        if token:headers['Authorization']='Bearer '+token
        if origin:headers['Origin']=origin
        r=urllib.request.Request(self.url+path,data=json.dumps(body).encode() if body is not None else None,headers=headers)
        try:
            with urllib.request.urlopen(r) as res:return res.status,json.load(res)
        except urllib.error.HTTPError as err:return err.code,json.load(err)
    def pet(self): return self.req('/v1/pets',{'name':'試験Pet','species':'dog'})[1]['id']
    def test_album_and_card_full_http_flow(self):
        pet=self.pet()
        r=self.req('/v1/photos',{'pet_id':pet,'items':[{'request_key':'1','asset':'pet-0','captured':'2020'}, {'request_key':'2','asset':'pet-1','captured':None}]})
        self.assertEqual(r[0],200)
        ids=[p['id'] for p in r[1]['results']]
        self.assertEqual(self.req('/v1/cards',{'pet_id':pet,'photo_ids':ids})[0],201)
        self.assertEqual(len(self.req('/v1/albums/'+pet)[1]['photos']),2)
        self.assertEqual(self.req('/v1/photos/delete',{'pet_id':pet,'photo_id':ids[0]})[0],200)
        self.assertEqual(len(self.req('/v1/albums/'+pet)[1]['photos']),1)
    def test_concurrent_retries_do_not_duplicate(self):
        from concurrent.futures import ThreadPoolExecutor
        pet=self.pet()
        body={'pet_id':pet,'items':[{'request_key':'concurrent','asset':'pet-0','captured':None}]}
        with ThreadPoolExecutor(max_workers=8) as pool:
            responses=list(pool.map(lambda _:self.req('/v1/photos',body),range(8)))
        self.assertTrue(all(r[0]==200 for r in responses))
        self.assertEqual(len(self.req('/v1/albums/'+pet)[1]['photos']),1)

    def test_guest_outsider_operator_cannot_access_private(self):
        pet=self.pet()
        for token in [None,'local-outsider','local-operator']:
            self.assertIn(self.req('/v1/albums/'+pet,token=token)[0],[401,404])
        self.assertEqual(self.req('/v1/photos',{'pet_id':pet,'items':[]},token='local-outsider')[0],404)
    def test_managed_api_requires_mock_operator(self):
        for token in [None,'local-owner','local-family']:
            self.assertEqual(self.req('/v1/demo/managed',token=token)[0],403)
        self.assertEqual(len(self.req('/v1/demo/managed',token='local-operator')[1]['profiles']),10)
    def test_managed_http_editor_approval_distributor_and_rate_limit(self):
        rows=[{'id':'http-ops','name':'合成試験','species':'cat','asset':'pet-1'}]
        self.assertEqual(self.req('/v1/demo/managed/create',{'rows':rows,'request_key':'ops'},token='local-owner')[0],403)
        self.assertEqual(self.req('/v1/demo/managed/create',{'rows':rows,'request_key':'ops'},token='local-editor')[0],201)
        profile=self.req('/v1/demo/managed',token='local-editor')[1]['profiles'][-1]
        asset=profile['materials'][0]['id']
        draft=self.req('/v1/demo/managed/draft',{'pet_id':'http-ops','body':'人工イラスト','asset_ids':[asset]},token='local-editor')[1]
        body={'draft_id':draft['id'],'revision':1}
        self.assertEqual(self.req('/v1/demo/managed/approve',body,token='local-editor')[0],403)
        self.assertEqual(self.req('/v1/demo/managed/approve',body,token='local-approver')[0],403)
        rights={'asset_id':asset,'holder':'MEFRION test','scope':'sns','evidence':'design/ASSET_RIGHTS.md'}
        self.assertEqual(self.req('/v1/demo/managed/rights',rights,token='local-approver')[0],200)
        self.assertEqual(self.req('/v1/demo/managed/approve',body,token='local-approver')[0],200)
        self.assertEqual(self.req('/v1/demo/managed/distribute',{**body,'explicit':True},token='local-distributor')[0],200)
        self.assertTrue(any(p['pet_id']=='http-ops' for p in self.req('/v1/demo/feed')[1]['posts']))
        self.assertEqual(self.req('/v1/demo/managed/stop',{'pet_ids':['http-ops']},token='local-distributor')[0],200)
        self.assertFalse(any(p['pet_id']=='http-ops' for p in self.req('/v1/demo/feed')[1]['posts']))
        self.assertEqual(self.req('/v1/demo/managed/audit',token=None)[0],403)
        self.srv.operator_calls['demo-editor']=[__import__('time').monotonic()]*120
        self.assertEqual(self.req('/v1/demo/managed',token='local-editor')[0],429)
    def test_no_public_private_export_endpoint(self):
        self.assertEqual(self.req('/v1/public/posts',{})[0],404)
        self.assertEqual(self.req('/private/original')[0],404)
    def test_input_origin_and_sql_name_safe(self):
        self.assertEqual(self.req('/v1/pets',{'name':'name','species':'bird'})[0],400)
        self.assertEqual(self.req('/v1/pets',{'name':'name','species':'dog'},origin='https://outside.example')[0],403)
        self.assertEqual(self.req('/v1/pets',{'name':"'; DROP TABLE pets; --",'species':'dog'})[0],201)
        self.assertEqual(len(self.req('/v1/pets')[1]['pets']),1)
    def test_twins_http_failure_and_feedback(self):
        for case in ['results','failure','insufficient','poor_photo']:
            r=self.req('/v1/demo/twins',{'species':'dog','scenario':case},token=None)
            self.assertEqual(r[1]['status'],case)
        self.assertEqual(self.req('/v1/demo/feedback',{'choice':'similar'},token=None)[0],201)
        self.assertEqual(self.req('/v1/demo/feedback',{'choice':'free text'},token=None)[0],400)
    def test_static_allowlist_traversal(self):
        self.assertEqual(self.req('/../.env')[0],404)
        with urllib.request.urlopen(self.url+'/') as res:
            self.assertEqual(res.status,200);self.assertIn("frame-ancestors 'none'",res.headers['Content-Security-Policy'])

    def test_family_image_gateway_revokes_immediately(self):
        pet=self.pet()
        invitation=self.req('/v1/demo/family/invite',{'pet_id':pet})[1]
        self.assertEqual(self.req('/v1/demo/family/accept',{'token':invitation['token'],'confirm_scope':True},token='local-family')[0],200)
        photo=self.req('/v1/photos',{'pet_id':pet,'items':[{'request_key':'family','asset':'pet-1','captured':None}]},token='local-family')[1]['results'][0]['id']
        path='/v1/demo/private-images/'+photo
        request=urllib.request.Request(self.url+path,headers={'Authorization':'Bearer local-family'})
        with urllib.request.urlopen(request) as res:
            self.assertEqual(res.headers['Cache-Control'],'no-store')
            self.assertEqual(res.headers['Content-Type'],'image/png')
            self.assertTrue(res.read().startswith(b'\x89PNG'))
        self.assertEqual(self.req(path,token='local-outsider')[0],404)
        self.assertEqual(self.req(path,token=None)[0],401)
        self.req('/v1/demo/family/remove',{'pet_id':pet,'member':'demo-family'})
        self.assertEqual(self.req(path,token='local-family')[0],404)
        self.assertEqual(self.req('/v1/albums/'+pet,token='local-family')[0],404)

    def test_shared_web_escapes_text_and_revokes_on_consent(self):
        pet=self.pet()
        photos=self.req('/v1/photos',{'pet_id':pet,'items':[{'request_key':'a','asset':'pet-0','captured':'2020'},{'request_key':'b','asset':'pet-1','captured':None}]})[1]['results']
        ids=[p['id'] for p in photos]
        self.req('/v1/demo/social/pet-visibility',{'pet_id':pet,'allowed':True,'explicit':True})
        for pid in ids:self.req('/v1/demo/family/consent',{'photo_id':pid,'purpose':'external_share','allowed':True})
        post=self.req('/v1/demo/social/publish',{'pet_id':pet,'photo_ids':ids,'body':'<script>alert(1)</script>','kind':'share','explicit':True})[1]['id']
        with urllib.request.urlopen(self.url+'/shared/'+post) as response:
            page=response.read().decode()
            self.assertNotIn('<script>',page);self.assertIn('&lt;script&gt;',page)
            self.assertNotIn('demo-owner',page)
            for pid in ids:self.assertNotIn(pid,page)
        self.req('/v1/demo/family/consent',{'photo_id':ids[0],'purpose':'external_share','allowed':False})
        self.assertEqual(self.req('/shared/'+post,token=None)[0],404)

    def test_social_http_reaction_block_and_report(self):
        posts=self.req('/v1/demo/feed')[1]['posts'];post=posts[0]
        self.assertEqual(len(posts),10)
        body={'post_id':post['id'],'kind':'like','enabled':True}
        self.req('/v1/demo/social/react',body);self.req('/v1/demo/social/react',body)
        self.assertEqual(self.req('/v1/demo/social/posts/'+post['id'])[1]['likes'],1)
        self.assertEqual(self.req('/v1/demo/social/report',{'post_id':post['id'],'reason':'privacy'})[0],201)
        self.req('/v1/demo/social/block',{'pet_id':post['pet_id']})
        self.assertEqual(self.req('/v1/demo/feed')[1]['posts'],[])
        self.assertEqual(self.req('/v1/demo/social/posts/'+post['id'])[0],404)
