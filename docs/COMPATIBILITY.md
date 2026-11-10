# CacheSSD compatibility

DiskWing is the public project/application name. The alpha's internal names are intentionally preserved:

- SwiftPM targets/products: CacheSSDCore, CacheSSD, CacheSSDHelper; existing types/imports.
- App bundle ID: com.cachessd.app; helper signing identifier: com.cachessd.helper.
- Data in ~/Library/Application Support/CacheSSD, JSON schemas, installation IDs, journals, and SSD generations under MacCaches/CacheSSD.
- Managed .zshrc markers, generated integration functions, and backup names.
- CACHESSD_TEST_TEMP for fixtures. DISKWING_RUN_NATIVE_TESTS=1 enables installed-tool checks.

The generated bundle is dist/DiskWing.app. Its executable remains CacheSSD and helper CacheSSDHelper. Settings are read in place without migration. Consolidation does not replace the installed alpha, activate integrations, or alter user data.

Future renaming of persisted identifiers requires compatibility and rollback handling. Login items and shell helper paths need care when an installed bundle moves.
