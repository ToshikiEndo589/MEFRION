import json
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]


class IndividualManagedPetPlanTests(unittest.TestCase):
    def test_one_name_and_optional_breed_per_photo(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / 'scripts/prepare_stock_seed_individual_pets.py')],
            cwd=ROOT, capture_output=True, text=True, check=True,
        )
        summary = json.loads(result.stdout)
        self.assertEqual((summary['posts'], summary['names']), (50, 50))
        self.assertEqual(summary['breeds_shown'] + summary['breeds_hidden'], 50)
        sql = (ROOT / 'release/stock-seed-plan/stock-50-individual-pets.sql').read_text()
        self.assertNotIn('（推定）', sql)
        self.assertNotIn('犬種未確認', sql)
        self.assertNotIn('猫種未確認', sql)
        self.assertIn("post.state='published'", sql)
        self.assertIn("mefrion_private.post_allowed(item.post_id,null)", sql)


if __name__ == '__main__':
    unittest.main()
