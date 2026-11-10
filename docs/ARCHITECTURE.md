# Architecture and data contracts

CacheSSDCore is shared by SwiftUI/AppKit and CacheSSDHelper. Names, bundle IDs and legacy JSON/shell markers stay compatible.

OperationSafety coordinates the legacy migration.lock lease, file identity, versioned durable journals and recovery. Migration/PersonalActions verify before publishing; personal originals go to Finder Trash, eligible cache originals are released only after validation, and unknown data never becomes disposable by size. Settings writes preserve existing locations and unreadable files. Configuration changes retain private before/after records; incomplete configuration records require review rather than blind automatic rollback.

FileTree measures without hydration or link traversal. Copy verification covers bytes and copy-relevant metadata, including resource forks and ACLs. Hash reads reject links and dataless placeholders. Bun's verified cache-internal absolute links are normalized to portable relative links. Native tool format exceptions remain explicit (Gradle locks; local wrapper/JDK/config references).

ScanIndex uses system SQLite through CSQLite, one locked connection per worker, WAL, full synchronous commits, private permissions and versioned schema. It streams enumeration in autorelease batches, stores relative paths and source identity, and aggregates directory totals bottom-up. Queries paginate in SQL; searching spans the selected root rather than only visible children. Streaming export has a consistent read transaction and preserves an existing report on cancellation. Indexes, snapshots and exports remain local.

Logical size sums file entries; allocation deduplicates hard links within a scan. APFS clones/snapshots/purgeable data prevent equating either total with recoverable free space. Scope is one filesystem; other mounts and unreadable/limited areas are explicit. Files can change between scan and action, so indexed identity is rechecked before action and bytes/metadata are rechecked during it.

GrowthTracking compares complete snapshots with the same root/volume and available access. Missing or partial scans yield unavailable, never zero savings. At most fifty snapshots and 10,000 folder samples per snapshot are retained. FSEvents is advisory; drops/root changes invalidate a scope. Current reconciliation rescans a scope, with an opt-in queue/rate limit and Low Power Mode pause. No cleanup is automatic.

CacheAdapters separates native version/effective-cache discovery from routing and mutation. Existing explicit environment/project/user preferences win. Qualification data is a versioned resource tied to disposable workflow evidence; a different version can be copied with original retained but cannot release the original based on old evidence.

Localization separates literal template keys from interpolation arguments, so a file called Nome is never translated as a label. Historical application-authored messages are localized only at explicit display boundaries. Resource lookup works from SwiftPM tests, the helper and a portable app bundle without depending on this checkout.

Updates is compiled only under DISKWING_ENABLE_UPDATER=1, with exact Sparkle 2.10.1. Default local builds omit it. Production metadata requires HTTPS and an Ed25519 public key; checks are off by default, profiling/download/install automation disabled, installation consent remains in Sparkle UI and operation leases/recovery are checked. Distribution tooling does not establish end-to-end release readiness.

Read docs/COMPATIBILITY.md before changing persisted names. .local/ is private and never an API/input to public CI.
