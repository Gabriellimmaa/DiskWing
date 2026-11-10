# Recovery and local data

Settings, history, backups, and migration journals remain in ~/Library/Application Support/CacheSSD. Reports contain paths: review them before sharing.

**Usar somente o Mac** stops external selection for new commands. Existing processes keep their environment. **Desativar integração** removes the managed terminal block, preserving other edits. Open a new terminal afterward. The previous .zshrc backup stays in application support; corrected local temporary-directory settings are intentionally preserved.

**Restaurar cópia ao Mac** requires the SSD, enough space, and an empty local destination. Existing cache data is not overwritten. If already populated, select local mode; tools can recreate caches.

migration-*.json records interrupted steps and quarantine paths. Preserve originals and logs after failure. .partial-* directories are incomplete or not activated; do not substitute them for originals. Verified SSD generations are not automatically deleted.

Personal-file moves verify the destination and put the source in Trash. Restore through Finder. DiskWing never empties Trash. Review copies before manually freeing source space.

Disable shell integration and login startup before removing an installed app. Consolidation leaves the installed alpha and settings unchanged.
