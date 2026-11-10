"""Packaging boundaries: the build must never overwrite an unrelated application."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('diskwing_build', Path(__file__).resolve().parents[2] / 'build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class PackagingTests(unittest.TestCase):
    def test_defaults_are_checkout_relative(self):
        args = build.parse_args([])
        self.assertEqual(args.scratch, build.PROJECT / '.build')
        self.assertEqual(args.output, build.PROJECT / 'dist/DiskWing.app')

    def test_existing_cli_options_remain_available(self):
        args = build.parse_args(['--scratch', '/tmp/build', '--configuration', 'debug', '--output', '/tmp/custom.app'])
        self.assertEqual(args.configuration, 'debug')
        self.assertEqual(args.output, Path('/tmp/custom.app'))

    def test_refuses_unidentified_existing_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'DiskWing.app'
            app.mkdir()
            with self.assertRaises(ValueError):
                build.validate_output(app)
            self.assertTrue(app.exists())

    def test_refuses_foreign_app_and_accepts_legacy_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'DiskWing.app'
            contents = app / 'Contents'
            contents.mkdir(parents=True)
            for identifier, accepted in [('org.other.app', False), ('com.cachessd.app', True)]:
                with (contents / 'Info.plist').open('wb') as file:
                    plistlib.dump({'CFBundleIdentifier': identifier}, file)
                if accepted:
                    build.validate_output(app)
                else:
                    with self.assertRaises(ValueError):
                        build.validate_output(app)

    def test_refuses_symlink_output(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'DiskWing.app'
            app.symlink_to(Path(directory) / 'another.app')
            with self.assertRaises(ValueError):
                build.validate_output(app)

    def test_updater_requires_developer_id_https_and_valid_public_key(self):
        import base64
        public_key = base64.b64encode(bytes(range(32))).decode()
        args = build.parse_args(['--with-updater', '--feed-url', 'https://example.org/appcast.xml', '--public-ed-key', public_key])
        with self.assertRaises(ValueError):
            build.release_settings(args)
        args.sign_identity = 'Developer ID Application: Example (TESTTEAM)'
        settings = build.release_settings(args)
        self.assertFalse(settings['SUEnableAutomaticChecks'])
        self.assertFalse(settings['SUAutomaticallyUpdate'])
        self.assertFalse(settings['SUSendProfileInfo'])
        for feed in ['http://example.org/feed', 'https://user:password@example.org/feed', 'https://example.org/feed?token=secret']:
            args.feed_url = feed
            with self.assertRaises(ValueError):
                build.release_settings(args)

    def test_notarization_and_version_fail_before_build(self):
        args = build.parse_args(['--notary-profile', 'example'])
        with self.assertRaises(ValueError):
            build.release_settings(args)
        args = build.parse_args(['--version', 'invalid'])
        with self.assertRaises(ValueError):
            build.release_settings(args)

    def test_local_build_has_no_update_metadata(self):
        self.assertEqual(build.release_settings(build.parse_args([])), {})


if __name__ == '__main__':
    unittest.main()
