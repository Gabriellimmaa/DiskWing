import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[2] / 'scripts/install_local.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallationTests(unittest.TestCase):
    def fixture(self, base):
        source = base / 'source.app'
        (source / 'Contents').mkdir(parents=True)
        (source / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.cachessd.app'}))
        return source, base / 'installed/DiskWing.app'

    def test_external_volume_is_rejected_before_copying(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = self.fixture(Path(directory).resolve())
            with patch.object(installer.subprocess,'check_output',side_effect=['Filesystem 512-blocks Used Available Capacity Mounted on\n/dev/disk9s1 100 10 90 10% /volume\n',plistlib.dumps({'Internal':False})]):
                with self.assertRaises(ValueError): installer.install(source,output)
            self.assertFalse(output.exists())

    def test_existing_app_is_preserved_and_volume_uses_device_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = self.fixture(Path(directory).resolve())
            output.mkdir(parents=True)
            (output/'Contents').mkdir()
            (output/'Contents/Info.plist').write_bytes((source/'Contents/Info.plist').read_bytes())
            (output/'previous').write_text('preserve')
            with patch.object(installer.subprocess,'check_output',side_effect=['Filesystem 512-blocks Used Available Capacity Mounted on\n/dev/disk3s5 100 10 90 10% /System/Volumes/Data\n',plistlib.dumps({'Internal':True})]) as query, patch.object(installer.subprocess,'run'):
                installer.install(source,output)
                self.assertEqual(query.call_args_list[1].args[0][-1],'/dev/disk3s5')
            backups = list(output.parent.glob('.DiskWing-previous-*.app'))
            self.assertEqual(len(backups),1)
            self.assertEqual((backups[0]/'previous').read_text(),'preserve')
            self.assertFalse((output/'previous').exists())

    def test_non_app_destination_is_refused(self):
        with self.assertRaises(ValueError): installer.install(Path('missing.app'),Path('Documents'))
