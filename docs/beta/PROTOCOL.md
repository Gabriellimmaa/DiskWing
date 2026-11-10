# Beta protocol and v1 release decision

A compiled feature is not a completed beta. Copy evidence-template.json to .local/beta/evidence.json. No participants have been enrolled by the implementation, and no success is assumed.

Recruit five general Mac users and five developers on Apple Silicon, macOS 14 or later. Obtain permission to record observations. Use pseudonyms; keep contact details, screenshots, file names, inventories and recordings outside Git. Participation and file operations remain voluntary.

General-user task: independently choose a folder, locate a large disposable item, understand logical/allocated/free sizes, review a safe move, find the copy and recover the original. Developer task: identify effective configuration, migrate one qualified disposable cache, install/build from it, return to local routing without the SSD, and restore/disable integration. Both groups inspect the explorer and cache screens. Use prepared sample files/projects before considering any personal data.

Record the initial task completion without coaching, mistakes and recovery, duration, comprehensibility, data preservation, version/macOS/architecture, permission state, connection/network state and measured free space. A task passes only if the participant independently completes their cohort task, preserves data and can use the Mac without the SSD.

At day seven or later, collect a seven-day diary: use/reconnection, regrowth, repeated downloads, unexpected dependency, notification frequency, recovery and any data loss. Compare the same folder/volume and readable scope. Record absence/unreadability separately from zero bytes. No automatic deletion or invented savings.

Each private participant record needs:
- id: unique pseudonym; segment: general or developer.
- observedAt and followupAt: timezone-qualified ISO dates at least seven days apart.
- independentTaskSuccess, dataPreserved, worksWithoutSSD, sevenDayDiaryComplete: explicit booleans.
- evidenceRef: private relative reference to reviewed observation/diary evidence.

Run python3 scripts/release_readiness.py .local/beta/evidence.json. At least five participants and four qualifying successes per cohort are required. All critical blockers must be resolved. Public artifacts contain only reviewed aggregates and issue references.

The maintainer separately verifies Developer ID, stapled notarization, a signed update and rejection of an invalid signature, fresh install/restore/disable/removal on a second Mac, PT/EN, keyboard and VoiceOver. Evidence references and reviewer/date belong in the private review file. The script checks declarations and eligibility; it cannot authenticate an interview or replace manual review.

Keep a release candidate prerelease until these gates pass. Do not publish v1.0, tags, participants, or a Sparkle feed simply because this script exists.
