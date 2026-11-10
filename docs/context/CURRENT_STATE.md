# Current state

## Expanded core flows — 2026-11-10

The [expanded scope](../plans/SCOPE-EXPANSION-2026-11-10.md) is implemented and independently reviewed. The current local candidate is **1.0.0 build 8**, source 9be84dd, with a clean-source [manifest](../validation/candidate-1.0.0-build8-local.json) and successful [exact-archive qualification](../validation/expanded-build8-qualification.json). The normal installed application remains build 6 with its previous backup preserved; build 7 is superseded.

The explorer now separates manual Trash from conservative Move, including eligible home/application-cache content with review, protected paths and recovery. It offers an explicit internal APFS data-volume entry and refreshes stale results after operations. Caches can prepare future writes with an empty/absent local source. Yarn Classic and Go are exactly qualified and retain originals; ccache remains inactive. npm 10.9.2 is qualified with source-unavailable offline SSD reuse and npx preservation; validation preserves unindexed cache content.

The combined suite passed 244 cases discovered, 219 executed, 25 explicit skips and zero failures; 18 targeted cases checked the qualification binding. Native follow-up passed 48 of 49 cases with one ccache skip. The CocoaPods runtime profiles are recorded separately from inherited application availability. Build 8 samples PT/EN/minimum-window/Trash/future-cache/keyboard observations passed and the sample process was closed. Exact build 8 ZIP installation/helper/resources/removal passed in a generated temporary internal workspace. See [expanded evidence](../validation/EXPANDED-FLOWS-2026-11-10.md).

The macOS 15 directory-hint issue and a test journal-ID ordering issue were corrected and passed both CI runners at e761947. Final combined-head CI/integration remains the next step in the [live ledger](../TRACEABILITY.json). All observed sample/automated results remain distinct from maintainer approval, another Mac/macOS 14, physical faults, human VoiceOver/beta and signed distribution. publicV1Ready remains false.

## Previous build 6 engineering handoff

