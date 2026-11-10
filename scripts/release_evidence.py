"""Candidate identity and immutable packaging helpers; no credentials or publishing."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile

CANDIDATE_KEYS = {'commit', 'version', 'buildNumber', 'archiveSHA256'}
GATES = ['developerIDVerified', 'notarizationStapled', 'signedUpdaterVerified', 'secondMacRecoveryVerified',
         'minimumMacOSVerified', 'voiceOverVerified', 'keyboardVerified', 'bothLanguagesVerified', 'physicalFaultRecoveryVerified']
HUMAN_GATES = {'secondMacRecoveryVerified', 'minimumMacOSVerified', 'voiceOverVerified', 'keyboardVerified',
               'bothLanguagesVerified', 'physicalFaultRecoveryVerified'}
PARTICIPANT_CHECKS = ['independentTaskSuccess', 'dataPreserved', 'worksWithoutSSD', 'sevenDayDiaryComplete']
SF_DATALESS = 0x40000000  # Darwin placeholder content must not be hydrated during verification.


def timestamp(value):
    if not isinstance(value, str): raise ValueError('Expected a timezone-qualified timestamp.')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None: raise ValueError('Expected a timezone-qualified timestamp.')
    return parsed.astimezone(timezone.utc)


def candidate_valid(value, allow_unversioned=False):
    if not isinstance(value, dict) or set(value) != CANDIDATE_KEYS: return False
    return ((allow_unversioned and value['commit'] is None or isinstance(value['commit'], str) and re.fullmatch(r'[0-9a-f]{40}', value['commit']) is not None)
            and isinstance(value['version'], str) and re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.]+)?', value['version']) is not None
            and isinstance(value['buildNumber'], str) and re.fullmatch(r'[0-9]{1,18}', value['buildNumber']) is not None and int(value['buildNumber']) > 0
            and isinstance(value['archiveSHA256'], str) and re.fullmatch(r'[0-9a-f]{64}', value['archiveSHA256']) is not None)


def sha256(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as file:
        for block in iter(lambda: file.read(1048576), b''): value.update(block)
    return value.hexdigest()


def source_identity(project, profile):
    try:
        commit = subprocess.check_output(['git', '-C', str(project), 'rev-parse', 'HEAD'], text=True, stderr=subprocess.DEVNULL).strip()
        dirty = bool(subprocess.check_output(['git', '-C', str(project), 'status', '--porcelain', '--untracked-files=normal'], text=True))
        if not re.fullmatch(r'[0-9a-f]{40}', commit): raise ValueError('Unsupported Git commit identity.')
    except (subprocess.CalledProcessError, OSError):
        commit, dirty = None, True
    if profile != 'dev' and (not commit or dirty):
        raise ValueError('Candidate/production packaging requires a clean committed checkout.')
    return commit, dirty


def immutable_copy(source, target):
    source, target = Path(source), Path(target)
    if target.exists() or target.is_symlink():
        if target.is_symlink() or not target.is_file() or sha256(target) != sha256(source):
            raise ValueError('Refusing to replace an existing artifact.')
        return
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, 'wb') as output, source.open('rb') as original:
            shutil.copyfileobj(original, output, 1048576); output.flush(); os.fsync(output.fileno())
    except BaseException:
        target.unlink(missing_ok=True)
        raise


def package_candidate(app, directory, *, commit, dirty, version, build_number, profile, developer_id, notarized, updater, acceptance=False):
    """Archive the stable application basename after signing/stapling, before output swap."""
    app, directory = Path(app), Path(directory)
    if profile == 'production' and (dirty or not developer_id or not notarized or acceptance):
        raise ValueError('Production artifacts require clean source and verified Developer ID/notarization.')
    with tempfile.TemporaryDirectory(prefix='.DiskWing-package-', dir=directory) as temporary:
        folder = Path(temporary)
        archive = folder / 'candidate.zip'
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
        digest = sha256(archive)
        candidate = {'commit': commit, 'version': version, 'buildNumber': build_number, 'archiveSHA256': digest}
        if not candidate_valid(candidate, allow_unversioned=profile == 'dev'): raise ValueError('Invalid candidate identity.')
        stem = 'DiskWing-' + version + '-' + build_number + '-' + digest
        destination = directory / (stem + '.zip')
        manifest_path = directory / (stem + '.manifest.json')
        manifest = {'schemaVersion': 1, 'suite': 'diskwing-candidate-v1', 'candidate': candidate, 'profile': profile,
                    'sourceDirty': dirty, 'acceptanceOnly': acceptance, 'architecture': 'arm64', 'minimumMacOS': '14.0',
                    'builtAt': datetime.now(timezone.utc).isoformat(),
                    'archive': {'fileName': destination.name, 'bytes': archive.stat().st_size},
                    'helperSHA256': sha256(app / 'Contents/MacOS/CacheSSDHelper'),
                    'verification': {'signatureVerified': True, 'developerID': developer_id,
                                     'notarizationAccepted': notarized, 'notarizationStapled': notarized,
                                     'gatekeeperAccepted': notarized, 'updaterEnabled': updater}}
        immutable_copy(archive, destination)
        if manifest_path.exists() or manifest_path.is_symlink():
            if manifest_path.is_symlink(): raise ValueError('Refusing a redirected candidate manifest.')
            previous = json.loads(manifest_path.read_text())
            for key in ['candidate', 'profile', 'sourceDirty', 'acceptanceOnly', 'architecture', 'minimumMacOS', 'archive', 'helperSHA256', 'verification']:
                if previous.get(key) != manifest[key]: raise ValueError('Existing manifest belongs to different candidate metadata.')
            manifest = previous
        else:
            staged = folder / 'manifest.json'; staged.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
            immutable_copy(staged, manifest_path)
    return manifest_path, manifest


def _unique_fields(pairs):
    result = {}
    for key, value in pairs:
        if key in result: raise ValueError('Duplicate evidence field.')
        result[key] = value
    return result


def _reject_constant(value):
    raise ValueError('Non-finite JSON values are unsupported.')


def read_json_file(path, limit=8_388_608, *, expected_sha256=None):
    """Hash and parse the same bounded snapshot; never reopen reviewed evidence."""
    path = Path(path)
    before = path.lstat()
    def identity(value):
        return (value.st_dev, value.st_ino, value.st_mode, value.st_size, value.st_mtime_ns,
                value.st_ctime_ns, getattr(value, 'st_flags', 0))
    def valid(value):
        return stat.S_ISREG(value.st_mode) and value.st_size <= limit and not getattr(value, 'st_flags', 0) & SF_DATALESS
    if not valid(before): raise ValueError('Invalid evidence file.')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as file:
        opened = os.fstat(file.fileno())
        if not valid(opened) or identity(opened) != identity(before): raise ValueError('Evidence changed before reading.')
        data = file.read(limit + 1)
        after = os.fstat(file.fileno())
        if identity(after) != identity(opened) or identity(path.lstat()) != identity(opened):
            raise ValueError('Evidence changed while reading.')
    if len(data) > limit or len(data) != opened.st_size: raise ValueError('Evidence is too large or incomplete.')
    if expected_sha256 is not None and hashlib.sha256(data).hexdigest() != expected_sha256:
        raise ValueError('Reviewed evidence bytes do not match their recorded hash.')
    return json.loads(data, object_pairs_hook=_unique_fields, parse_constant=_reject_constant)
