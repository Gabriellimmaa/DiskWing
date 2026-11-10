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

Legacy settings.json, history records, migration journals, installation IDs, volume-relative generations and shell markers remain compatible. New data is separate: versioned index.sqlite (schema 2), operation-UUID.json (schema 1), configuration-UUID.json (schema 1), and preferences.json (schema 1). Newer unsupported index/preferences/recovery versions are preserved rather than silently rewritten. Scanned identity is an optional additive field in ScanItem; full streamed exports declare schemaVersion 2.

Original import hashes are historical evidence, not hashes of the evolving checkout. Configuration before/after records may contain secrets and must remain private. Optional Sparkle preference keys are separate; they do not rename CacheSSD storage.

Directory verification retains the historical SHA-256 input: root metadata text followed by sorted-key JSON for path-sorted manifest entries. The new disposable verification database changes neither journal digests nor schemas. Unicode path ordering uses Swift comparison rather than SQLite binary collation. Destinations lacking extended-security support (including the qualified ExFAT image) are refused before copy publication or source release. APFS qualification is documented in validation/FILESYSTEMS-2026-11-10.md.

The acceptance-check helper command and its standalone schema-1 reports are additive diagnostics. They do not read/write the normal settings, change existing persisted identifiers, or declare release readiness. Generated acceptance stores are isolated and removed only after success.