Updated 2026-11-10. PR12, [PR19](https://github.com/Gabriellimmaa/DiskWing/pull/19) and [PR20](https://github.com/Gabriellimmaa/DiskWing/pull/20) are merged. The engineering handoff is main 1947aec, whose [CI passed on macOS 15/26](https://github.com/Gabriellimmaa/DiskWing/actions/runs/42783336972). Candidate source remains 4db2600, identical to implementation merge f915039; PR20 changed only tests/documentation. Local 1.0.0 candidate build 6 is qualified and recorded in [the candidate handoff](../validation/LOCAL-CANDIDATE-2026-11-10.md). It has a local ad-hoc signature and remains ineligible for public v1 promotion. Apple Silicon/macOS 14+, Lift, MIT and PT/EN remain the approved scope.

The maintainer then requested installation and launch for interface validation. The exact build 6 archive was verified and installed in the user's Applications folder on internal storage, preserving the previous 0.2.0-dev build 3 application. Its normal application process and visible DiskWing window were observed after launch. Maintainer interface feedback is pending; installation/launch is not human acceptance. See [installation evidence](../validation/LOCAL-INSTALLATION-2026-11-10.md) and [the consolidated session record](SESSION-2026-11-10.md).

## Implemented

- One cross-process operation lease for cache migration/restore, personal actions, shell/Xcode configuration and recovery; durable operation/configuration checkpoints; preserved unreadable records.
- Streamed single-file copies with in-transfer cancellation and disk-backed tree verification preserving historical recovery digests. Disposable APFS cross-volume recovery/metadata, low-space/read-only refusal and ExFAT refusal have local evidence.
- Verified bytes, permissions, timestamps, extended attributes/resource forks and ACLs; source identity/stability checks, cancellation, staging, conflict/space protection and guided recovery without overwrite.
- SQLite index with paginated navigation, full-scope accent-insensitive search, size filters, logical/allocated ordering and streamed cancellable export.
- Metadata-only scan with progress, partial coverage, hard-link allocation accounting, no traversal into links/other mounts, no intentional cloud download. Limits: one million entries, depth 80, index budget 512 MiB and 256 MiB free-space floor.
- Up to two indexed trees per root and fifty comparable growth snapshots, with up to 10,000 folders per sample. Coverage limits are explicit. Private internal records are excluded from scans/events to avoid feedback.
- Optional FSEvents tracking, rescans at least fifteen minutes apart, Low Power Mode pause, optional growth alerts limited to one per root/day. No folders are watched by default.
- Seven versioned native cache adapters. Exact qualified versions are bundled; unknown/custom versions preserve the source. Bun/uv originals always remain local. Absolute Bun links within its own cache become relative in the copy.
- Portuguese/English selection, native keyboard navigation, review/recovery screens and optional notification permission requested only from the alert control.
- Portable packaged acceptance helper and disposable internal installation/removal runner, with private non-overwriting reports tied to the helper SHA-256. Human/other-Mac/release gates remain explicit and unverified. See [acceptance handoff](../acceptance/SECOND_MAC.md).
- Internal-disk installer preserving the previous application; portable ad-hoc build and optional pinned Sparkle 2 build. HTTPS/public-key/Developer-ID checks, nested signing and notarization tooling exist; actual public signing remains unverified.

The current validation records are [initial implementation evidence](../validation/IMPLEMENTATION-2026-11-10.md), [subsequent filesystem/copy qualification](../validation/FILESYSTEMS-2026-11-10.md) and [portable acceptance evidence](../validation/ACCEPTANCE-KIT-2026-11-10.md), linked to [requirements](../TRACEABILITY.json) and nine GitHub issues/milestones. Original import hashes in the migration manifest describe the historical import, not subsequent source revisions.

## Remaining release gates

Developer ID Application certificate and notarization credentials; hosted signed appcast and end-to-end valid/invalid update checks; second Mac install/restore/disable/removal; hands-on VoiceOver, both languages and keyboard acceptance; five general users plus five developers with immediate and seven-day observations. See [distribution](../DISTRIBUTION.md) and [beta protocol](../beta/PROTOCOL.md).

Events currently schedule full scoped rescans; subtree-only incremental reconciliation is future optimization. Resource limits can produce partial scans; retained-tree pruning now precedes insertion to avoid permanent exhaustion during repeated scans. The 20,001-file copy resource benchmark and disposable-image APFS/ExFAT checks are single-Mac evidence. A newly written 4 GiB same-volume copy/cancellation passed; more filesystems/devices and physical unplug/power-loss behavior still need qualification. Do not infer these results from synthetic fault injection.

No personal cache migration, terminal activation, Xcode preference change, login registration, notification activation, disk ejection, Chrome operation or public binary release is performed by implementing these features. No storage-saving claim is made.

## Autonomous delivery in progress

The maintainer approved autonomous implementation, independent review, merges and publication within the existing v1 scope. See docs/AUTONOMOUS-DELIVERY.md and the execution ledger in TRACEABILITY.json. Work is isolated by ownership/worktree; physical/human/signing dependencies remain pending. Static findings were converted to linked tasks. The repeated-index-budget defect was reproduced and fixed; operation recovery, cache configuration, GUI isolation and candidate evidence have been implemented and independently reviewed. All currently executable implementation/qualification tasks passed independent review and exact-head macOS 15/26 CI. Build 6 passed full-ZIP validation, temporary internal installation, packaged resource/helper checks and removal. PR20 additionally strengthened named checkpoint assertions and recorded a negative control; independent review and exact-head/main CI passed. QA task #18 is closed; original release requirements #2–#9 remain open. Production signing, physical-device and human acceptance remain pending.

## Next execution order

1. Inspect actual main/PR/CI state, then read docs/TRACEABILITY.json, docs/context/SESSION-2026-11-10.md and docs/validation/LOCAL-INSTALLATION-2026-11-10.md. Preserve the installed build 6, its previous-version backup and immutable ZIP; builds 4/5 are superseded.
2. Collect the maintainer's interface feedback on installed build 6. Record observed versus expected behavior and language/window context. No acceptance result has been supplied yet. Documentation-only follow-ups do not require reinstalling or rebuilding the unchanged candidate.
3. When Developer ID/notarization access and a protected update key are available, build one new final production artifact with a larger build number, then exercise valid/tampered signed updates, consent and operation blocking in a separate channel. Functional fixes must reopen their affected qualification.
4. Qualify that exact artifact on another physical Apple Silicon Mac and macOS 14, with actual PT/EN keyboard/VoiceOver and a separate disposable physical-fault device.
5. Record five general users plus five developers, >=80% independent success per cohort and seven real days. Review private candidate-bound records with the schema 2 readiness validator before public promotion. Specific participant outreach authorization remains required; none was performed here.

No worker has an unintegrated implementation. Independent worktrees can remain private for provenance; recreate specialists only after checking the current ledger. No background service continues after an active session ends.

## Beyond v1

Duplicate-content analysis with APFS clone/hard-link accounting, assisted app uninstall, dedicated library adapters, additional caches, Intel support according to demand and native Icon Composer polish remain outside v1.
