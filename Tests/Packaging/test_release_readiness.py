import importlib.util
from datetime import datetime, timedelta, timezone
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('readiness', Path(__file__).resolve().parents[2] / 'scripts/release_readiness.py')
readiness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(readiness)


class ReleaseReadinessTests(unittest.TestCase):
    def fixture(self):
        now = datetime(2026, 11, 10, tzinfo=timezone.utc)
        participants = []
        for segment in ['general', 'developer']:
            for n in range(5):
                participants.append({'id': segment + str(n), 'segment': segment, 'observedAt': (now-timedelta(days=8)).isoformat(),
                                     'followupAt': now.isoformat(), 'independentTaskSuccess': n < 4, 'dataPreserved': True,
                                     'worksWithoutSSD': True, 'sevenDayDiaryComplete': True, 'evidenceRef': 'synthetic-test-only'})
        gates = dict.fromkeys(['developerIDVerified','notarizationStapled','signedUpdaterVerified','secondMacRecoveryVerified',
                              'voiceOverVerified','keyboardVerified','bothLanguagesVerified'], True)
        return {'participants':participants,'distribution':gates,'criticalBlockers':[]}, now

    def test_missing_evidence_never_passes(self):
        self.assertFalse(readiness.evaluate({})['ready'])

    def test_all_gates_and_four_of_five_per_cohort_are_required(self):
        data, now = self.fixture()
        self.assertTrue(readiness.evaluate(data, now)['ready'])
        data['participants'][0]['dataPreserved'] = False
        self.assertFalse(readiness.evaluate(data, now)['ready'])

    def test_future_or_early_followup_and_duplicate_people_do_not_count(self):
        data, now = self.fixture()
        data['participants'][0]['followupAt'] = (now+timedelta(days=1)).isoformat()
        self.assertFalse(readiness.evaluate(data, now)['ready'])
        data, now = self.fixture()
        data['participants'][0]['followupAt'] = data['participants'][0]['observedAt']
        self.assertFalse(readiness.evaluate(data, now)['ready'])
        data, now = self.fixture()
        data['participants'][0]['id'] = data['participants'][1]['id']
        self.assertFalse(readiness.evaluate(data, now)['ready'])

    def test_critical_blockers_and_unsigned_distribution_prevent_release(self):
        data, now = self.fixture()
        data['criticalBlockers'] = ['unresolved data-loss report']
        self.assertFalse(readiness.evaluate(data, now)['ready'])
        data['criticalBlockers'] = []
        data['distribution']['notarizationStapled'] = False
        self.assertFalse(readiness.evaluate(data, now)['ready'])
