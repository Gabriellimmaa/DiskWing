import copy
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('candidate_qualification', Path(__file__).resolve().parents[2] / 'scripts/qualify_candidate.py')
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


class CandidateQualificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('CACHESSD_TEST_TEMP'))
        self.root = Path(self.temp.name).resolve(); self.workspace = self.root / 'workspace'; self.workspace.mkdir()
        self.output = self.root / 'report.json'; self.archive = self.root / 'candidate.zip'; self.manifest_path = self.root / 'manifest.json'
        self.helper = b'generated helper, never executed by these unit tests'
        self.info = {'CFBundleIdentifier': 'com.cachessd.app', 'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '4',
                     'DiskWingBuildCommit': 'a' * 40, 'DiskWingBuildProfile': 'candidate', 'DiskWingSourceDirty': False}
        self.write_archive()

    def tearDown(self): self.temp.cleanup()

    def write_archive(self, extra=()):
        with zipfile.ZipFile(self.archive, 'w') as archive:
            archive.writestr('DiskWing.app/Contents/Info.plist', plistlib.dumps(self.info))
            archive.writestr('DiskWing.app/Contents/MacOS/CacheSSDHelper', self.helper)
            for name, data, mode in extra:
                item = zipfile.ZipInfo(name); item.create_system = 3; item.external_attr = mode << 16
                archive.writestr(item, data)
        self.candidate = {'commit': 'a' * 40, 'version': '1.0.0', 'buildNumber': '4', 'archiveSHA256': runner.contracts.sha256(self.archive)}
        self.manifest = {'schemaVersion': 1, 'suite': 'diskwing-candidate-v1', 'candidate': self.candidate, 'profile': self.info['DiskWingBuildProfile'],
                         'sourceDirty': self.info['DiskWingSourceDirty'], 'acceptanceOnly': False, 'architecture': 'arm64', 'minimumMacOS': '14.0',
                         'helperSHA256': runner.hashlib.sha256(self.helper).hexdigest(), 'archive': {'fileName': self.archive.name, 'bytes': self.archive.stat().st_size}}
        self.save_manifest()

    def save_manifest(self): self.manifest_path.write_text(json.dumps(self.manifest))

    def lifecycle(self, app, workspace, output):
        self.assertNotEqual(app.parent.parent, self.root)
        self.assertEqual(plistlib.loads((app / 'Contents/Info.plist').read_bytes()), self.info)
        core = {'schemaVersion': 1, 'suite': 'diskwing-portable-acceptance-v1', 'passed': True, 'fixtureDisposition': 'removed',
                'helperSHA256': self.manifest['helperSHA256'], 'checks': [{'id': name, 'status': 'passed'} for name in runner.lifecycle.CHECKS],
                'pendingManualGates': runner.lifecycle.MANUAL_GATES}
        return {'schemaVersion': 1, 'suite': 'diskwing-bundle-lifecycle-v1', 'fixtureDisposition': 'removed', 'core': core,
                'pendingManualGates': runner.lifecycle.MANUAL_GATES, 'passed': True, 'applicationVersion': '1.0.0', 'buildNumber': '4',
                'helperSHA256': self.manifest['helperSHA256'], 'checks': dict.fromkeys(['internalInstallationAndSignature', 'installedHelperAndResources', 'temporaryAppRemovedEvidenceRetained'], True)}

    def qualify(self, expected=None):
        return runner.qualify(self.manifest_path, self.workspace, self.output, expected_candidate=self.candidate if expected is None else expected)

    def test_exact_archive_candidate_can_pass_local_diagnostic_without_release_claim(self):
        before = self.archive.read_bytes()
        with patch.object(runner.lifecycle, 'qualify', side_effect=self.lifecycle) as lifecycle:
            report = self.qualify()
        self.assertTrue(report['passed']); lifecycle.assert_called_once()
        self.assertEqual(report['candidate'], self.candidate); self.assertFalse(report['publicV1Ready'])
        self.assertEqual(report['pendingManualGates'], runner.lifecycle.MANUAL_GATES)
        self.assertEqual(report['fixtureDisposition'], 'removed'); self.assertEqual(list(self.workspace.iterdir()), [])
        self.assertEqual(self.archive.read_bytes(), before); self.assertEqual(self.output.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(str(self.root), self.output.read_text())

    def test_dev_dirty_artifact_remains_explicit_diagnostic_only(self):
        self.info.update(DiskWingBuildProfile='dev', DiskWingSourceDirty=True); self.write_archive()
        with patch.object(runner.lifecycle, 'qualify', side_effect=self.lifecycle): report = self.qualify()
        self.assertTrue(report['passed']); self.assertTrue(report['sourceDirty']); self.assertFalse(report['publicV1Ready'])

    def test_expected_candidate_is_required_and_mismatches_fail_before_extraction(self):
        for expected in [None, {}, dict(self.candidate, commit='b' * 40), dict(self.candidate, version='1.0.1'),
                         dict(self.candidate, buildNumber='5'), dict(self.candidate, archiveSHA256='b' * 64)]:
            with patch.object(runner.subprocess, 'run') as execute:
                with self.assertRaises(ValueError):
                    runner.qualify(self.manifest_path, self.workspace, self.output, expected_candidate=expected)
                execute.assert_not_called()
        self.assertFalse(self.output.exists()); self.assertEqual(list(self.workspace.iterdir()), [])

    def test_malformed_future_preview_and_dirty_candidate_metadata_are_preserved(self):
        original = copy.deepcopy(self.manifest)
        for change in [{'schemaVersion': 99}, {'schemaVersion': True}, {'acceptanceOnly': True}, {'profile': 'unknown'}, {'profile': []}, {'sourceDirty': True}]:
            self.manifest = dict(original, **change); self.save_manifest(); before = self.manifest_path.read_bytes()
            with self.assertRaises(ValueError): self.qualify()
            self.assertEqual(self.manifest_path.read_bytes(), before)
        self.assertFalse(self.output.exists()); self.assertEqual(list(self.workspace.iterdir()), [])

    def test_tampered_archive_never_reaches_extraction_or_installation(self):
        data = self.archive.read_bytes(); self.archive.write_bytes(data[:-1] + bytes([data[-1] ^ 1]))
        with patch.object(runner.subprocess, 'run') as extract, patch.object(runner.lifecycle, 'qualify') as install:
            report = self.qualify(); extract.assert_not_called(); install.assert_not_called()
        self.assertFalse(report['passed']); self.assertEqual(report['failedStage'], 'archive-identity')
        self.assertEqual(report['fixtureDisposition'], 'retained-for-review')

    def test_archive_symlink_is_refused_without_following_it(self):
        target = self.root / 'preserved.zip'; self.archive.rename(target); self.archive.symlink_to(target)
        with patch.object(runner.subprocess, 'run') as execute:
            report = self.qualify(); execute.assert_not_called()
        self.assertFalse(report['passed']); self.assertEqual(report['failedStage'], 'archive-identity'); self.assertTrue(target.is_file())

    def test_changed_bundle_identity_cannot_inherit_helper_acceptance(self):
        for field, value in [('CFBundleIdentifier', 'other.application'), ('DiskWingBuildCommit', 'b' * 40), ('CFBundleVersion', '5')]:
            original = self.info[field]; self.info[field] = value; self.write_archive()
            with patch.object(runner.lifecycle, 'qualify') as install:
                report = self.qualify(); install.assert_not_called()
            self.assertFalse(report['passed']); self.assertEqual(report['failedStage'], 'bundle-identity')
            self.output.unlink(); self.info[field] = original

    def test_lifecycle_failure_retains_generated_data_and_sanitizes_errors(self):
        sentinel = self.root / 'sentinel'; sentinel.write_text('preserve me')
        with patch.object(runner.lifecycle, 'qualify', side_effect=ValueError(str(self.root))): report = self.qualify()
        self.assertFalse(report['passed']); self.assertEqual(report['failedStage'], 'internal-lifecycle')
        self.assertEqual(len(list(self.workspace.iterdir())), 1); self.assertEqual(sentinel.read_text(), 'preserve me')
        self.assertNotIn(str(self.root), self.output.read_text())

    def test_unknown_or_malformed_lifecycle_cannot_claim_candidate_success(self):
        for report in [{'schemaVersion': 2, 'passed': True}, {'schemaVersion': 1, 'passed': True}, None]:
            with patch.object(runner.lifecycle, 'qualify', return_value=report): result = self.qualify()
            self.assertFalse(result['passed']); self.assertEqual(result['failedStage'], 'internal-lifecycle')
            self.output.unlink()

    def test_low_fixture_space_refuses_copy_and_preserves_original_archive(self):
        before = self.archive.read_bytes()
        with patch.object(runner.shutil, 'disk_usage', return_value=runner.shutil._ntuple_diskusage(10, 9, 1)), patch.object(runner, 'snapshot_archive') as snapshot:
            report = self.qualify(); snapshot.assert_not_called()
        self.assertFalse(report['passed']); self.assertEqual(self.archive.read_bytes(), before)

    def test_existing_reports_and_links_block_before_work(self):
        self.output.write_text('existing private evidence')
        with patch.object(runner, 'snapshot_archive') as snapshot:
            with self.assertRaises(ValueError): self.qualify()
            snapshot.assert_not_called()
        self.assertEqual(self.output.read_text(), 'existing private evidence')
        self.output.unlink(); target = self.root / 'existing.json'; target.write_text('preserved'); self.output.symlink_to(target)
        with self.assertRaises(ValueError): self.qualify()
        self.assertEqual(target.read_text(), 'preserved'); self.assertEqual(list(self.workspace.iterdir()), [])

    def test_zip_traversal_duplicate_case_alias_and_special_files_are_rejected(self):
        cases = [('DiskWing.app/../../escape', stat.S_IFREG), ('/escape', stat.S_IFREG), ('DiskWing.app\\escape', stat.S_IFREG),
                 ('C:/escape', stat.S_IFREG), ('DiskWing.app/Contents/info.plist', stat.S_IFREG), ('DiskWing.app/fifo', stat.S_IFIFO)]
        for name, mode in cases:
            self.write_archive([(name, b'generated', mode | 0o600)])
            with self.assertRaises(ValueError, msg=name): runner.validate_zip(self.archive)
        self.assertFalse((self.root / 'escape').exists())

    def test_zip_links_cannot_escape_cycle_or_receive_descendant_writes(self):
        mode = stat.S_IFLNK | 0o777
        cases = [[('DiskWing.app/Contents/link', '../../escape', mode)],
                 [('DiskWing.app/Contents/link', '/tmp/outside', mode)],
                 [('DiskWing.app/a', 'b', mode), ('DiskWing.app/b', 'a', mode)],
                 [('DiskWing.app/Contents/link', 'MacOS', mode), ('DiskWing.app/Contents/LINK/escape', b'generated', stat.S_IFREG | 0o600)]]
        for entries in cases:
            self.write_archive(entries)
            with self.assertRaises(ValueError): runner.validate_zip(self.archive)

    def test_internal_framework_links_survive_ditto_and_remain_inside_application(self):
        base = 'DiskWing.app/Contents/Frameworks/Sparkle.framework/'
        self.write_archive([(base + 'Versions/A/Sparkle', b'generated framework', stat.S_IFREG | 0o755),
                            (base + 'Versions/Current', 'A', stat.S_IFLNK | 0o777),
                            (base + 'Sparkle', 'Versions/Current/Sparkle', stat.S_IFLNK | 0o777)])
        self.assertEqual(runner.validate_zip(self.archive), 'DiskWing.app')
        folder = self.root / 'extracted'; folder.mkdir()
        subprocess.run(['/usr/bin/ditto', '-x', '-k', str(self.archive), str(folder)], check=True, capture_output=True)
        app = folder / 'DiskWing.app'; runner.validate_extracted(app)
        link = app / 'Contents/Frameworks/Sparkle.framework/Sparkle'
        self.assertTrue(link.is_symlink()); self.assertEqual(link.read_bytes(), b'generated framework')

    def test_zip_resource_limits_and_alternate_path_metadata_are_rejected(self):
        with patch.object(runner, 'MAX_EXPANDED', 1):
            with self.assertRaises(ValueError): runner.validate_zip(self.archive)
        with patch.object(runner, 'MAX_MEMBERS', 1):
            with self.assertRaises(ValueError): runner.validate_zip(self.archive)
        with zipfile.ZipFile(self.archive, 'a') as archive:
            entry = zipfile.ZipInfo('DiskWing.app/hardlink'); entry.extra = b'\x0d\x00\x00\x00'
            archive.writestr(entry, b'generated')
        with self.assertRaises(ValueError): runner.validate_zip(self.archive)


if __name__ == '__main__': unittest.main()
