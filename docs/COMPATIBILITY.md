# CacheSSD compatibility

DiskWing is the public project/application name. The alpha's internal names are intentionally preserved:

- SwiftPM targets/products: CacheSSDCore, CacheSSD, CacheSSDHelper; existing types/imports.
- App bundle ID: com.cachessd.app; helper signing identifier: com.cachessd.helper.
- Data in ~/Library/Application Support/CacheSSD, JSON schemas, installation IDs, journals, and SSD generations under MacCaches/CacheSSD.
- Managed .zshrc markers, generated integration functions, and backup names.
- CACHESSD_TEST_TEMP for fixtures. DISKWING_RUN_NATIVE_TESTS=1 enables installed-tool checks.

The generated bundle is dist/DiskWing.app. Its executable remains CacheSSD and helper CacheSSDHelper. Settings are read in place without migration. Consolidation does not replace the installed alpha, activate integrations, or alter user data.

Future renaming of persisted identifiers requires compatibility and rollback handling. Login items and shell helper paths need care when an installed bundle moves.

## Additive 0.2 development data

Legacy settings.json, history records, migration journals, installation IDs, volume-relative generations and shell markers remain compatible. New data is separate: versioned index.sqlite (schema 3), operation-UUID.json (schema 1), configuration-UUID.json (schema 1), and preferences.json (schema 1). Newer unsupported index/preferences/recovery versions are preserved rather than silently rewritten. Scanned identity is an optional additive field in ScanItem; full streamed exports declare schemaVersion 2.

Original import hashes are historical evidence, not hashes of the evolving checkout. Configuration before/after records may contain secrets and must remain private. Optional Sparkle preference keys are separate; they do not rename CacheSSD storage.

Directory verification retains the historical SHA-256 input: root metadata text followed by sorted-key JSON for path-sorted manifest entries. The new disposable verification database changes neither journal digests nor schemas. Unicode path ordering uses Swift comparison rather than SQLite binary collation. Destinations lacking extended-security support (including the qualified ExFAT image) are refused before copy publication or source release. APFS qualification is documented in validation/FILESYSTEMS-2026-11-10.md.

The acceptance-check helper command and its standalone schema-1 reports are additive diagnostics. They do not read/write the normal settings, change existing persisted identifiers, or declare release readiness. Generated acceptance stores are isolated and removed only after success.

## Autonomous delivery additions

Schema-2 indexes upgrade additively to schema 3 with typed coverage (complete, partial, unknown). Historical ambiguous trees become partial; unknown readings do not become zero. A retained-tree budget is reclaimed before a replacement scan. Streamed exports remain schema 2 with additive coverage. Legacy ScanItem JSON infers coverage conservatively; unknown coverage values remain unknown.

Operation/configuration journals remain schema 1. Restore journals add optional sourceVolumeUUID to bind recovery to the reviewed generation. Legacy restore journals without this proof are preserved and cannot automatically remove an existing configured route; review is required. Future completed records are retained and block updater promotion rather than being pruned. Historical tree digests are unchanged.

The development-only samples bundle uses com.cachessd.app.acceptance (helper com.cachessd.helper.acceptance) and never opens the normal preference domain. The normal bundle rejects sample launch arguments. No persisted production identifier changes.

Release review evidence uses a separate schema 2 and candidate manifests schema 1. Earlier private review files are preserved, rejected for promotion, and must be reviewed against the exact candidate rather than silently upgraded. These schemas do not change user settings.
