# Current state

Updated 2026-11-09. Early local native macOS alpha, developed on Apple Silicon. Target: macOS 14. Verification on other Macs and OS versions is pending.

## Implemented

SwiftUI/AppKit app, menu extra, folder explorer, sorting/search, largest files, Finder, cancellable metadata scanner, reviewed personal-file actions, seven cache integrations, copy verification, native-tool checks, zsh routing, history, recovery journals, Xcode-default review, login-item option, and preparation for eject.

Analysis: 200,000 entries, 80 levels, 120 displayed children per folder, 60 largest files. History: 150 operations and 50 scan summaries. Partial scans and unreadable paths are identified. APFS shared blocks prevent guaranteed recoverable-space claims.

Consolidation did not execute personal migrations, shell activation, Xcode changes, startup activation, or physical ejection. Chrome data was not changed. No storage-saving claim is made.

## Next priorities

1. Test actual dependency installs/builds with disposable projects for every tool, with/without SSD and internet.
2. Exercise restore, disable/uninstall, interrupted recovery, and eject with disposable data.
3. Review accessibility and additional Macs/macOS versions.
4. Add incremental tracking and growth comparisons after correctness/resource validation.
5. Prepare Developer ID, notarization, signed updates, and beta with five general users and five developers.

Pending: automatic event-based updates, seven-day comparisons, growth notifications, duplicates, full app uninstall, library migrations, native Icon Composer .icon, notarized binaries, and market validation.

Development does not authorize operating on personal caches. Review and recovery remain required.
