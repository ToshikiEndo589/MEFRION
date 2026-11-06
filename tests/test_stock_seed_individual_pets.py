import json
from pathlib import Path
import subprocess
import sys
import unittest
import csv
import contextlib
import importlib.util
import io
import tempfile
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


class IndividualManagedPetPlanTests(unittest.TestCase):
    def test_one_name_and_optional_breed_per_photo(self):
        # CI must not depend on an operator's private .local catalogue.
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)
            records = fixture / '.local/pexels-pets/records'
            records.mkdir(parents=True)
            rows = []
            for index in range(70):
                species = 'dog' if index < 45 else 'cat'
                rows.append({'asset_id': f'pexels-{index}', 'species': species, 'source_page': f'https://example.invalid/{index}'})
                (records / f'{index}.json').write_text(json.dumps({'source_page': rows[-1]['source_page'], 'species_hint': species, 'alt': 'synthetic animal'}))
            queue = fixture / 'queue.csv'
            with queue.open('w', newline='') as stream:
                writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
            state = fixture / 'state.json'
            state.write_text(json.dumps({'status': 'published_verified', 'pets': ['00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002'], 'asset_ids': [row['asset_id'] for row in rows[20:]]}))
            output = fixture / 'plan.sql'
            sys.path.insert(0, str(ROOT / 'scripts'))
            try:
                spec = importlib.util.spec_from_file_location('individual_plan_fixture', ROOT / 'scripts/prepare_stock_seed_individual_pets.py')
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                capture = io.StringIO()
                with patch.multiple(module, ROOT=fixture, ROWS=queue, STATE=state, OUT=output, EXPLICIT={}), contextlib.redirect_stdout(capture):
                    module.main()
                summary = json.loads(capture.getvalue())
                sql = output.read_text()
            finally:
                sys.path.pop(0)
        self.assertEqual((summary['posts'], summary['names']), (50, 50))
        self.assertEqual(summary['breeds_shown'] + summary['breeds_hidden'], 50)
        self.assertNotIn('（推定）', sql)
        self.assertNotIn('犬種未確認', sql)
        self.assertNotIn('猫種未確認', sql)
        self.assertIn("post.state='published'", sql)
        self.assertIn("mefrion_private.post_allowed(item.post_id,null)", sql)


if __name__ == '__main__':
    unittest.main()
