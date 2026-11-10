# Recovery and local data

Settings, history, backups, and migration journals remain in ~/Library/Application Support/CacheSSD. Reports contain paths: review them before sharing.

**Usar somente o Mac** stops external selection for new commands. Existing processes keep their environment. **Desativar integração** removes the managed terminal block, preserving other edits. Open a new terminal afterward. The previous .zshrc backup stays in application support; corrected local temporary-directory settings are intentionally preserved.

**Restaurar cópia ao Mac** requires the SSD, enough space, and an empty local destination. Existing cache data is not overwritten. If already populated, select local mode; tools can recreate caches.

migration-*.json records interrupted steps and quarantine paths. Preserve originals and logs after failure. .partial-* directories are incomplete or not activated; do not substitute them for originals. Verified SSD generations are not automatically deleted.

Personal-file moves verify the destination and put the source in Trash. Restore through Finder. DiskWing never empties Trash. Review copies before manually freeing source space.

Disable shell integration and login startup before removing an installed app. Consolidation leaves the installed alpha and settings unchanged.

## Durable recovery in the development preview

History lists pending operation-UUID.json records, including cancelled/interrupted copies. Review Restore original only when the source is absent and a verified copy is connected. Existing sources are never overwritten. Review Close record and keep copies after inspecting originals/staging/destinations; that action removes no data. A changed copy is preserved for manual review. Completed personal moves remain recoverable through Finder Trash and their verified destinations.

Unreadable or newer records are preserved. configuration-UUID.json contains private before/after shell/Xcode settings; a prepared record requires review after interruption. Do not paste it into public issues or blindly replace a shell that has since changed. The original zshrc-before-cachessd.txt and Xcode backup remain available.

The private SQLite index can be rebuilt by another scan; do not remove recovery journals or settings as an index repair. Stop tracking before moving a monitored root. Unavailable volumes and denied access never imply freed space. See DISTRIBUTION.md for reviewed removal.
