import json
import os
import threading
import unittest
import urllib.request
from unittest.mock import patch
from backend.fixtures import PETS, feed
from backend.server import make_server

class PhaseZeroTests(unittest.TestCase):
    def test_owned_demo_fixtures_and_no_fake_reactions(self):
        self.assertEqual(len(PETS), 10)
        self.assertEqual(len({p['id'] for p in PETS}), 10)
        for p in PETS:
            self.assertTrue(p['demo_only'])
            self.assertEqual(p['rights'], 'project-owned-procedural-illustration')
        for p in feed():
            self.assertEqual((p['likes'],p['comments']), (0,0))
            self.assertNotIn('publisher_id',p)
            self.assertNotIn('rights',p)

    def test_production_and_nonloopback_refused(self):
        with patch.dict(os.environ, {'MEFRION_ENV':'production'}):
            with self.assertRaises(RuntimeError): make_server(0)
        with patch.dict(os.environ, {'MEFRION_HOST':'0.0.0.0'}):
            with self.assertRaises(RuntimeError): make_server(0)

    def test_real_http_health_feed_and_private_path_not_found(self):
        with make_server(0) as srv:
            th=threading.Thread(target=srv.serve_forever,daemon=True); th.start()
            try:
                url=f'http://127.0.0.1:{srv.server_port}'
                with urllib.request.urlopen(url+'/health') as r:
                    self.assertEqual(r.headers['Cache-Control'],'no-store')
                    self.assertFalse(json.load(r)['production_ready'])
                with urllib.request.urlopen(url+'/v1/demo/feed') as r:
                    self.assertEqual(len(json.load(r)['posts']),10)
                with self.assertRaises(urllib.error.HTTPError) as err:
                    urllib.request.urlopen(url+'/private/anything')
                self.assertEqual(err.exception.code,404)
            finally: srv.shutdown(); th.join()
