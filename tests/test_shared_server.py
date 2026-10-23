import unittest,threading,urllib.request,urllib.error
from unittest.mock import patch
from http.server import ThreadingHTTPServer
from backend.shared_server import Handler
from backend import cloud_shares
POST='11111111-1111-4111-8111-111111111111';MEDIA='22222222-2222-4222-8222-222222222222'
class PublicShareServerTests(unittest.TestCase):
 def setUp(self):self.server=ThreadingHTTPServer(('127.0.0.1',0),Handler);self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start();self.base='http://127.0.0.1:'+str(self.server.server_port)
 def tearDown(self):self.server.shutdown();self.server.server_close();self.thread.join()
 def read(self,path,method='GET'):
  try:q=urllib.request.urlopen(urllib.request.Request(self.base+path,method=method))
  except urllib.error.HTTPError as e:q=e
  with q:return q.status,q.headers,q.read()
 def test_private_admin_and_mutation_routes_are_absent(self):
  with patch.object(cloud_shares,'public_request') as upstream:
   for path in ['/admin','/admin/cloud','/v1/development/cloud-public-config','/family-originals/photo','/cloud-shared/invalid','/cloud-shared/'+POST+'/image/invalid']:
    self.assertEqual(self.read(path)[0],404)
   self.assertEqual(self.read('/cloud-shared/'+POST,'POST')[0],405);upstream.assert_not_called()
 def test_html_is_renderable_and_uncached_and_rechecks_revocation(self):
  with patch.object(cloud_shares,'page',return_value=(200,'<h1>MEFRION</h1>')):
   status,h,b=self.read('/cloud-shared/'+POST);self.assertEqual(status,200);self.assertIn('text/html',h['Content-Type']);self.assertIn('no-store',h['Cache-Control']);self.assertIn("frame-ancestors 'none'",h['Content-Security-Policy'])
  with patch.object(cloud_shares,'image',return_value=None):self.assertEqual(self.read('/cloud-shared/'+POST+'/image/'+MEDIA)[0],404)
  with patch.object(cloud_shares,'page',side_effect=OSError('offline')):
   status,_,b=self.read('/cloud-shared/'+POST);self.assertEqual(status,503);self.assertNotIn(b'<img',b)
