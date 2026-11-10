# Current state

Updated 2026-11-10. Development preview 0.2.0-dev on Apple Silicon, macOS 14+. Public v1, other-Mac validation and human beta remain gated.

## Implemented

- One cross-process operation lease for cache migration/restore, personal actions, shell/Xcode configuration and recovery; durable operation/configuration checkpoints; preserved unreadable records.
- Verified bytes, permissions, timestamps, extended attributes/resource forks and ACLs; source identity/stability checks, cancellation, staging, conflict/space protection and guided recovery without overwrite.
- SQLite index with paginated navigation, full-scope accent-insensitive search, size filters, logical/allocated ordering and streamed cancellable export.
- Metadata-only scan with progress, partial coverage, hard-link allocation accounting, no traversal into links/other mounts, no intentional cloud download. Limits: one million entries, depth 80, index budget 512 MiB and 256 MiB free-space floor.
- Up to two indexed trees per root and fifty comparable growth snapshots, with up to 10,000 folders per sample. Coverage limits are explicit. Private internal records are excluded from scans/events to avoid feedback.
- Optional FSEvents tracking, rescans at least fifteen minutes apart, Low Power Mode pause, optional growth alerts limited to one per root/day. No folders are watched by default.
- Seven versioned native cache adapters. Exact qualified versions are bundled; unknown/custom versions preserve the source. Bun/uv originals always remain local. Absolute Bun links within its own cache become relative in the copy.
- Portuguese/English selection, native keyboard navigation, review/recovery screens and optional notification permission requested only from the alert control.
- Internal-disk installer preserving the previous application; portable ad-hoc build and optional pinned Sparkle 2 build. HTTPS/public-key/Developer-ID checks, nested signing and notarization tooling exist; actual public signing remains unverified.

The current validation record is [implementation evidence](../validation/IMPLEMENTATION-2026-11-10.md), linked to [requirements](../TRACEABILITY.json) and nine GitHub issues/milestones. Original import hashes in the migration manifest describe the historical import, not subsequent source revisions.

## Remaining release gates

Developer ID Application certificate and notarization credentials; hosted signed appcast and end-to-end valid/invalid update checks; second Mac install/restore/disable/removal; hands-on VoiceOver, both languages and keyboard acceptance; five general users plus five developers with immediate and seven-day observations. See [distribution](../DISTRIBUTION.md) and [beta protocol](../beta/PROTOCOL.md).

Events currently schedule full scoped rescans; subtree-only incremental reconciliation is future optimization. Resource limits can produce partial scans, including when retained trees consume the index budget. Large personal-copy throughput, physical unplug/power-loss behavior and cross-filesystem metadata compatibility need further device testing. Do not infer these results from synthetic fault injection.

No personal cache migration, terminal activation, Xcode preference change, login registration, notification activation, disk ejection, Chrome operation or public binary release is performed by implementing these features. No storage-saving claim is made.

## Beyond v1

Duplicate-content analysis with APFS clone/hard-link accounting, assisted app uninstall, dedicated library adapters, additional caches, Intel support according to demand and native Icon Composer polish remain outside v1.
