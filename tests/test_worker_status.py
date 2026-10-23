"""A failed scheduler cycle must replace stale success without leaking data."""
import io
import json
import os
import runpy
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent


class WorkerStatusTests(unittest.TestCase):
    def test_missing_configuration_records_failure_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            (root / '.local').mkdir()
            script = root / 'scripts/run_development_workers.py'
            script.write_text((ROOT / 'scripts/run_development_workers.py').read_text())
            status = root / '.local/development-worker-status.json'
            status.write_text(json.dumps({'timestamp': 1, 'failures': 0}))
            output = io.StringIO()
            with patch.object(sys, 'path', [str(ROOT / 'scripts')] + sys.path), patch.dict(os.environ, {'MEFRION_AUTOMATIC_CYCLE': '1'}), redirect_stdout(output):
                with self.assertRaises(SystemExit) as exit_code:
                    runpy.run_path(str(script), run_name='__main__')
                self.assertEqual(exit_code.exception.code, 1)
            report = json.loads(status.read_text())
            self.assertEqual(report['failures'], 1)
            self.assertTrue(report['automatic_local'])
            self.assertGreater(report['timestamp'], 1)
            self.assertFalse((root / '.local/development-worker-status.tmp').exists())
            self.assertEqual(status.stat().st_mode & 0o777, 0o600)
            self.assertNotIn(directory, output.getvalue())
