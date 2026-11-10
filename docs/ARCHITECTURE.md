# Architecture and data contracts

CacheSSDCore is shared by SwiftUI/AppKit and CacheSSDHelper. Names, bundle IDs and legacy JSON/shell markers stay compatible.

OperationSafety coordinates the legacy migration.lock lease, file identity, versioned durable journals and recovery. Migration/PersonalActions verify before publishing; personal originals go to Finder Trash, eligible cache originals are released only after validation, and unknown data never becomes disposable by size. Settings writes preserve existing locations and unreadable files. Configuration changes retain private before/after records; incomplete configuration records require review rather than blind automatic rollback.

Manual Trash has a distinct policy from generic Move: reviewed home descendants
including application caches can be eligible, while structural/sensitive paths,
private records and unsupported links/placeholders remain protected. Recovery
dispatches by operation kind and revalidates missing-source ancestors. New
future-cache setup uses a configuration journal and no-follow destination
creation, without creating/removing a local source. Terminal script capability
is versioned by an additive comment; older scripts require reviewed refresh.

DataVolumePaths recognizes the split APFS data-volume spelling only when device
and inode prove equivalence. Scanner classification/private-index exclusion and
home-file actions account for that spelling without broadening mount traversal
or trusting a prefix alone. Post-action analyses are refreshed or marked stale.

FileTree measures without hydration or link traversal. Copy verification covers bytes and copy-relevant metadata, including resource forks and ACLs. Hash reads reject links and dataless placeholders. File transfers use at most 1 MiB per data chunk, check cancellation during a single large file, reject replacement/growth, then copy metadata and synchronize the output. Directory metadata is applied deepest-first. Before writing, destinations must advertise extended-security support; unsupported filesystems such as ExFAT are refused rather than losing permissions. Bun's verified cache-internal absolute links are normalized to portable relative links. Native tool format exceptions remain explicit (Gradle locks; local wrapper/JDK/config references).

VerificationStore is a separate disposable SQLite manifest. Operation digests stream sorted entry JSON instead of retaining multiple full-tree arrays. Its Swift path collation and sorted-key JSON preserve the historical digest bytes, including Unicode paths, so existing recovery records remain usable. Defaults are one million entries, a 512 MiB database budget checked every 256 inserts/before reading, and a 256 MiB free-space floor. Workspace parents are resolved to physical paths before SQLite NOFOLLOW opens, including legitimate macOS /var to /private/var temporary-directory aliases. The private sibling workspace is normally on the destination volume (recovery uses the private store); failure leaves the source intact. It is removed on normal completion/error, but abrupt process death can leave a private .DiskWing-verification-* directory. This is rebuildable scratch, not a durable operation journal, and is never trusted for recovery.

ScanIndex uses system SQLite through CSQLite, one locked connection per worker, WAL, full synchronous commits, private permissions and versioned schema. It streams enumeration in autorelease batches, stores relative paths and source identity, and aggregates directory totals bottom-up. Queries paginate in SQL; searching spans the selected root rather than only visible children. Streaming export has a consistent read transaction and preserves an existing report on cancellation. Indexes, snapshots and exports remain local.

Logical size sums file entries; allocation deduplicates hard links within a scan. APFS clones/snapshots/purgeable data prevent equating either total with recoverable free space. Scope is one filesystem; other mounts and unreadable/limited areas are explicit. Files can change between scan and action, so indexed identity is rechecked before action and bytes/metadata are rechecked during it.

GrowthTracking compares complete snapshots with the same root/volume and available access. Missing or partial scans yield unavailable, never zero savings. At most fifty snapshots and 10,000 folder samples per snapshot are retained. FSEvents is advisory; drops/root changes invalidate a scope. Current reconciliation rescans a scope, with an opt-in queue/rate limit and Low Power Mode pause. No cleanup is automatic.

CacheAdapters separates native version/effective-cache discovery from routing and mutation. Existing explicit environment/project/user preferences win. Qualification data is a versioned resource tied to disposable workflow evidence. The seven legacy adapters can copy a different version while retaining the original, but cannot release it based on old evidence. The new Yarn/Go/ccache adapters require exact qualification before activation, migration or future-cache setup, and routing rechecks the static Yarn/Go runtime version. Yarn and Go originals remain local; ccache stays inactive without its own qualification. Go/Yarn discovery reads installation metadata rather than executing commands that might initialize personal caches or telemetry.

Localization separates literal template keys from interpolation arguments, so a file called Nome is never translated as a label. Historical application-authored messages are localized only at explicit display boundaries. Resource lookup works from SwiftPM tests, the helper and a portable app bundle without depending on this checkout.

Updates is compiled only under DISKWING_ENABLE_UPDATER=1, with exact Sparkle 2.10.1. Default local builds omit it. Production metadata requires HTTPS and an Ed25519 public key; checks are off by default, profiling/download/install automation disabled, installation consent remains in Sparkle UI and operation leases/recovery are checked. Distribution tooling does not establish end-to-end release readiness.

Read docs/COMPATIBILITY.md before changing persisted names. .local/ is private and never an API/input to public CI.

AcceptanceRunner is an explicit helper-only diagnostic using generated homes/stores, injected SSD availability and Trash, and no native installs or GUI actions. It records fixed check statuses and pending human gates, preserving failed fixtures and restoring its in-process language selection. Reports contain no user paths or raw errors and never overwrite files/links. scripts/qualify_bundle.py adds real temporary internal installation, clean-environment packaged helper execution, SHA-256 equality and reviewed fixture removal. Neither output changes release-readiness or user preferences.
