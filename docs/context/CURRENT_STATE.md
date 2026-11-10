# Current state

Updated 2026-11-10. The expanded cache/explorer scope is integrated through
[PR #22](https://github.com/Gabriellimmaa/DiskWing/pull/22), merge e3ab12e. Its exact
PR head passed macOS 15/26 tests, packaging/lifecycle checks and both optional
updater builds. [Post-merge main CI](https://github.com/Gabriellimmaa/DiskWing/actions/runs/42876868358) also passed; TRACEABILITY.json records the handoff.
Apple Silicon, macOS 14+, Lift, MIT and PT/EN remain the approved scope.

## Current candidate and installed application

Local **1.0.0 build 8**, source `9be84dd`, has a clean-source
[manifest](../validation/candidate-1.0.0-build8-local.json) and successful
[exact-archive qualification](../validation/expanded-build8-qualification.json).
Its runtime source files match the implementation merged into main. Build 7 is
superseded; previous artifacts remain preserved. The normal installed app is
still build 6 and its earlier backup remains intact. No personal-file migration or deletion,
real shell/Xcode/login activation or physical disk fault was
performed by this delivery.

The [expanded contract](../plans/SCOPE-EXPANSION-2026-11-10.md),
[live roadmap](../ROADMAP.md), [ledger](../TRACEABILITY.json) and
[qualification record](../validation/EXPANDED-FLOWS-2026-11-10.md) describe the
current increment. Earlier engineering/installation history remains in
[the session record](SESSION-2026-11-10.md) and
[build 6 installation evidence](../validation/LOCAL-INSTALLATION-2026-11-10.md).

## Implemented

- Reviewed manual Trash for eligible home descendants, including application
  caches/data, with independent eligibility from generic Move. Structural roots,
  known credentials/profiles, protected installations and private records remain
  protected. Links/placeholders/special files are refused; Trash is never emptied.
- Explicit internal APFS data-volume exploration, paginated SQLite navigation,
  global scoped search, size filters and streamed export. Identity-proven Data
  aliases preserve scope/mount boundaries and exclude private index records.
  Post-action analysis/inventory refresh prevents stale results being current.
- Future-cache setup with an empty/absent local source, durable configuration
  checkpoints and no-follow destination/settings checks. Opening the app does
  not migrate or clean data; integration updates require review and a new terminal.
- Seven legacy cache adapters plus exactly qualified Yarn Classic/Go build
  caching. npm 10.9.2 has source-unavailable offline SSD reuse and npx-preservation
  evidence; validation preserves unindexed cache content. Bun/uv/Yarn/Go origins
  remain local; ccache is inactive until native qualification. Explicit native,
  project, environment and command preferences prevail; Dock applications need
  their own supported mechanism.
- Shared cross-process operation lease, streamed verified copies, source
  stability checks, metadata/ACL/resource-fork preservation, conflict/space
  guards and guided recovery. Existing CacheSSD identifiers, formats and paths
  remain compatible; missing Trash-source directory hints now work on macOS 15.
- Metadata scans avoid link/other-mount traversal and intentional cloud downloads.
  Limits remain one million entries, depth 80, 512 MiB index and 256 MiB free-space
  floor; coverage is complete/partial/unknown. Logical/allocated/free space are
  distinct. Two indexed trees per root and fifty comparable snapshots are bounded.
- Optional growth monitoring/alerts, fifteen-minute rescan spacing and Low Power
  Mode pause. Nothing is watched by default; no telemetry or automatic cleanup.
- PT/EN and sample UI/keyboard journeys, portable generated acceptance checks,
  temporary internal installer/removal qualification and optional pinned updater
  compilation. Actual public signing/update acceptance remains separate.

## Verification and limits

The combined isolated suite passed 244 cases discovered, 219 executed, 25 explicit
skips and zero failures. The npm qualification binding passed 18 targeted cases
(one explicit native skip); all 51 packaging tests passed. Native follow-up
passed 48 of 49 cases with only ccache skipped: 35 core/configuration, nine legacy/
regression and four expanded native workflows. CocoaPods profiles are explicit;
adapter inspection in the inherited test environment does not establish a
universal application default. Runtime/gem installations were not changed.

Generated APFS and temporary-directory alias regressions passed; 23 Trash tests
were independently repeated after the directory-hint/journal-ID follow-ups.
Build 8 samples native UI was observed in PT/EN at minimum 1050 × 690: reviewed Trash,
cancel/confirm/rescan, missing-cache preparation, fixture integration, blocked
unqualified operations and basic keyboard worked without functional clipping.
The sample process was closed and fixtures/private observations retained.
These are developer observations, not maintainer/human VoiceOver/beta approval.

Build 8's exact ZIP passed identity, extraction, temporary internal installation,
signature/helper/resources and removal. It is locally ad-hoc signed, not
notarized or a public release. No storage-saving claim is made. Native cache
fixtures used the same filesystem and simulated availability; real physical
unplug/cross-device throughput is not established. Resource benchmarks and
filesystem-image evidence retain their own source/artifact limits. A Data entry
that disappears before identity proof can still stop a scan explicitly.

## Next actions and external gates

1. Preserve build 8's exact archive and the installed build 6/backup. Inspect
   actual main/CI state when resuming and collect the maintainer's feedback;
   its installation and personal-cache operations require their actual reviewed
   selections and are not implied by sample tests.
2. With actual Developer ID/notarization/update credentials, create a new
   production artifact with a larger build number and qualify signed valid/
   tampered updates, consent, operation blocking and deferred restart.
3. Qualify that artifact on another physical Apple Silicon Mac/macOS 14 and a
   separate disposable physical-fault device; perform hands-on PT/EN keyboard/
   VoiceOver acceptance across both flows.
4. With specific outreach authorization, record five general users plus five
   developers, at least 80% independent success per group and seven real days.
   Participant evidence is never simulated by agents.

publicV1Ready remains false. No unintegrated implementation is pending and no
background agent service is assumed after the active session. Further ccache,
pnpm stores/metadata, graphical-app adapters, duplicate detection, assisted
uninstall and Intel support need their own bounded scope and qualification.
