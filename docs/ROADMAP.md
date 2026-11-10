# DiskWing: alpha to v1

Approved scope: complete disk exploration **and** reviewed cache/SSD management in the first public version. Apple Silicon first, macOS 14+, Portuguese and English, local data, explicit review, preserved browser/project/SDK data. Historical plans remain in plans/.

The machine-readable source of requirement IDs, issues, acceptance criteria, validation state and external dependencies is [TRACEABILITY.json](TRACEABILITY.json). Implementation, isolated tests, native checks, cross-machine validation and beta are different states. Do not close a milestone solely because code exists.

| ID | Delivery | Completion evidence |
|---|---|---|
| [M0](https://github.com/Gabriellimmaa/DiskWing/issues/1) | Traceability | Every requirement maps to an issue, acceptance criteria, tests and evidence |
| [M1](https://github.com/Gabriellimmaa/DiskWing/issues/2) | Safe operations | Fail-closed reads, shared cross-process lease, durable checkpoints and recoverable injected failures |
| [M2](https://github.com/Gabriellimmaa/DiskWing/issues/3) | Complete scoped explorer | Paginated private SQLite index, global scoped search and bounded memory with explicit partial coverage |
| [M3](https://github.com/Gabriellimmaa/DiskWing/issues/4) | Personal actions | Copy/metadata verification, conflicts/space/cloud protection, recovery after interruptions |
| [M4](https://github.com/Gabriellimmaa/DiskWing/issues/5) | Qualified cache workflows | Actual temporary installs/builds and documented offline/SSD-absent scenarios for seven versioned integrations |
| [M5](https://github.com/Gabriellimmaa/DiskWing/issues/6) | Growth tracking | Opt-in advisory events, comparable snapshots, honest unavailable state and bounded retention |
| [M6](https://github.com/Gabriellimmaa/DiskWing/issues/7) | Public UX | PT/EN, keyboard/VoiceOver, clear permissions, review and recovery |
| [M7](https://github.com/Gabriellimmaa/DiskWing/issues/8) | Distribution | Internal installation, Developer ID/notarization, consented signed updates and removal |
| [M8](https://github.com/Gabriellimmaa/DiskWing/issues/9) | Beta and v1 | Five users per audience, four of five succeed per group, immediate/seven-day results, no critical blockers |

## Implementation status — 2026-11-10

M0–M5 have code and local validation evidence, including actual temporary native workflows and a one-million-entry explorer benchmark. M6 has PT/EN, native keyboard/accessibility-tree smoke and pending full VoiceOver acceptance. M7 has verified local installation/packaging and optional Sparkle compilation; Developer ID/notarization and end-to-end updates remain unverified. M8 has the protocol and readiness validator, with human recruitment and seven-day observation still pending.

See [implementation evidence](validation/IMPLEMENTATION-2026-11-10.md) and [all nine GitHub milestones](https://github.com/Gabriellimmaa/DiskWing/milestones). Public v1 readiness is false until the independent gates pass. Historical plans remain unchanged.

## Follow-on qualification and next priorities

PR #10 is merged at 6e95e499 and its [main CI passed](https://github.com/Gabriellimmaa/DiskWing/actions/runs/42755083061). The next M1/M3 increment replaces whole-tree in-memory verification with compatible streamed digests and makes a single-file copy cancellable. It adds a 20,001-file resource benchmark and actual disposable filesystem images: APFS metadata/recovery, low space, read-only and safe ExFAT refusal. See [qualification evidence](validation/FILESYSTEMS-2026-11-10.md). These are local development checks, not final milestone closure.

The next independent gates, in order of prerequisites, are:

1. Review/CI for this increment, then another Apple Silicon Mac's disposable filesystem and application install/restore/disable/removal matrix (M1/M3/M7).
2. Hands-on keyboard/VoiceOver and both-language acceptance across the two core flows, keeping user data untouched (M6).
3. Developer ID/notarization and a hosted signed-update acceptance/rejection exercise, including consent and recovery (M7). Credentials/hosting are external prerequisites; no public release is implicit.
4. Five general users plus five developers; immediate task results, at least 80 percent independent success per group and actual seven-day diaries (M8). Resolve all critical findings before v1 readiness.

Physical cable/power faults must use a separate disposable test device, never the development SSD. Additional filesystems and multi-gigabyte sequential copy throughput remain open qualification work.

## Baseline

The imported 0.1 alpha passed 26 native-enabled Swift tests and five packaging tests. Public CI runs 24 isolated Swift tests, explicitly skips two installed-tool checks, builds and verifies the app. These checks do not establish actual project installs, physical unplug safety or market validation.

Partial baseline capabilities: bounded explorer/search, personal actions with policy checks, seven cache integrations, per-command zsh routing, migration/restore and operation history. The first implementation work addresses unreadable terminal configuration, concurrent mutations, incomplete measurements and recovery.

## Architecture and invariants

GUI and helper share operation planning, execution and recovery. A versioned SQLite index stores paginated metadata locally. Adapters describe effective configuration, eligibility, tested versions and recovery. Existing CacheSSD identifiers, settings paths and integration markers stay compatible.

Source release follows verified copy, source stability and tool qualification. Bun/uv originals remain local. Chrome, credentials, SDKs, emulators and projects are protected. Personal sources go to Trash; the app never empties Trash.

Filesystem events are advisory; dropped events require a rescan. Root scope, permissions and unavailable volumes must be comparable before showing growth or reclaimed-space claims. Public export is always reviewed; no telemetry or automatic cleanup.

## Release gates

Exercise missing/renamed/read-only/full/disconnected SSD and full internal disk, file changes, protected content, links, cloud placeholders and application termination at operation boundaries. Test trees up to one million entries and keep progress/cancellation responsive. Prove restore/disable/removal on another Mac.

Production distribution requires Developer ID, hardened signing and Apple notarization; ad-hoc signatures do not satisfy this gate. Use Sparkle 2 for signed, consented updates, keeping local development usable without release credentials.

Beta requires five general users and five developers, at least four successful independent task completions in each group, and immediate/seven-day observation. Code cannot substitute for participant evidence.

## After v1

Qualify duplicate-content detection with clone/hard-link accounting; assisted app uninstall with ownership/shared-data protection; dedicated library/new-cache integrations; Intel according to demand and a tested matrix; native Icon Composer artwork as optional polish.

Dates are assigned only when capacity and prerequisites are known. Administrative Codex UI follow-up remains separate from runtime/release acceptance.
