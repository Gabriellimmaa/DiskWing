# DiskWing contributor and agent entry point

Read docs/context/PROJECT_CONTEXT.md, docs/context/CURRENT_STATE.md, docs/COMPATIBILITY.md, and docs/TESTING.md before changing behavior. docs/plans/ preserves the approved cache plan and product roadmap. Follow the approved Lift identity in design/brand/; do not redesign it during routine fixes.

## Architecture and commands

Native macOS SwiftPM project. Sources/CacheSSDCore contains analysis, routing, persistence, and operations; Sources/CacheSSDApp contains SwiftUI/AppKit screens; Sources/CacheSSDHelper is the CLI. Technical names intentionally remain CacheSSD for compatibility.

- Build: python3 build.py (default .build/, dist/DiskWing.app).
- Isolated tests: swift test -j 2.
- Packaging tests: python3 -m unittest discover -s Tests/Packaging -v.
- Installed-tool checks: DISKWING_RUN_NATIVE_TESTS=1 swift test -j 2. See docs/TESTING.md for prerequisites.
- Optional fixtures location: CACHESSD_TEST_TEMP=/path/to/test-temp.

## Data preservation

Opening the app must not migrate or clean anything. Operations require a review of the actual selection. Never run migration, shell integration, login-item registration, Xcode changes, unmount, or personal-file actions against the developer's data merely to test code. Use isolated samples and injected volumes/stores.

Preserve Chrome data, SDKs, emulators, projects, and local npx executables. Keep Bun/uv origins until their installed-environment link semantics have a separately approved, tested migration. Verify copies and source stability before releasing recognized caches. Unknown data is not disposable. Logical size, allocated blocks, and observed free-space changes are different measurements.

Do not change persisted paths, JSON formats, shell markers, or bundle IDs as a mechanical rename. No broad symbolic links for system cache directories. Existing processes keep their environment; do not claim physical unplug safety. Do not hydrate cloud files just to scan them.

## Documentation, publication, and privacy

Talk to the maintainer in Portuguese. Public overview/contribution docs are in English with README.pt-BR.md available; historical approved plans remain in Portuguese. Record behavior changes and validation limits honestly.

.local/ is private, ignored migration material. Never stage it or publish raw conversations, local inventories, UUIDs, personal paths, certificates, or credentials. Keep builds/dependencies out of Git. Public context documents are the durable project memory; original chats remain outside Git.

Do not add telemetry, automatic cleanup, a public release, signing credentials, or updater infrastructure without an explicitly approved scope. Do not overwrite unrelated local work. A successful local build is not notarization or verification on another Mac.
