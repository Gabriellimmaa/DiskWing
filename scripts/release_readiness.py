#!/usr/bin/env python3
"""Validate private human-beta evidence; never generate or publish participant data."""
import argparse
from datetime import datetime, timezone, timedelta
import json
from pathlib import Path


def timestamp(value):
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('Evidence dates require an explicit timezone.')
    return parsed.astimezone(timezone.utc)


def evaluate(data, now=None):
    now = now or datetime.now(timezone.utc)
    blockers = []
    participants = data.get('participants', [])
    ids = [p.get('id') for p in participants]
    if any(not isinstance(i, str) or not i for i in ids) or len(set(ids)) != len(ids):
        blockers.append('Participant pseudonyms must be unique and nonempty.')
    counts = {}
    for segment in ['general', 'developer']:
        cohort = [p for p in participants if p.get('segment') == segment]
        eligible = []
        for participant in cohort:
            try:
                observed = timestamp(participant['observedAt'])
                followup = timestamp(participant['followupAt'])
                mature = observed <= now and observed + timedelta(days=7) <= followup <= now
            except (ValueError, KeyError, AttributeError, TypeError):
                mature = False
            required = ['independentTaskSuccess', 'dataPreserved', 'worksWithoutSSD', 'sevenDayDiaryComplete']
            if mature and all(participant.get(key) is True for key in required) and participant.get('evidenceRef'):
                eligible.append(participant)
        counts[segment] = {'participants': len(cohort), 'qualifiedSuccesses': len(eligible)}
        if len(cohort) < 5 or len(eligible) < 0.8 * len(cohort):
            blockers.append(segment + ': five participants and four independent seven-day successes required.')
    gates = ['developerIDVerified', 'notarizationStapled', 'signedUpdaterVerified', 'secondMacRecoveryVerified',
             'voiceOverVerified', 'keyboardVerified', 'bothLanguagesVerified']
    for gate in gates:
        if data.get('distribution', {}).get(gate) is not True:
            blockers.append('Unverified gate: ' + gate)
    if data.get('criticalBlockers') != []:
        blockers.append('Critical blockers must be explicitly reviewed and empty.')
    return {'ready': not blockers, 'cohorts': counts, 'blockers': blockers}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path, help='Private JSON file; use .local/beta/ and pseudonyms.')
    args = parser.parse_args()
    result = evaluate(json.loads(args.evidence.read_text()))
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['ready'] else 1)
