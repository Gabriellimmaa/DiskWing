import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('build_release', Path(__file__).resolve().parents[2] / 'build.py')
build = importlib.util.module_from_spec(spec); spec.loader.exec_module(build)
artifacts = build.release_evidence


class ReleaseArtifactTests(unittest.TestCase):
    def test_development_defaults_and_production_guards_are_explicit(self):
        self.assertEqual(build.parse_args([]).profile, 'dev')
        for arguments in [['--profile', 'production'], ['--profile', 'production', '--sign-identity', 'Developer ID Application: Synthetic'],
                          ['--profile', 'production', '--sign-identity', 'Developer ID Application: Synthetic', '--notary-profile', 'synthetic']]:
            with self.assertRaises(ValueError): build.release_settings(build.parse_args(arguments))

    def test_acceptance_bundle_is_dev_only_and_never_enables_updates(self):
        self.assertEqual(build.release_settings(build.parse_args(['--acceptance-bundle'])), {})
        for flags in [['--profile', 'candidate'], ['--profile', 'production'], ['--with-updater'], ['--notary-profile', 'synthetic']]:
            with self.assertRaises(ValueError): build.release_settings(build.parse_args(['--acceptance-bundle'] + flags))

    def test_future_preview_domain_cannot_replace_normal_application(self):
        import plistlib
        with tempfile.TemporaryDirectory(dir=os.environ.get('CACHESSD_TEST_TEMP')) as folder:
            app = Path(folder) / 'DiskWing.app'; (app / 'Contents').mkdir(parents=True)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.cachessd.app'}))
            with self.assertRaises(ValueError): build.validate_output(app, 'com.cachessd.app.acceptance')
            build.validate_output(app)
            self.assertTrue(app.exists())

    def test_candidate_source_requires_clean_committed_identity(self):
        with patch.object(artifacts.subprocess, 'check_output', side_effect=['a' * 40, '']):
            self.assertEqual(artifacts.source_identity(Path('.'), 'candidate'), ('a' * 40, False))
        with patch.object(artifacts.subprocess, 'check_output', side_effect=['a' * 40, ' M fixture']):
            with self.assertRaises(ValueError): artifacts.source_identity(Path('.'), 'candidate')
        with patch.object(artifacts.subprocess, 'check_output', side_effect=FileNotFoundError):
            self.assertEqual(artifacts.source_identity(Path('.'), 'dev'), (None, True))
            with self.assertRaises(ValueError): artifacts.source_identity(Path('.'), 'production')

    def test_full_archive_hash_and_stable_bundle_name_are_recorded_without_paths(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('CACHESSD_TEST_TEMP')) as folder:
            root = Path(folder).resolve(); app = root / '.private-stage/DiskWing.app'
            (app / 'Contents/MacOS').mkdir(parents=True)
            (app / 'Contents/MacOS/CacheSSDHelper').write_bytes(b'synthetic helper, not a signed application')
            path, manifest = artifacts.package_candidate(app, root, commit='a' * 40, dirty=False, version='1.0.0', build_number='4',
                                                        profile='candidate', developer_id=False, notarized=False, updater=False)
            archive = root / manifest['archive']['fileName']
            self.assertEqual(artifacts.sha256(archive), manifest['candidate']['archiveSHA256'])
            self.assertEqual(archive.stat().st_size, manifest['archive']['bytes'])
            self.assertNotIn(str(root), path.read_text())
            with zipfile.ZipFile(archive) as contents:
                self.assertIn('DiskWing.app/Contents/MacOS/CacheSSDHelper', contents.namelist())
            with self.assertRaises(ValueError): artifacts.package_candidate(app, root, commit='a' * 40, dirty=False, version='1.0.0', build_number='4',
                                                                           profile='production', developer_id=True, notarized=False, updater=True)

    def test_notarization_rejection_never_claims_stapling_or_gatekeeper_acceptance(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('CACHESSD_TEST_TEMP')) as folder:
            app = Path(folder) / 'DiskWing.app'; app.mkdir()
            with patch.object(build.subprocess, 'run') as run, patch.object(build.subprocess, 'check_output', return_value='{"status":"Rejected"}'):
                with self.assertRaises(ValueError): build.notarize(app, 'synthetic-test-profile')
            self.assertEqual(len(run.call_args_list), 1)
            self.assertEqual(run.call_args_list[0].args[0][0], 'ditto')
            self.assertTrue(app.exists())

    def test_immutable_artifacts_preserve_existing_files_and_links(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('CACHESSD_TEST_TEMP')) as folder:
            root = Path(folder).resolve(); source = root / 'source'; source.write_text('new')
            existing = root / 'existing'; existing.write_text('keep')
            with self.assertRaises(ValueError): artifacts.immutable_copy(source, existing)
            linked = root / 'linked'; linked.symlink_to(existing)
            with self.assertRaises(ValueError): artifacts.immutable_copy(source, linked)
            self.assertEqual(existing.read_text(), 'keep')
