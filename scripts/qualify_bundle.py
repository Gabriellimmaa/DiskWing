#!/usr/bin/env python3
"""Qualify a temporary internal installation using generated data, never personal settings."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

CHECKS = ['bundled-resources-pt-en', 'indexed-explorer', 'personal-copy-recovery',
          'cache-copy-restore-local-fallback', 'isolated-shell-disable']
MANUAL_GATES = ['second-mac-human-acceptance', 'voiceover-keyboard-pt-en', 'developer-id-notarization',
                'signed-update-accept-reject', 'physical-cable-power-faults', 'ten-person-seven-day-beta']


def validate_core(report, expected_hash):
    """Fail closed if a different/malformed suite is mistaken for acceptance evidence."""
    return (isinstance(report, dict) and report.get('schemaVersion') == 1
            and report.get('suite') == 'diskwing-portable-acceptance-v1'
            and report.get('passed') is True and report.get('fixtureDisposition') == 'removed'
            and report.get('helperSHA256') == expected_hash
            and report.get('checks') == [{'id': name, 'status': 'passed'} for name in CHECKS]
            and report.get('pendingManualGates') == MANUAL_GATES)


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as file:
        for block in iter(lambda: file.read(1048576), b''): value.update(block)
    return value.hexdigest()


def new_report(output, report):
    parent = output.parent
    if parent.absolute() != parent.resolve(strict=True):
        raise ValueError('Report directories must not be redirected.')
    fd = os.open(output, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, 'w') as file:
            json.dump(report, file, indent=2); file.write('\n'); file.flush(); os.fsync(file.fileno())
    except BaseException:
        output.unlink(missing_ok=True)
        raise


def qualify(source, workspace, output):
    source, workspace, output = source.absolute(), workspace.absolute(), output.absolute()
    if not workspace.is_dir() or workspace != workspace.resolve(strict=True) or output.exists() or output.is_symlink():
        raise ValueError('Use an existing unlinked workspace and a new report filename.')
    if output.parent != output.parent.resolve(strict=True) or not output.parent.is_dir():
        raise ValueError('Use an existing unlinked report directory.')
    if source.is_symlink() or not source.is_dir(): raise ValueError('Expected a regular application bundle.')
    info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
    version, build = info.get('CFBundleShortVersionString', ''), info.get('CFBundleVersion', '')
    if (info.get('CFBundleIdentifier') != 'com.cachessd.app'
            or not isinstance(version, str) or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.]+)?', version)
            or not isinstance(build, str) or not build.isdigit()):
        raise ValueError('Expected DiskWing versioned bundle metadata.')
    expected_hash = digest(source / 'Contents/MacOS/CacheSSDHelper')
    root = Path(tempfile.mkdtemp(prefix='.DiskWing-lifecycle-', dir=workspace))
    installed = root / 'Applications/DiskWing.app'
    fixtures = root / 'fixtures'; fixtures.mkdir(mode=0o700)
    core_path = root / 'core-report.json'
    result = {'schemaVersion': 1, 'suite': 'diskwing-bundle-lifecycle-v1', 'date': datetime.now(timezone.utc).isoformat(),
              'applicationVersion': version, 'buildNumber': build, 'helperSHA256': expected_hash,
              'passed': False, 'checks': {}, 'pendingManualGates': MANUAL_GATES,
              'scope': 'Temporary internal app installation; generated same-volume fixtures, simulated SSD/Trash; no GUI, native package install, physical unplug or public signing acceptance'}
    stage = 'install'
    try:
        subprocess.run([sys.executable, str(Path(__file__).with_name('install_local.py')), str(source), '--output', str(installed)],
                       check=True, capture_output=True, timeout=120)
        result['checks']['internalInstallationAndSignature'] = True
        helper = installed / 'Contents/MacOS/CacheSSDHelper'
        stage = 'installed-helper'
        if digest(helper) != expected_hash: raise ValueError('Installed helper differs.')
        subprocess.run([str(helper), 'acceptance-check', '--workspace', str(fixtures), '--output', str(core_path)],
                       cwd=root, env={'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'en_US.UTF-8'}, check=True, capture_output=True, timeout=120)
        core = json.loads(core_path.read_text())
        if not validate_core(core, expected_hash): raise ValueError('Incomplete acceptance evidence.')
        result['core'] = core
        result['checks']['installedHelperAndResources'] = True
        stage = 'remove-temporary-app'
        shutil.rmtree(installed)
        if installed.exists() or not core_path.is_file(): raise ValueError('Removal/evidence check failed.')
        result['checks']['temporaryAppRemovedEvidenceRetained'] = True
        stage = 'cleanup-generated-fixtures'
        shutil.rmtree(root)
        result['fixtureDisposition'] = 'removed'
        result['passed'] = True
    except (OSError, ValueError, subprocess.SubprocessError):
        # Never publish command output, paths or personal identifiers in a portable report.
        result['failedStage'] = stage
        result['fixtureDisposition'] = 'retained-for-review'
    new_report(output, result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--workspace', type=Path, required=True, help='Existing internal-disk fixture directory.')
    parser.add_argument('--output', type=Path, required=True, help='New private JSON report; never overwritten.')
    args = parser.parse_args()
    try:
        report = qualify(args.source, args.workspace, args.output)
    except (OSError, ValueError, plistlib.InvalidFileException):
        parser.exit(2, 'Qualification preflight/report write failed. Check the bundle and use existing writable unlinked directories and a new report filename.\n')
    print('DiskWing automated bundle qualification: ' + ('passed' if report['passed'] else 'failed; generated fixtures retained for review'))
    raise SystemExit(0 if report['passed'] else 1)
