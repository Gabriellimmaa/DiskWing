import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('qualification', Path(__file__).resolve().parents[2] / 'scripts/qualify_bundle.py')
qualification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qualification)


class QualificationTests(unittest.TestCase):
    def core(self, helper_hash='a' * 64):
        return {'schemaVersion': 1, 'suite': 'diskwing-portable-acceptance-v1', 'passed': True,
                'fixtureDisposition': 'removed', 'helperSHA256': helper_hash,
                'checks': [{'id': name, 'status': 'passed'} for name in qualification.CHECKS],
                'pendingManualGates': qualification.MANUAL_GATES}

    def fixture(self, root):
        app = root / 'source.app'
        (app / 'Contents/MacOS').mkdir(parents=True)
        (app / 'Contents/MacOS/CacheSSDHelper').write_bytes(b'generated-fixture-helper')
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.cachessd.app', 'CFBundleShortVersionString': '0.2.0-dev', 'CFBundleVersion': '3'}))
        workspace = root / 'workspace'; workspace.mkdir()
        return app, workspace, root / 'report.json'

    def test_incomplete_or_different_build_evidence_never_passes(self):
        for value in [None, [], {}, {'passed': True}, self.core('b' * 64)]:
            self.assertFalse(qualification.validate_core(value, 'a' * 64))
        report = self.core(); self.assertTrue(qualification.validate_core(report, 'a' * 64))
        report['pendingManualGates'] = []
        self.assertFalse(qualification.validate_core(report, 'a' * 64))
        report = self.core(); report['checks'][0]['status'] = 'failed'
        self.assertFalse(qualification.validate_core(report, 'a' * 64))

    def test_reports_are_private_and_existing_evidence_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve() / 'report.json'
            qualification.new_report(output, {'passed': False})
            original = output.read_bytes()
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError): qualification.new_report(output, {})
            link = output.with_name('link.json'); link.symlink_to(output)
            with self.assertRaises(FileExistsError): qualification.new_report(link, {})
            self.assertEqual(output.read_bytes(), original)

    def test_install_failure_retains_generated_evidence_without_leaking_command_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); app, workspace, output = self.fixture(root)
            error = subprocess.CalledProcessError(1, ['private-command'], stderr=b'/private-user/secret')
            with patch.object(qualification.subprocess, 'run', side_effect=error):
                report = qualification.qualify(app, workspace, output)
            self.assertFalse(report['passed']); self.assertEqual(report['failedStage'], 'install')
            self.assertEqual(len(list(workspace.iterdir())), 1)
            self.assertNotIn('private-user', output.read_text())
            self.assertNotIn(str(root), output.read_text())
            self.assertTrue(app.exists())

    def test_complete_mock_lifecycle_removes_only_its_generated_installation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); app, workspace, output = self.fixture(root)
            sentinel = workspace / 'keep.txt'; sentinel.write_text('keep')
            def run(command, **options):
                if command[1].endswith('install_local.py'):
                    shutil.copytree(app, Path(command[-1]))
                else:
                    self.assertEqual(options['env']['PATH'], '/usr/bin:/bin:/usr/sbin:/sbin')
                    report = self.core(qualification.digest(app / 'Contents/MacOS/CacheSSDHelper'))
                    Path(command[-1]).write_text(json.dumps(report))
                return subprocess.CompletedProcess(command, 0)
            with patch.object(qualification.subprocess, 'run', side_effect=run):
                report = qualification.qualify(app, workspace, output)
            self.assertTrue(report['passed']); self.assertEqual(report['fixtureDisposition'], 'removed')
            self.assertEqual(list(workspace.iterdir()), [sentinel]); self.assertEqual(sentinel.read_text(), 'keep')
            self.assertTrue(app.exists())
            self.assertEqual(report['pendingManualGates'], qualification.MANUAL_GATES)

    def test_existing_report_blocks_work_before_installation(self):
        with tempfile.TemporaryDirectory() as directory:
            app, workspace, output = self.fixture(Path(directory).resolve()); output.write_text('keep')
            with patch.object(qualification.subprocess, 'run') as run:
                with self.assertRaises(ValueError): qualification.qualify(app, workspace, output)
                run.assert_not_called()
            self.assertEqual(output.read_text(), 'keep'); self.assertEqual(list(workspace.iterdir()), [])
