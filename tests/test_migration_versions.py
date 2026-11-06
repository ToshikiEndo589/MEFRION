import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('migration_check', Path(__file__).resolve().parents[1] / 'scripts/check_migration_versions.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class MigrationVersions(unittest.TestCase):
    def test_conflicting_versions_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ['202611050001_one.sql', '202611050001_two.sql']:
                (Path(directory) / name).write_text('select 1;')
            with self.assertRaisesRegex(ValueError, 'Duplicate migration'):
                module.check(directory)

    def test_repository_has_unique_versions(self):
        self.assertGreater(module.check(Path(__file__).resolve().parents[1] / 'supabase/migrations'), 0)
