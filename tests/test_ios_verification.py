"""Verification must keep an existing signed checkout intact."""
import io
import runpy
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


class IOSVerificationSafetyTests(unittest.TestCase):
    def run_without_xcode(self, existing):
        unavailable = SimpleNamespace(returncode=1, stdout='')
        with patch('sys.argv', ['scripts/verify_ios.py']), patch('pathlib.Path.exists', return_value=existing), patch('subprocess.run', return_value=unavailable) as commands, redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                runpy.run_path('scripts/verify_ios.py', run_name='__main__')
            self.assertEqual(error.exception.code, 2)
        return [call.args[0] for call in commands.call_args_list]

    def test_existing_project_is_not_regenerated_or_written(self):
        project = Path('ios/MEFRION.xcodeproj/project.pbxproj')
        before = project.read_bytes()
        commands = self.run_without_xcode(True)
        self.assertEqual(commands, [['xcode-select', '-p']])
        self.assertEqual(project.read_bytes(), before)

    def test_missing_project_is_generated_before_xcode_check(self):
        commands = self.run_without_xcode(False)
        self.assertEqual(commands[0][1], 'scripts/generate_xcode_project.py')
        self.assertEqual(commands[1], ['xcode-select', '-p'])
