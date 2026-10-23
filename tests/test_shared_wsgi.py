import io
import json
import os
import unittest
from unittest.mock import patch
from backend import cloud_shares
from backend.shared_wsgi import application, public_origin
from scripts.check_development_worker import assess

POST = '11111111-1111-4111-8111-111111111111'
MEDIA = '22222222-2222-4222-8222-222222222222'


class SharedGatewayTests(unittest.TestCase):
    def call(self, path, method='GET'):
        captured = []
        body = b''.join(application({'PATH_INFO': path, 'QUERY_STRING': '', 'REQUEST_METHOD': method, 'wsgi.input': io.BytesIO()}, lambda status, headers: captured.append((status, dict(headers)))))
        status, headers = captured[0]
        return int(status.split()[0]), headers, body

    def test_originals_admin_auth_and_mutations_never_contact_upstream(self):
        with patch.object(cloud_shares, 'public_request') as request:
            for path in ['/admin', '/family-originals/x', '/auth/v1/user', '/v1/development/cloud-public-config', '/cloud-shared/invalid']:
                self.assertEqual(self.call(path)[0], 404)
            for method in ['POST', 'PUT', 'PATCH', 'DELETE', 'HEAD']:
                self.assertEqual(self.call('/cloud-shared/' + POST, method)[0], 405)
            self.assertEqual(self.call('/' + 'x' * 3000)[0], 414)
            request.assert_not_called()

    def test_live_page_security_and_absolute_ogp(self):
        with patch.dict(os.environ, {'MEFRION_PUBLIC_ORIGIN': 'https://share.example.test'}), patch.object(cloud_shares, 'page', return_value=(200, '<meta property="og:image" content="/cloud-shared/x">')):
            status, headers, body = self.call('/cloud-shared/' + POST)
        self.assertEqual(status, 200)
        self.assertIn(b'https://share.example.test/cloud-shared/x', body)
        self.assertIn('no-store', headers['Cache-Control'])
        self.assertIn("frame-ancestors 'none'", headers['Content-Security-Policy'])
        self.assertEqual(headers['X-Robots-Tag'], 'noindex, nofollow')

    def test_withdrawal_and_upstream_failure_never_return_photo(self):
        with patch.object(cloud_shares, 'image', return_value=None):
            self.assertEqual(self.call('/cloud-shared/' + POST + '/image/' + MEDIA)[0], 404)
        with patch.object(cloud_shares, 'page', side_effect=OSError('unavailable')):
            status, _, body = self.call('/cloud-shared/' + POST)
            self.assertEqual(status, 503)
            self.assertNotIn(b'<img', body)

    def test_aasa_requires_exact_config_and_only_public_route(self):
        with patch.dict(os.environ, {'MEFRION_PUBLIC_ORIGIN': '', 'MEFRION_ASSOCIATED_APP_ID': ''}):
            self.assertEqual(self.call('/.well-known/apple-app-site-association')[0], 404)
        with patch.dict(os.environ, {'MEFRION_PUBLIC_ORIGIN': 'https://share.example.test', 'MEFRION_ASSOCIATED_APP_ID': 'P24PQABLB8.dev.local.mefrion.prototype'}):
            status, _, body = self.call('/.well-known/apple-app-site-association')
            self.assertEqual(status, 200)
            entry = json.loads(body)['applinks']['details'][0]
            self.assertEqual(entry['components'][0]['/'], '/cloud-shared/*')
        for origin in ['http://share.example.test', 'https://user:pass@share.example.test', 'https://share.example.test/extra', 'https://share.example.test?q=x', 'https://share.example.test:invalid', 'https://bad"host.test']:
            with patch.dict(os.environ, {'MEFRION_PUBLIC_ORIGIN': origin}):
                self.assertIsNone(public_origin())


class WorkerHealthTests(unittest.TestCase):
    def test_only_recent_successful_automatic_cycle_passes(self):
        base = {'timestamp': 1000, 'failures': 0, 'automatic_local': True, 'cloud_schedule': False}
        self.assertTrue(assess(base, now=1100)['healthy'])
        for value in [{}, {**base, 'timestamp': 1200}, {**base, 'timestamp': 800}, {**base, 'failures': 1}, {**base, 'automatic_local': False}]:
            self.assertFalse(assess(value, now=1100)['healthy'])
