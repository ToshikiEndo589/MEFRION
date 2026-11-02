import base64
import importlib.util
import json
import unittest
from pathlib import Path

spec=importlib.util.spec_from_file_location('secret_scanner',Path(__file__).parents[1]/'scripts/check_shippable_secrets.py')
scanner=importlib.util.module_from_spec(spec);spec.loader.exec_module(scanner)

class SecretScannerTests(unittest.TestCase):
    def jwt(self,payload):
        encode=lambda p:base64.urlsafe_b64encode(json.dumps(p).encode()).decode().rstrip('=')
        return encode({'alg':'HS256'})+'.'+encode(payload)+'.'+'x'*43
    def test_public_key_allowed_private_and_user_tokens_rejected(self):
        self.assertEqual(scanner.scan_text('sb_'+'publishable_'+'x'*40,'app'),[])
        self.assertEqual(scanner.scan_text(self.jwt({'role':'anon'}),'app'),[])
        for payload in [{'role':'service_role'},{'role':'authenticated','sub':'test-only'},{'sub':'test-only'}]:
            self.assertTrue(scanner.scan_text(self.jwt(payload),'app'))
    def test_provider_keys_private_keys_and_binary_strings_are_rejected(self):
        for value in ['sb_'+'secret_'+'x'*40,'sb'+'p_'+'a'*40,'gh'+'p_'+'x'*40,'github_'+'pat_'+'x'*50,'xkeys'+'ib-'+'x'*70,'xsmtp'+'sib-'+'x'*70,'AK'+'IA'+'A'*16,'-----BEGIN '+'PRIVATE KEY-----']:
            with self.subTest(prefix=value[:5]):
                self.assertTrue(scanner.scan_text('\x00\xff'+value+'\x00','APP/test'))
    def test_report_never_echoes_values(self):
        value='sb_'+'secret_'+'z'*40
        report=scanner.scan_text('test\n'+value,'path')
        self.assertEqual(report[0]['line'],2)
        self.assertNotIn(value,json.dumps(report))
