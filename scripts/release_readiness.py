#!/usr/bin/env python3
"""Fail-closed private acceptance review bound to the exact packaged candidate."""
import argparse
from datetime import datetime, timezone, timedelta
import importlib.util
import json
from pathlib import Path, PurePosixPath
import re

_spec = importlib.util.spec_from_file_location('diskwing_release_evidence', Path(__file__).with_name('release_evidence.py'))
contracts = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(contracts)
timestamp = contracts.timestamp


def _manifest_valid(manifest, now):
    if (not isinstance(manifest, dict) or type(manifest.get('schemaVersion')) is not int or manifest['schemaVersion'] != 1
            or manifest.get('suite') != 'diskwing-candidate-v1' or manifest.get('profile') != 'production'
            or manifest.get('sourceDirty') is not False or manifest.get('acceptanceOnly') is not False
            or not contracts.candidate_valid(manifest.get('candidate')) or manifest.get('architecture') != 'arm64'
            or manifest.get('minimumMacOS') != '14.0'):
        return False
    verification = manifest.get('verification')
    gates = ['signatureVerified', 'developerID', 'notarizationAccepted', 'notarizationStapled', 'gatekeeperAccepted', 'updaterEnabled']
    if not isinstance(verification, dict) or any(verification.get(key) is not True for key in gates): return False
    archive = manifest.get('archive')
    if not isinstance(archive, dict) or type(archive.get('bytes')) is not int or archive['bytes'] <= 0: return False
    name = archive.get('fileName')
    if not isinstance(name, str) or Path(name).name != name or '/' in name or '\\' in name or not name.endswith('.zip'): return False
    try: return timestamp(manifest['builtAt']) <= now
    except (KeyError, ValueError, TypeError, OverflowError): return False


def _review(pointer, root, candidate, built_at, now, *, human, expected_checks, participant=None):
    if not isinstance(pointer, dict) or set(pointer) != {'evidenceRef', 'sha256'}: return False
    ref, expected_hash = pointer.get('evidenceRef'), pointer.get('sha256')
    if (not isinstance(ref, str) or not ref or '\\' in ref or PurePosixPath(ref).is_absolute()
            or any(part in {'.', '..'} for part in ref.split('/'))
            or not isinstance(expected_hash, str) or re.fullmatch(r'[0-9a-f]{64}', expected_hash) is None): return False
    try:
        root = Path(root).resolve(strict=True); path = root.joinpath(*PurePosixPath(ref).parts)
        resolved = path.resolve(strict=True)
        if root not in resolved.parents or resolved != path.absolute() or path.is_symlink() or path.stat().st_size > 8_388_608: return False
        if contracts.sha256(path) != expected_hash: return False
        record = contracts.read_json_file(path)
        if (not isinstance(record, dict) or type(record.get('schemaVersion')) is not int or record['schemaVersion'] != 1
                or record.get('kind') not in ({'human-review'} if human else {'human-review', 'tool-verification'})
                or record.get('candidate') != candidate): return False
        reviewer = record.get('reviewerAlias')
        if not isinstance(reviewer, str) or not reviewer.strip() or len(reviewer) > 80: return False
        if not built_at <= timestamp(record['reviewedAt']) <= now: return False
        checks = record.get('checks')
        if not isinstance(checks, dict) or any(type(checks.get(key)) is not bool or checks[key] != value for key, value in expected_checks.items()): return False
        if participant is not None:
            if record.get('participantID') != participant['id']: return False
            for key in ['observedAt', 'followupAt']:
                if timestamp(record[key]) != timestamp(participant[key]): return False
            if timestamp(record['reviewedAt']) < timestamp(participant['followupAt']): return False
        return True
    except (KeyError, ValueError, TypeError, OSError, OverflowError): return False


