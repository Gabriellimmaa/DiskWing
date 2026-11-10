#!/usr/bin/env python3
"""Install a verified local bundle on the internal disk, preserving the prior app."""
from pathlib import Path
import argparse
import plistlib
import shutil
import subprocess
import uuid

BUNDLE_ID = 'com.cachessd.app'


def identity(app):
    if app.is_symlink() or not app.is_dir():
        raise ValueError('Expected a regular application bundle.')
    with (app / 'Contents/Info.plist').open('rb') as file:
        if plistlib.load(file).get('CFBundleIdentifier') != BUNDLE_ID:
            raise ValueError('Refusing to replace an unrelated application.')


def install(source, output):
    if output.suffix != '.app':
        raise ValueError('The installation destination must be an .app bundle.')
    identity(source)
    parent = output.parent
    parent.mkdir(parents=True, exist_ok=True)
    if parent.absolute() != parent.resolve() or output.is_symlink():
        raise ValueError('Installation paths must not be redirected.')
    # diskutil accepts a device/mount point, not arbitrary folders; df also
    # resolves the APFS Data volume behind a user-directory firmlink.
    device = subprocess.check_output(['/bin/df', '-P', str(parent)], text=True).splitlines()[-1].split()[0]
    volume = plistlib.loads(subprocess.check_output(['/usr/sbin/diskutil', 'info', '-plist', device]))
    if not volume.get('Internal', False):
        raise ValueError('Install DiskWing on internal storage so it can work without an SSD.')
    if output.exists():
        identity(output)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(source)], check=True)
    stage = parent / ('.DiskWing-install-' + str(uuid.uuid4()) + '.app')
    backup = parent / ('.DiskWing-previous-' + str(uuid.uuid4()) + '.app')
    try:
        shutil.copytree(source, stage, symlinks=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(stage)], check=True)
        if output.exists():
            output.rename(backup)
        try:
            stage.rename(output)
        except BaseException:
            if backup.exists():
                backup.rename(output)
            raise
        print(output)
        if backup.exists():
            print('Previous verified application preserved at: ' + str(backup))
    finally:
        if stage.exists():
            shutil.rmtree(stage)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, default=Path.home() / 'Applications/DiskWing.app')
    args = parser.parse_args()
    install(args.source.absolute(), args.output.absolute())
