#!/usr/bin/env python3
"""Qualify the exact reviewed ZIP using a private, temporary internal installation."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import tempfile
import unicodedata
import zipfile


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


contracts = module('candidate_evidence', 'release_evidence.py')
lifecycle = module('candidate_lifecycle', 'qualify_bundle.py')
MAX_ARCHIVE = 536_870_912
MAX_EXPANDED = 1_073_741_824
MAX_MEMBERS = 100_000


def key(path):
    # APFS may ignore case and canonical Unicode spelling. Check that namespace too.
    return unicodedata.normalize('NFD', path).casefold()


def parts(name):
    if (not isinstance(name, str) or not name or '\\' in name or ':' in name
            or any(ord(char) < 32 or ord(char) == 127 for char in name)):
        raise ValueError('Unsupported ZIP path.')
    value = name.rstrip('/')
    segments = value.split('/')
    if not value or any(segment in {'', '.', '..'} for segment in segments): raise ValueError('Unsafe ZIP path.')
    return segments


def validate_zip(path):
    """Allow one application and ditto metadata; reject writes through any link."""
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if not entries or len(entries) > MAX_MEMBERS or sum(item.file_size for item in entries) > MAX_EXPANDED:
            raise ValueError('ZIP resource limit exceeded.')
        names, links, roots = {}, {}, set()
        for item in entries:
            components = parts(item.filename)
            if item.create_system != 3 or item.orig_filename != item.filename or item.flag_bits & 1 or item.compress_type not in {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED}:
                raise ValueError('Unsupported ZIP entry.')
            # zipfile checks the local header against the central directory on
            # open; ditto must never see a different filename than we reviewed.
            with archive.open(item): pass
            name = '/'.join(components); normalized = key(name)
            if normalized in names: raise ValueError('Duplicate ZIP path.')
            names[normalized] = name
            if components[0] != '__MACOSX': roots.add(components[0])
            mode = item.external_attr >> 16
            kind = stat.S_IFMT(mode)
            if kind not in {0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK} or mode & 0o7000: raise ValueError('Special ZIP entry.')
            if bool(item.is_dir()) != (kind == stat.S_IFDIR) and kind != 0: raise ValueError('Ambiguous ZIP entry type.')
            # Alternate-path/hard-link extra fields are outside builder's ditto format.
            extra = item.extra
            while extra:
                if len(extra) < 4: raise ValueError('Malformed ZIP metadata.')
                tag, size = struct.unpack('<HH', extra[:4])
                if tag not in {0x0001, 0x5455, 0x5855, 0x7855, 0x7875} or len(extra) < size + 4:
                    raise ValueError('Unsupported ZIP metadata.')
                extra = extra[4 + size:]
            if kind == stat.S_IFLNK:
                if components[0] == '__MACOSX' or item.file_size > 4096: raise ValueError('Unsupported ZIP link.')
                target = archive.read(item).decode('utf-8')
                if not target or target.startswith('/') or '\\' in target or ':' in target or any(ord(c) < 32 for c in target):
                    raise ValueError('Unsafe ZIP link.')
                resolved = components[:-1]
                for component in PurePosixPath(target).parts:
                    if component == '..':
                        if len(resolved) <= 1: raise ValueError('ZIP link escapes application.')
                        resolved.pop()
                    elif component != '.': resolved.append(component)
                links[normalized] = key('/'.join(resolved))
        if len(roots) != 1: raise ValueError('Expected one application root.')
        root = roots.pop()
        if not root.endswith('.app'): raise ValueError('Expected an application archive.')
        normalized_root = key(root)
        for name in names:
            components = name.split('/')
            if any('/'.join(components[:end]) in links for end in range(1, len(components))):
                raise ValueError('ZIP member writes through a link.')
            if components[0] == key('__MACOSX') and len(components) > 1:
                if components[1] not in {normalized_root, '._' + normalized_root}: raise ValueError('Unrelated ZIP metadata.')
        for target in links.values():
            visited = set()
            for _ in range(40):
                if target in visited or not (target == normalized_root or target.startswith(normalized_root + '/')):
                    raise ValueError('Cyclic or escaping ZIP link.')
                visited.add(target)
                components = target.split('/')
                prefix = next(('/'.join(components[:end]) for end in range(1, len(components) + 1)
                               if '/'.join(components[:end]) in links), None)
                if prefix is None: break
                target = links[prefix] + target[len(prefix):]
            else: raise ValueError('ZIP link chain is too deep.')
            if target not in names and not any(name.startswith(target + '/') for name in names):
                raise ValueError('Dangling ZIP link.')
        return root


def snapshot_archive(source, target, expected_size, expected_hash):
    """Verify the bytes subsequently inspected/extracted, without reopening source."""
    before = source.lstat()
    if (not stat.S_ISREG(before.st_mode) or before.st_size != expected_size
            or before.st_size > MAX_ARCHIVE or getattr(before, 'st_flags', 0) & contracts.SF_DATALESS):
        raise ValueError('Invalid candidate archive.')
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as original:
        opened = os.fstat(original.fileno())
        if (not stat.S_ISREG(opened.st_mode) or getattr(opened, 'st_flags', 0) & contracts.SF_DATALESS
                or (opened.st_dev, opened.st_ino, opened.st_size) != (before.st_dev, before.st_ino, before.st_size)):
            raise ValueError('Candidate archive changed.')
        value = hashlib.sha256(); count = 0
        out = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(out, 'wb') as copied:
            for block in iter(lambda: original.read(1_048_576), b''):
                count += len(block)
                if count > expected_size: raise ValueError('Candidate archive changed.')
                value.update(block); copied.write(block)
            copied.flush(); os.fsync(copied.fileno())
    if count != expected_size or value.hexdigest() != expected_hash: raise ValueError('Candidate archive hash mismatch.')


def validate_extracted(app):
    if app.is_symlink() or not app.is_dir(): raise ValueError('Invalid extracted application.')
    for directory, folders, files in os.walk(app, followlinks=False):
        for name in folders + files:
            path = Path(directory) / name
            value = path.lstat()
            if stat.S_ISLNK(value.st_mode):
                if not path.resolve(strict=True).is_relative_to(app): raise ValueError('Extracted link escapes application.')
            elif not (stat.S_ISREG(value.st_mode) or stat.S_ISDIR(value.st_mode)):
                raise ValueError('Invalid extracted entry.')


def qualify(manifest_path, workspace, output, *, expected_candidate, archive_path=None):
    if not contracts.candidate_valid(expected_candidate): raise ValueError('Expected a reviewed candidate identity.')
    manifest = contracts.read_json_file(manifest_path)
    if (not isinstance(manifest, dict) or type(manifest.get('schemaVersion')) is not int or manifest['schemaVersion'] != 1
            or manifest.get('suite') != 'diskwing-candidate-v1' or manifest.get('candidate') != expected_candidate
            or not isinstance(manifest.get('profile'), str) or manifest['profile'] not in {'dev', 'candidate', 'production'} or type(manifest.get('sourceDirty')) is not bool
            or manifest.get('acceptanceOnly') is not False or manifest.get('architecture') != 'arm64' or manifest.get('minimumMacOS') != '14.0'
            or not isinstance(manifest.get('helperSHA256'), str) or re.fullmatch('[0-9a-f]{64}', manifest['helperSHA256']) is None):
        raise ValueError('Candidate manifest does not match the reviewed identity.')
    if manifest['profile'] != 'dev' and manifest['sourceDirty']: raise ValueError('Candidate source is dirty.')
    archive_info = manifest.get('archive')
    if (not isinstance(archive_info, dict) or type(archive_info.get('bytes')) is not int or not 0 < archive_info['bytes'] <= MAX_ARCHIVE
            or not isinstance(archive_info.get('fileName'), str) or parts(archive_info['fileName']) != [archive_info['fileName']]
            or not archive_info['fileName'].endswith('.zip')): raise ValueError('Invalid candidate archive metadata.')
    source = Path(archive_path) if archive_path is not None else Path(manifest_path).parent / archive_info['fileName']
    if source.name != archive_info['fileName']: raise ValueError('Candidate archive filename mismatch.')
    workspace, output = Path(workspace).absolute(), Path(output).absolute()
    if (not workspace.is_dir() or workspace != workspace.resolve(strict=True) or output.exists() or output.is_symlink()
            or output.parent != output.parent.resolve(strict=True) or not output.parent.is_dir()):
        raise ValueError('Use an unlinked workspace and a new private report filename.')
    root = Path(tempfile.mkdtemp(prefix='.DiskWing-candidate-', dir=workspace)); identity = root.stat()
    result = {'schemaVersion': 1, 'suite': 'diskwing-candidate-qualification-v1', 'candidate': dict(expected_candidate),
              'profile': manifest['profile'], 'sourceDirty': manifest['sourceDirty'], 'date': datetime.now(timezone.utc).isoformat(),
              'passed': False, 'publicV1Ready': False, 'checks': {}, 'pendingManualGates': lifecycle.MANUAL_GATES,
              'scope': 'Exact archive; temporary internal installation and generated helper fixtures. No GUI, other physical Mac, public signing/update or human acceptance claim.'}
    stage = 'archive-identity'
    try:
        if shutil.disk_usage(root).free < archive_info['bytes'] + 1_073_741_824: raise ValueError('Insufficient confirmed fixture space.')
        snapshot = root / 'candidate.zip'
        snapshot_archive(source, snapshot, archive_info['bytes'], expected_candidate['archiveSHA256'])
        result['checks']['archiveIdentity'] = True
        stage = 'archive-paths'; app_name = validate_zip(snapshot)
        result['checks']['safeArchivePaths'] = True
        with zipfile.ZipFile(snapshot) as archive: expanded_size = sum(item.file_size for item in archive.infolist())
        if shutil.disk_usage(root).free < expanded_size + 1_073_741_824: raise ValueError('Insufficient confirmed fixture space.')
        extraction = root / 'extracted'; extraction.mkdir(mode=0o700)
        stage = 'extract'
        subprocess.run(['/usr/bin/ditto', '-x', '-k', str(snapshot), str(extraction)], check=True, capture_output=True, timeout=120)
        app = extraction / app_name; validate_extracted(app)
        stage = 'bundle-identity'
        info_path = app / 'Contents/Info.plist'; helper = app / 'Contents/MacOS/CacheSSDHelper'
        if info_path.is_symlink() or helper.is_symlink(): raise ValueError('Redirected bundle identity.')
        with info_path.open('rb') as file: info_bytes = file.read(1_048_577)
        if len(info_bytes) > 1_048_576: raise ValueError('Bundle identity is too large.')
        info = plistlib.loads(info_bytes)
        if not isinstance(info, dict): raise ValueError('Invalid bundle identity.')
        if (info.get('CFBundleIdentifier') != 'com.cachessd.app' or info.get('CFBundleShortVersionString') != expected_candidate['version']
                or info.get('CFBundleVersion') != expected_candidate['buildNumber'] or info.get('DiskWingBuildCommit') != expected_candidate['commit']
                or info.get('DiskWingBuildProfile') != manifest['profile'] or info.get('DiskWingSourceDirty') is not manifest['sourceDirty']
                or contracts.sha256(helper) != manifest['helperSHA256']): raise ValueError('Extracted bundle identity mismatch.')
        result['checks']['extractedBundleIdentity'] = True
        stage = 'internal-lifecycle'
        report = lifecycle.qualify(app, workspace, root / 'lifecycle.json')
        result['lifecycle'] = report
        if (not isinstance(report, dict) or type(report.get('schemaVersion')) is not int or report['schemaVersion'] != 1
                or report.get('suite') != 'diskwing-bundle-lifecycle-v1' or report.get('fixtureDisposition') != 'removed'
                or report.get('passed') is not True or report.get('helperSHA256') != manifest['helperSHA256']
                or report.get('pendingManualGates') != lifecycle.MANUAL_GATES
                or not lifecycle.validate_core(report.get('core'), manifest['helperSHA256'])
                or not isinstance(report.get('checks'), dict)
                or any(report.get('checks', {}).get(check) is not True for check in ['internalInstallationAndSignature', 'installedHelperAndResources', 'temporaryAppRemovedEvidenceRetained'])
                or report.get('applicationVersion') != expected_candidate['version'] or report.get('buildNumber') != expected_candidate['buildNumber']):
            raise ValueError('Candidate lifecycle qualification failed.')
        result['checks']['internalLifecycle'] = True
        stage = 'cleanup-generated-fixtures'
        current = root.lstat()
        if not stat.S_ISDIR(current.st_mode) or (current.st_dev, current.st_ino) != (identity.st_dev, identity.st_ino): raise ValueError('Fixture root changed.')
        shutil.rmtree(root)
        result['fixtureDisposition'] = 'removed'; result['passed'] = True
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile, subprocess.SubprocessError, plistlib.InvalidFileException):
        result['failedStage'] = stage; result['fixtureDisposition'] = 'retained-for-review'
    lifecycle.new_report(output, result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--expected-candidate', type=Path, required=True, help='Reviewed JSON object with commit, version, buildNumber and archiveSHA256.')
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--workspace', type=Path, required=True, help='Existing internal-disk fixture directory.')
    parser.add_argument('--output', type=Path, required=True, help='New private JSON report; never overwritten.')
    args = parser.parse_args()
    try:
        value = qualify(args.manifest, args.workspace, args.output, expected_candidate=contracts.read_json_file(args.expected_candidate), archive_path=args.archive)
    except (OSError, ValueError, RuntimeError):
        parser.exit(2, 'Candidate preflight/report write failed. Check the reviewed identity, manifest and private directories.\n')
    print('DiskWing exact-candidate diagnostic: ' + ('passed' if value['passed'] else 'failed; generated fixtures retained for review'))
    raise SystemExit(0 if value['passed'] else 1)
