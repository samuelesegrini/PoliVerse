"""Boundary checks: phone inputs must never become arbitrary commands or source URLs."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

SCRIPT = Path(__file__).with_name('build.py')
spec = importlib.util.spec_from_file_location('local_build', SCRIPT)
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class BuildInputTests(unittest.TestCase):
    def rejected(self, *args):
        result = subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2, result.stderr)

    def test_shell_and_revision_expressions_are_rejected(self):
        for ref in ['main;touch /tmp/unwanted', '$(whoami)', '--upload-pack=evil', '../main', 'main^{commit}']:
            with self.subTest(ref=ref):
                self.rejected('--ref', ref)

    def test_scheduled_jobs_cannot_select_feature_branches(self):
        self.rejected('--automatic', '--ref', 'feature/unreviewed')

    def test_mac_install_fails_before_any_checkout(self):
        self.rejected('--platform', 'mac', '--install')


if __name__ == '__main__':
    unittest.main()
