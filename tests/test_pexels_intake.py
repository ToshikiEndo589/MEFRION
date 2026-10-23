import importlib.util
import io
from pathlib import Path
import unittest
from PIL import Image

spec = importlib.util.spec_from_file_location('pexels_intake', Path(__file__).resolve().parents[1]/'scripts/collect_pexels_assets.py')
intake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(intake)

class PexelsIntakeTests(unittest.TestCase):
    def test_source_validation_rejects_credentials_and_foreign_hosts(self):
        for url in ('http://images.pexels.com/a', 'https://images.pexels.com.evil.test/a',
                    'https://secret@images.pexels.com/a', 'https://images.pexels.com:444/a'):
            with self.assertRaises(ValueError):
                intake.safe_url(url, 'images.pexels.com')
        self.assertEqual(intake.safe_url('https://images.pexels.com/a', 'images.pexels.com'), 'https://images.pexels.com/a')

    def test_normalization_preserves_aspect_and_limits_pixels(self):
        source = io.BytesIO()
        Image.new('RGB', (2400, 1200), 'orange').save(source, format='JPEG')
        image = intake.normalize(source.getvalue())
        self.assertEqual(image.size, (1024, 512))
        self.assertEqual(image.mode, 'RGB')
        self.assertEqual(len(intake.dhash(image)), 16)

    def test_small_or_invalid_images_rejected(self):
        source = io.BytesIO()
        Image.new('RGB', (100, 100)).save(source, format='PNG')
        with self.assertRaises(ValueError):
            intake.normalize(source.getvalue())
        with self.assertRaises(Exception):
            intake.normalize(b'not an image')

    def test_redirect_refused_before_forwarding_authorization(self):
        with self.assertRaises(ValueError):
            intake.NoRedirect().redirect_request(None, None, 302, 'Found', {}, 'https://other.test')

if __name__ == '__main__':
    unittest.main()
