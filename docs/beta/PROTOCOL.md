# Beta protocol and v1 release decision

A compiled feature is not a completed beta. Copy evidence-template.json to .local/beta/evidence.json. No participants have been enrolled by the implementation, and no success is assumed.

Recruit five general Mac users and five developers on Apple Silicon, macOS 14 or later. Obtain permission to record observations. Use pseudonyms; keep contact details, screenshots, file names, inventories and recordings outside Git. Participation and file operations remain voluntary.

General-user task: independently choose a folder, locate a large disposable item, understand logical/allocated/free sizes, review a safe move, find the copy and recover the original. Developer task: identify effective configuration, migrate one qualified disposable cache, install/build from it, return to local routing without the SSD, and restore/disable integration. Both groups inspect the explorer and cache screens. Use prepared sample files/projects before considering any personal data.

Record the initial task completion without coaching, mistakes and recovery, duration, comprehensibility, data preservation, version/macOS/architecture, permission state, connection/network state and measured free space. A task passes only if the participant independently completes their cohort task, preserves data and can use the Mac without the SSD.

At day seven or later, collect a seven-day diary: use/reconnection, regrowth, repeated downloads, unexpected dependency, notification frequency, recovery and any data loss. Compare the same folder/volume and readable scope. Record absence/unreadability separately from zero bytes. No automatic deletion or invented savings.

Each private participant record needs:
- id: unique pseudonym; segment: general or developer.
- observedAt and followupAt: actual timezone-qualified ISO dates; a qualifying success requires at least seven days. Preserve failed/withdrawn records and their real last observation without inventing a seven-day follow-up.
- independentTaskSuccess, dataPreserved, worksWithoutSSD, sevenDayDiaryComplete: explicit booleans.
- review: {evidenceRef, sha256}, pointing to a bounded private JSON human-review of that candidate and observation/diary.

Run python3 scripts/release_readiness.py .local/beta/evidence.json --manifest dist/CANDIDATE.manifest.json --evidence-root .local/beta. At least five participants and 80% qualifying successes per cohort are required (four when there are exactly five participants). Keep failures and withdrawals in the denominator; never silently remove them to improve the rate. Only successes with actual seven-day follow-up qualify. All critical blockers must be resolved. Public artifacts contain only reviewed aggregates and issue references.

The maintainer separately verifies Developer ID, stapled notarization, a signed update and rejection of an invalid signature, fresh install/restore/disable/removal on a second Mac, PT/EN, keyboard and VoiceOver. Evidence references and reviewer/date belong in the private review file. The script checks declarations and eligibility; it cannot authenticate an interview or replace manual review.

Keep a release candidate prerelease until these gates pass. Do not publish v1.0, tags, participants, or a Sparkle feed simply because this script exists.

Before enrollment, use the [portable acceptance handoff](../acceptance/SECOND_MAC.md) to prepare candidate/build hashes and the other-Mac/PT/EN/VoiceOver/lifecycle review. Automated reports and an empty manual template are not participant observations and must never be imported as beta successes.

## Candidate-bound private evidence (schema 2)

Copy the exact manifest candidate object (commit, version, buildNumber, archiveSHA256) to evidence.json. Preserve legacy files unchanged. The validator requires the production manifest and its matching ZIP alongside it; dev/local candidates are never ready.

Each distributionReviews gate points to {"evidenceRef":"reviews/your-review.json","sha256":"SHA256_OF_THAT_JSON"}. Use a relative path inside the private evidence directory, no links or traversal. The JSON record has schemaVersion: 1, kind: "human-review" or "tool-verification", candidate: the same object, reviewerAlias, reviewedAt: a timezone-qualified timestamp, and checks: {GATE: true}. Physical Mac, minimum macOS 14, VoiceOver, keyboard, languages and physical fault checks require human-review. Tool evidence cannot fulfill them.

Each participant.review points to a human-review JSON with the same candidate, participantID, observedAt, followupAt, reviewerAlias, reviewedAt and checks containing the four participant booleans. Dates must follow candidate creation; review follows the actual seven-day follow-up. The pointer hash and parsed JSON are checked from the same bounded immutable read. Malformed, duplicate-field, future-schema, stale or different-candidate evidence is rejected without rewriting it. These checks do not authenticate people: a responsible reviewer must verify the underlying observations.

No example record constitutes completed evidence. Keep all participant records, contact information and raw observations private. Signed distribution, a different physical Mac/macOS 14, accessibility and a disposable physical-fault device remain independent prerequisites. Publication permission is already granted within this plan; verify live repository access when promoting, without asking again for approval already given.
