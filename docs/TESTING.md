# Testing

Run swift test -j 2 and python3 -m unittest discover -s Tests/Packaging -v. Isolated Swift tests use synthetic homes, stores, and injected volumes. CACHESSD_TEST_TEMP can select a fixture location.

The original implementation had 26 tests. Two invoke installed tools and are skipped unless DISKWING_RUN_NATIVE_TESTS=1 is set. A prepared Mac needs npm, Bun, CocoaPods, Python with pip, uv, Homebrew, and an existing Gradle wrapper distribution. Requested native checks fail when a command is absent; Gradle reports a skip if no local distribution exists.

Native checks query or validate isolated cache copies. They do not prove complete dependency installation, project builds, offline behavior, or physical hot-unplug safety. Do not download distributions or modify personal projects just to satisfy a check.

CI runs isolated Swift tests, Python packaging tests, a production build, and signature/icon verification. It does not use signing credentials, register login items, modify shell files, or publish releases.

## Acceptance areas

- Scanner: hard links, external links, limits, partial reads, cancellation, and totals despite bounded display.
- Operations: hashes, source stability, interrupted/missing/full/wrong volumes, busy files, protected data, recovery.
- Routing: local fallback, mounts, overrides, project preferences, corrupt settings, repeated sourcing, variable changes, dotfile permissions/links.
- Compatibility: Gradle distributions and lock exclusions, local npx executables, Bun/uv origins, technical identifiers.
- Packaging: portable defaults/CLI, refusal to overwrite foreign apps or links, production signature, approved icon bytes.

See docs/context/MIGRATION-2026-11-09.md for results. Raw machine-specific logs remain in ignored .local/ storage.
