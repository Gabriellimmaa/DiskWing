# DiskWing: alpha to v1

Approved scope: complete disk exploration **and** reviewed cache/SSD management in the first public version. Apple Silicon first, macOS 14+, Portuguese and English, local data, explicit review, preserved browser/project/SDK data. Historical plans remain in plans/.

The maintainer's [2026-11-10 expansion](plans/SCOPE-EXPANSION-2026-11-10.md) adds explicit manual Trash for eligible application caches and additional home content, separate from the stricter Move policy; internal data-volume discovery; future-write setup with an empty/absent cache; and additional per-tool cache adapters. These requirements are implemented in [PR #22](https://github.com/Gabriellimmaa/DiskWing/pull/22) and qualified in local build 8; the installed build 8 and its build 6/earlier backups remain preserved. See [expanded evidence](validation/EXPANDED-FLOWS-2026-11-10.md). Graphical applications require their own supported mechanisms and evidence rather than inheriting terminal coverage.

The machine-readable source of requirement IDs, issues, acceptance criteria, validation state and external dependencies is [TRACEABILITY.json](TRACEABILITY.json). Implementation, isolated tests, native checks, cross-machine validation and beta are different states. Do not close a milestone solely because code exists.

| ID | Delivery | Completion evidence |
|---|---|---|
| [M0](https://github.com/Gabriellimmaa/DiskWing/issues/1) | Traceability | Every requirement maps to an issue, acceptance criteria, tests and evidence |
| [M1](https://github.com/Gabriellimmaa/DiskWing/issues/2) | Safe operations | Fail-closed reads, shared cross-process lease, durable checkpoints and recoverable injected failures |
| [M2](https://github.com/Gabriellimmaa/DiskWing/issues/3) | Complete logical-volume explorer | Physical source identities, durable resume, private paged SQLite, tree/treemap, bounded memory and explicit partial coverage |
| [M3](https://github.com/Gabriellimmaa/DiskWing/issues/4) | Personal actions | Reviewed per-volume Trash and identity-bound recovery; separate Move policy; conflicts/space/cloud protection |
| [M4](https://github.com/Gabriellimmaa/DiskWing/issues/5) | Qualified cache workflows | Actual version/platform-bound CLI and graphical workflows, normal launch, existing-data reuse, future writes, absence/reconnection and source handling |
| [M5](https://github.com/Gabriellimmaa/DiskWing/issues/6) | Growth tracking | Opt-in advisory events, comparable snapshots, honest unavailable state and bounded retention |
| [M6](https://github.com/Gabriellimmaa/DiskWing/issues/7) | Public UX | PT/EN, keyboard/VoiceOver, clear permissions, review and recovery |
| [M7](https://github.com/Gabriellimmaa/DiskWing/issues/8) | Distribution | Internal installation, Developer ID/notarization, consented signed updates and removal |
| [M8](https://github.com/Gabriellimmaa/DiskWing/issues/9) | Beta and v1 | Five users per audience, four of five succeed per group, immediate/seven-day results, no critical blockers |

## History follow-up — 2026-11-11

The maintainer's History overflow report is fixed in [PR #25](https://github.com/Gabriellimmaa/DiskWing/pull/25). One scroll viewport keeps recovery cards and operations inside the window. Independent review, PT/EN minimum-size regression and native samples, full local checks, macOS 15/26 PR CI and exact build 12 package qualification passed. Build 12 is installed; build 11 and earlier backups are preserved. [Scoped evidence](validation/HISTORY-LAYOUT-2026-11-11.md) records the actual normal-app observation and unchanged state-file checks. This resolves the reported defect without closing human or public-v1 gates.

## Earlier cache/volume implementation status — 2026-11-10

The active increment is [PR #24](https://github.com/Gabriellimmaa/DiskWing/pull/24) under the [approved simpler cache/whole-volume plan](plans/CACHE-VOLUME-EXPERIENCE-2026-11-10.md). It adds two primary routes, application-oriented batch transfer, exact-version/platform Google Chrome qualification, explicit local exceptions, whole logical volumes, durable resume, virtual tree/treemap and volume-bound Trash. Native Chrome and disposable APFS/HFS+ Trash/refusal evidence are independently reviewed; the full >1M filesystem test, query replay and exact build 11 package have their own evidence; final PR/main bookkeeping retains its own gates. See [current state](context/CURRENT_STATE.md), [graphical matrix](validation/GRAPHICAL-CACHES-2026-11-10.md) and [review boundaries](validation/CACHE-VOLUME-REVIEW-2026-11-10.md).

The installed normal build 8 and build 6/build 3 backups remain unchanged. Build 9 is an intermediate uninstalled candidate; the final build 11 is separately archived and passed its own exact-package checks. No personal cache selection was executed. Earlier PR #22/build 8 evidence remains [historical validation](validation/EXPANDED-FLOWS-2026-11-10.md), and does not qualify this increment automatically.

### Previous build 6 engineering baseline

M0–M5 have code and local validation evidence, including actual temporary native workflows and a one-million-entry explorer benchmark. M6 has PT/EN, native keyboard/accessibility-tree smoke and pending full VoiceOver acceptance. M7 has verified local installation/packaging and optional Sparkle compilation; Developer ID/notarization and end-to-end updates remain unverified. M8 has the protocol and readiness validator, with human recruitment and seven-day observation still pending.

PR12/19/20 are merged; engineering handoff main 1947aec passed macOS 15/26 CI. Local candidate 1.0.0 build 6 was subsequently installed and opened on the maintainer's Mac at their explicit request, preserving the previous application. Maintainer interface feedback is pending. See [the consolidated cycle](context/SESSION-2026-11-10.md), [installation record](validation/LOCAL-INSTALLATION-2026-11-10.md), [initial implementation evidence](validation/IMPLEMENTATION-2026-11-10.md) and [all nine GitHub milestones](https://github.com/Gabriellimmaa/DiskWing/milestones). Public v1 readiness is false until the independent gates pass. Historical plans remain unchanged.

## Follow-on qualification and next priorities

PR #11 is merged at 1cdcaabf and its [main CI passed](https://github.com/Gabriellimmaa/DiskWing/actions/runs/42758794618). The merged M1/M3 increment replaces whole-tree in-memory verification with compatible streamed digests and makes a single-file copy cancellable. It adds a 20,001-file resource benchmark and actual disposable filesystem images: APFS metadata/recovery, low space, read-only and safe ExFAT refusal. See [qualification evidence](validation/FILESYSTEMS-2026-11-10.md). These are local development checks, not final milestone closure.

The follow-on portable acceptance kit adds self-contained bundled checks, a real temporary internal installation/removal runner and a private PT/EN/VoiceOver/lifecycle review template. It also resolves physical temporary-workspace paths before SQLite NOFOLLOW checks. Automated evidence does not close another-Mac or human acceptance gates.

The next independent gates, in order of prerequisites, are:

1. Collect maintainer feedback on installed build 12 after the scoped History fix. Preserve build 11/build 8/build 6/build 3 backups and the original performance evidence. Personal-cache operations require their own actual selection and review; developer observations are not human acceptance.
2. Developer ID/notarization and a hosted signed-update acceptance/rejection exercise, including consent, operation blocking and deferred restart (M7). Use a new production artifact with a build number greater than 12 and its own affected qualification; protected signing/update keys remain external prerequisites.
3. Another Apple Silicon Mac/macOS 14 disposable filesystem and application install/restore/disable/removal matrix (M1/M3/M7), plus hands-on keyboard/VoiceOver and both-language acceptance across the two core flows (M6). The packaged helper/lifecycle runner and [manual handoff](acceptance/SECOND_MAC.md) keep generated checks distinct from independent human evidence.
4. Five general users plus five developers; immediate task results, at least 80 percent independent success per group and actual seven-day diaries (M8). Resolve all critical findings before v1 readiness. Private participant outreach requires specific authorization.

Physical cable/power faults must use a separate disposable test device, never the development SSD. A fully written 4 GiB same-volume copy/cancellation was qualified locally; physical cross-device throughput, additional devices/filesystems and cable/power faults remain open qualification work.

## Baseline

The imported 0.1 alpha passed 26 native-enabled Swift tests and five packaging tests. At that baseline, public CI ran 24 isolated Swift tests, explicitly skipped two installed-tool checks, and built/verified the app. These checks do not establish actual project installs, physical unplug safety or market validation.

Partial baseline capabilities: bounded explorer/search, personal actions with policy checks, seven cache integrations, per-command zsh routing, migration/restore and operation history. The first implementation work addresses unreadable terminal configuration, concurrent mutations, incomplete measurements and recovery.

## Architecture and invariants

GUI and helper share operation planning, execution and recovery. A versioned SQLite index stores paginated metadata locally. Adapters describe effective configuration, eligibility, tested versions and recovery. Existing CacheSSD identifiers, settings paths and integration markers stay compatible.

Source release follows verified copy, source stability and tool qualification. Bun/uv/Yarn/Go originals remain local in the current supported increment. Chrome profiles, credentials, SDKs, emulators and projects are protected; only individually qualified cache scopes may transfer. Personal sources go to Trash; the app never empties Trash.

Filesystem events are advisory; dropped events require a rescan. Root scope, permissions and unavailable volumes must be comparable before showing growth or reclaimed-space claims. Public export is always reviewed; no telemetry or automatic cleanup.

## Release gates

Exercise missing/renamed/read-only/full/disconnected SSD and full internal disk, file changes, protected content, links, cloud placeholders and application termination at operation boundaries. Test the new volume engine above one million entries and keep progress/cancellation responsive. Prove restore/disable/removal on another Mac.

Production distribution requires Developer ID, hardened signing and Apple notarization; ad-hoc signatures do not satisfy this gate. Use Sparkle 2 for signed, consented updates, keeping local development usable without release credentials.

Beta requires five general users and five developers, at least four successful independent task completions in each group, and immediate/seven-day observation. Code cannot substitute for participant evidence.

## After v1

Qualify duplicate-content detection with clone/hard-link accounting; assisted app uninstall with ownership/shared-data protection; dedicated library/new-cache integrations; Intel according to demand and a tested matrix; native Icon Composer artwork as optional polish.

Dates are assigned only when capacity and prerequisites are known. Administrative Codex UI follow-up remains separate from runtime/release acceptance.
