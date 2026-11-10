# Current state

Updated 2026-11-10. [PR #12](https://github.com/Gabriellimmaa/DiskWing/pull/12) merged to main at fff0d6b; [main CI passed](https://github.com/Gabriellimmaa/DiskWing/actions/runs/42762937392). Development preview 0.2.0-dev on Apple Silicon, macOS 14+. Public v1, other-Mac validation and human beta remain gated.

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

The maintainer approved autonomous implementation, independent review, merges and publication within the existing v1 scope. See docs/AUTONOMOUS-DELIVERY.md and the execution ledger in TRACEABILITY.json. Work is isolated by ownership/worktree; physical/human/signing dependencies remain pending. Static findings were converted to linked tasks. The repeated-index-budget defect was reproduced and fixed; operation recovery, cache configuration, GUI isolation and candidate evidence have been implemented and independently reviewed. Integrated isolated/native/resource checks and native sample GUI journeys passed. Independent review covered each code increment; exact-head macOS15/26 CI and a clean local candidate are the next promotion steps. Production signing and human acceptance remain pending.

## Next execution order

1. Finish integrated autonomous validation, exact-head CI, merge and verify main; update docs/TRACEABILITY.json with candidate identity and the next action. Do not recreate already integrated worker branches.
2. Preserve the complete local 1.0.0 candidate without declaring it publicly ready. Acquire Developer ID/notarization and a protected update key, then build one final production artifact and exercise signed/tampered updates in a separate channel.
3. Qualify that exact artifact on another physical Apple Silicon Mac and the macOS 14 minimum, with actual PT/EN keyboard/VoiceOver and disposable-device recovery tests.
4. Record five general users plus five developers, >=80% independent success per cohort and seven real days. Verify private reviewed records against the manifest with the readiness validator before public promotion. No participant outreach is authorized implicitly.

## Beyond v1

Duplicate-content analysis with APFS clone/hard-link accounting, assisted app uninstall, dedicated library adapters, additional caches, Intel support according to demand and native Icon Composer polish remain outside v1.
