import copy
import importlib.util
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('readiness', Path(__file__).resolve().parents[2] / 'scripts/release_readiness.py')
readiness = importlib.util.module_from_spec(spec); spec.loader.exec_module(readiness)


class ReleaseReadinessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('CACHESSD_TEST_TEMP'))
        self.root = Path(self.temp.name).resolve()
        self.now = datetime(2026, 11, 10, tzinfo=timezone.utc)
        self.archive = self.root / 'DiskWing-synthetic.zip'; self.archive.write_bytes(b'synthetic unit-test artifact only')
        self.candidate = {'commit': 'a' * 40, 'version': '1.0.0', 'buildNumber': '4', 'archiveSHA256': readiness.contracts.sha256(self.archive)}
        self.manifest = {'schemaVersion': 1, 'suite': 'diskwing-candidate-v1', 'candidate': self.candidate,
                         'profile': 'production', 'sourceDirty': False, 'acceptanceOnly': False, 'architecture': 'arm64',
                         'minimumMacOS': '14.0', 'builtAt': (self.now - timedelta(days=10)).isoformat(),
                         'archive': {'fileName': self.archive.name, 'bytes': self.archive.stat().st_size},
                         'verification': dict.fromkeys(['signatureVerified', 'developerID', 'notarizationAccepted', 'notarizationStapled', 'gatekeeperAccepted', 'updaterEnabled'], True)}
        self.data = {'schemaVersion': 2, 'candidate': self.candidate, 'participants': [],
                     'distribution': dict.fromkeys(readiness.contracts.GATES, True), 'distributionReviews': {}, 'criticalBlockers': []}
        for gate in readiness.contracts.GATES:
            self.data['distributionReviews'][gate] = self.record(gate, {gate: True})
        for segment in ['general', 'developer']:
            for n in range(5):
                participant = {'id': segment + str(n), 'segment': segment, 'observedAt': (self.now - timedelta(days=8)).isoformat(),
                               'followupAt': self.now.isoformat(), 'independentTaskSuccess': n < 4, 'dataPreserved': True,
                               'worksWithoutSSD': True, 'sevenDayDiaryComplete': True}
                participant['review'] = self.record(participant['id'], {key: participant[key] for key in readiness.contracts.PARTICIPANT_CHECKS}, participant=participant)
                self.data['participants'].append(participant)

    def tearDown(self): self.temp.cleanup()

    def record(self, name, checks, participant=None, kind='human-review'):
        record = {'schemaVersion': 1, 'kind': kind, 'candidate': self.candidate, 'reviewerAlias': 'synthetic-reviewer',
                  'reviewedAt': self.now.isoformat(), 'checks': checks}
        if participant:
            record.update({'participantID': participant['id'], 'observedAt': participant['observedAt'], 'followupAt': participant['followupAt']})
        path = self.root / (name + '.json'); path.write_text(json.dumps(record))
        return {'evidenceRef': path.name, 'sha256': readiness.contracts.sha256(path)}

    def evaluate(self, data=None, manifest=None):
        return readiness.evaluate(self.data if data is None else data, self.now, manifest=self.manifest if manifest is None else manifest,
                                  evidence_root=self.root, archive_path=self.archive)

    def test_missing_legacy_unknown_and_malformed_evidence_fail_without_rewriting(self):
        for value in [None, [], {}, {'schemaVersion': 1}, {'schemaVersion': True}, {'schemaVersion': 99}, {'schemaVersion': 2, 'participants': []}]:
            before = copy.deepcopy(value)
            self.assertFalse(readiness.evaluate(value, self.now, manifest=self.manifest, evidence_root=self.root, archive_path=self.archive)['ready'])
            self.assertEqual(value, before)
        data = copy.deepcopy(self.data); data['participants'] = [None, 'bad', {'id': 'ok', 'segment': []}]
        self.assertFalse(self.evaluate(data)['ready'])

    def test_candidate_bound_reviews_and_four_of_five_per_cohort_are_required(self):
        self.assertTrue(self.evaluate()['ready'])
        self.data['participants'][0]['dataPreserved'] = False
        self.assertFalse(self.evaluate()['ready'])

    def test_candidate_archive_or_evidence_mismatch_never_inherits_acceptance(self):
        data = copy.deepcopy(self.data); data['candidate'] = dict(self.candidate, buildNumber='5')
        self.assertFalse(self.evaluate(data)['ready'])
        path = self.root / self.data['participants'][0]['review']['evidenceRef']
        original = path.read_bytes(); path.write_text('changed observation')
        self.assertFalse(self.evaluate()['ready']); path.write_bytes(original)
        self.archive.write_bytes(b'changed candidate archive')
        self.assertFalse(self.evaluate()['ready'])

    def test_future_early_naive_and_duplicate_observations_cannot_count(self):
        for change in [{'followupAt': (self.now + timedelta(days=1)).isoformat()}, {'followupAt': self.data['participants'][0]['observedAt']},
                       {'observedAt': '2026-11-01'}, {'id': self.data['participants'][1]['id']}, {'dataPreserved': 'true'}]:
            data = copy.deepcopy(self.data); data['participants'][0].update(change)
            self.assertFalse(self.evaluate(data)['ready'])

    def test_unknown_schema_dirty_preview_or_unsigned_manifest_block_release(self):
        for change in [{'schemaVersion': 99}, {'sourceDirty': True}, {'acceptanceOnly': True}, {'profile': 'candidate'},
                       {'builtAt': (self.now + timedelta(days=1)).isoformat()}, {'candidate': dict(self.candidate, buildNumber='²')}]:
            manifest = copy.deepcopy(self.manifest); manifest.update(change)
            self.assertFalse(self.evaluate(manifest=manifest)['ready'])
        for gate in self.manifest['verification']:
            manifest = copy.deepcopy(self.manifest); manifest['verification'][gate] = False
            self.assertFalse(self.evaluate(manifest=manifest)['ready'])

    def test_critical_blockers_or_unreviewed_gate_block_release(self):
        self.data['criticalBlockers'] = ['synthetic unresolved blocker']
        self.assertFalse(self.evaluate()['ready']); self.data['criticalBlockers'] = []
        self.data['distribution']['notarizationStapled'] = False
        self.assertFalse(self.evaluate()['ready']); self.data['distribution']['notarizationStapled'] = True
        self.data['distributionReviews'].pop('notarizationStapled')
        self.assertFalse(self.evaluate()['ready'])

    def test_automatic_records_cannot_attest_human_gates(self):
        self.data['distributionReviews']['voiceOverVerified'] = self.record('automated', {'voiceOverVerified': True}, kind='tool-verification')
        self.assertFalse(self.evaluate()['ready'])
        self.data['distributionReviews']['voiceOverVerified'] = self.record('human', {'voiceOverVerified': True})
        self.data['participants'][0]['review'] = self.record('automated-participant', {key: True for key in readiness.contracts.PARTICIPANT_CHECKS}, participant=self.data['participants'][0], kind='tool-verification')
        self.assertFalse(self.evaluate()['ready'])

    def test_duplicate_or_nonfinite_json_does_not_silently_change_evidence(self):
        path = self.root / 'invalid.json'
        for text in ['{"schemaVersion":2,"schemaVersion":1}', '{"value":NaN}']:
            path.write_text(text)
            with self.assertRaises(ValueError): readiness.contracts.read_json_file(path)
            self.assertEqual(path.read_text(), text)

    def test_private_references_cannot_escape_follow_links_or_silently_disappear(self):
        gate = 'keyboardVerified'; original = self.data['distributionReviews'][gate]
        for ref in ['../outside.json', str(self.root / 'keyboardVerified.json'), 'missing.json']:
            self.data['distributionReviews'][gate] = dict(original, evidenceRef=ref)
            self.assertFalse(self.evaluate()['ready'])
        link = self.root / 'linked.json'; link.symlink_to(self.root / original['evidenceRef'])
        self.data['distributionReviews'][gate] = dict(original, evidenceRef=link.name)
        self.assertFalse(self.evaluate()['ready'])
