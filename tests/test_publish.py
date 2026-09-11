"""Publication gates without network calls. Author: Neil Mitchell."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import publish_preview

ENV = {'GITHUB_ACTIONS': 'true', 'GITHUB_REF': 'refs/heads/main',
       'GITHUB_REPOSITORY': 'test/suite', 'GITHUB_SHA': 'fixture-commit',
       'RELEASE_TAG': 'v2.0.0-alpha.1'}


def check(name, conclusion='success', status='completed'):
    return {'name': name, 'conclusion': conclusion, 'status': status, 'app': {'slug': 'github-actions'}}


class PublishGates(unittest.TestCase):
    def test_rejects_local_branch_and_wrong_tag_before_network(self):
        for change in [{'GITHUB_ACTIONS': 'false'}, {'GITHUB_REF': 'refs/heads/other'}, {'RELEASE_TAG': 'v2.0.0'}]:
            with self.subTest(change=change), patch.dict('os.environ', ENV | change, clear=True), patch.object(publish_preview, 'gh') as gh:
                with self.assertRaises(ValueError): publish_preview.main()
                gh.assert_not_called()

    def test_windows_gate_blocks_before_release_actions(self):
        for windows in [None, check('validate (windows-latest)', 'failure'), check('validate (windows-latest)', None, 'in_progress')]:
            results = [check('validate (ubuntu-latest)')]
            if windows: results.append(windows)
            with self.subTest(windows=windows), patch.dict('os.environ', ENV, clear=True), patch.object(
                publish_preview, 'gh', return_value=json.dumps([{'check_runs': results}])) as gh:
                with self.assertRaisesRegex(ValueError, 'exact-commit'): publish_preview.main()
                self.assertEqual(gh.call_count, 1)
                self.assertIn('/commits/fixture-commit/check-runs', gh.call_args.args[-1])

    def test_existing_release_cannot_be_overwritten(self):
        checks = [{'check_runs': [check('validate (ubuntu-latest)'), check('validate (windows-latest)')]}]
        with patch.dict('os.environ', ENV, clear=True), patch.object(publish_preview, 'gh', side_effect=[
            json.dumps(checks), json.dumps([[{'tag_name': 'v2.0.0-alpha.1'}]])]) as gh:
            with self.assertRaisesRegex(ValueError, 'already exists'): publish_preview.main()
            self.assertEqual(gh.call_count, 2)


if __name__ == '__main__': unittest.main()