def evaluate(data, now=None, *, manifest=None, evidence_root=None, archive_path=None):
    now = now or datetime.now(timezone.utc)
    blockers = []
    counts = {key: {'participants': 0, 'qualifiedSuccesses': 0} for key in ['general', 'developer']}
    def result(): return {'ready': not blockers, 'cohorts': counts, 'blockers': blockers}
    if not isinstance(data, dict) or type(data.get('schemaVersion')) is not int or data['schemaVersion'] != 2:
        blockers.append('Unsupported evidence schema; preserve legacy/unknown records and review a schema-2 candidate file.')
        return result()
    if not _manifest_valid(manifest, now):
        blockers.append('A clean production candidate with verified signing/notarization and a supported manifest is required.')
        return result()
    candidate, built_at = manifest['candidate'], timestamp(manifest['builtAt'])
    if data.get('candidate') != candidate: blockers.append('Evidence belongs to a different candidate.')
    if evidence_root is None: blockers.append('Private evidence directory is required.')
    if archive_path is None:
        blockers.append('The exact packaged archive is required.')
    else:
        try:
            archive = Path(archive_path)
            if (archive.is_symlink() or not archive.is_file() or archive.name != manifest['archive']['fileName']
                    or archive.stat().st_size != manifest['archive']['bytes'] or contracts.sha256(archive) != candidate['archiveSHA256']):
                blockers.append('Packaged archive identity does not match the candidate manifest.')
        except (OSError, ValueError, TypeError): blockers.append('Packaged archive is unavailable.')
    participants = data.get('participants')
    if not isinstance(participants, list) or len(participants) > 1000:
        blockers.append('Participants must be a bounded list of reviewed private records.')
        return result()
    seen = set()
    for participant in participants:
        if not isinstance(participant, dict):
            blockers.append('Malformed participant record.'); continue
        identifier, segment = participant.get('id'), participant.get('segment')
        if not isinstance(identifier, str) or not identifier.strip() or len(identifier) > 80 or identifier in seen:
            blockers.append('Participant pseudonyms must be unique and nonempty.'); continue
        seen.add(identifier)
        if not isinstance(segment, str) or segment not in counts:
            blockers.append('Unknown participant cohort.'); continue
        counts[segment]['participants'] += 1
        try:
            observed, followup = timestamp(participant['observedAt']), timestamp(participant['followupAt'])
            dates_valid = built_at <= observed <= followup <= now
        except (KeyError, ValueError, TypeError, OverflowError): dates_valid = False
        booleans_valid = all(type(participant.get(key)) is bool for key in contracts.PARTICIPANT_CHECKS)
        checked = {key: participant.get(key) for key in contracts.PARTICIPANT_CHECKS}
        reviewed = dates_valid and booleans_valid and _review(participant.get('review'), evidence_root, candidate, built_at, now,
                                                             human=True, expected_checks=checked, participant=participant)
        if not reviewed:
            blockers.append('A participant observation is malformed, stale or lacks matching human review.'); continue
        if observed + timedelta(days=7) <= followup and all(checked.values()): counts[segment]['qualifiedSuccesses'] += 1
    for segment, values in counts.items():
        if values['participants'] < 5 or values['qualifiedSuccesses'] < 0.8 * values['participants']:
            blockers.append(segment + ': five reviewed participants and at least 80 percent independent seven-day successes required.')
    distribution, reviews = data.get('distribution'), data.get('distributionReviews')
    for gate in contracts.GATES:
        if (not isinstance(distribution, dict) or distribution.get(gate) is not True or not isinstance(reviews, dict)
                or not _review(reviews.get(gate), evidence_root, candidate, built_at, now, human=gate in contracts.HUMAN_GATES, expected_checks={gate: True})):
            blockers.append('Unverified candidate-bound gate: ' + gate)
    if data.get('criticalBlockers') != []: blockers.append('Critical blockers must be explicitly reviewed and empty.')
    return result()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path, help='Private schema-2 beta/review JSON; never rewritten.')
    parser.add_argument('--manifest', type=Path, help='Candidate manifest alongside the exact ZIP.')
    parser.add_argument('--evidence-root', type=Path, help='Private directory containing reviewed evidence references.')
    args = parser.parse_args()
    try:
        data = contracts.read_json_file(args.evidence)
        manifest = contracts.read_json_file(args.manifest) if args.manifest else None
        archive = args.manifest.parent / manifest['archive']['fileName'] if isinstance(manifest, dict) and isinstance(manifest.get('archive'), dict) and isinstance(manifest['archive'].get('fileName'), str) else None
        answer = evaluate(data, manifest=manifest, evidence_root=args.evidence_root or args.evidence.parent, archive_path=archive)
    except (OSError, ValueError, KeyError, TypeError, OverflowError):
        answer = {'ready': False, 'cohorts': {}, 'blockers': ['Evidence/manifest could not be safely read; original files were preserved.']}
    print(json.dumps(answer, indent=2))
    raise SystemExit(0 if answer['ready'] else 1)
