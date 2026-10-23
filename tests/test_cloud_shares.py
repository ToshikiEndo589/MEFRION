"""Public web boundaries; no network credentials or private-photo fixtures."""
import unittest
from unittest.mock import patch
from backend import cloud_shares

POST='11111111-1111-4111-8111-111111111111'
MEDIA='22222222-2222-4222-8222-222222222222'
class CloudSharesTests(unittest.TestCase):
    def test_withdrawal_during_image_fetch_prevents_response(self):
        public={'media':[{'id':MEDIA}]}
        with patch.object(cloud_shares,'projection',side_effect=[public,None]),patch.object(cloud_shares,'public_request',return_value=b'owned-derived'):
            self.assertIsNone(cloud_shares.image(POST,MEDIA))
        with patch.object(cloud_shares,'projection',return_value={'media':[]}),patch.object(cloud_shares,'public_request') as fetch:
            self.assertIsNone(cloud_shares.image(POST,MEDIA));fetch.assert_not_called()
    def test_guest_html_escapes_names_and_preserves_unknown_dates(self):
        public={'kind':'card','name':'<script>private-name</script>','text':'<img src=x onerror=attack()>','layout':{},'media':[{'id':MEDIA,'captured':None}]}
        with patch.object(cloud_shares,'projection',return_value=public):status,page=cloud_shares.page(POST)
        self.assertEqual(status,200);self.assertIn('日付不明',page);self.assertIn('&lt;script&gt;',page)
        self.assertNotIn('<script>',page);self.assertNotIn('<img src=x',page);self.assertNotIn('family-originals',page)
        with patch.object(cloud_shares,'projection',return_value=None):status,page=cloud_shares.page(POST)
        self.assertEqual(status,404);self.assertIn('この共有は終了しました',page);self.assertNotIn('<img',page)
