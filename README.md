<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="design/brand/logo/svg/diskwing-horizontal-color-reverse.svg"><img src="design/brand/logo/svg/diskwing-horizontal-color.svg" width="340" alt="DiskWing"></picture></p>

# Understand your Mac's storage

DiskWing is an open source macOS utility for exploring disk usage and reviewing selective cache migrations to an external SSD. It grew from the local CacheSSD prototype. **This is an early local alpha, not a notarized public release.**

[![macOS checks](https://github.com/Gabriellimmaa/DiskWing/actions/workflows/ci.yml/badge.svg)](https://github.com/Gabriellimmaa/DiskWing/actions/workflows/ci.yml)

[Português](README.pt-BR.md) · [Current state](docs/context/CURRENT_STATE.md) · [Live roadmap](docs/ROADMAP.md) · [Recovery](docs/RECOVERY.md)

## What it does

- Explore a paginated private SQLite index, search the entire selected scope, filter/order sizes, inspect the largest files, and reveal items in Finder.
- Distinguish logical size from allocated blocks, with progress, cancellation, and partial-result indicators.
- Review migrations for npm, Bun, CocoaPods, pip, Homebrew, Gradle, and uv; verify copies before releasing supported local caches.
- Route new zsh commands to the available cache location. Without the selected SSD, new commands fall back to local defaults.
- Review personal-file actions, operation history, and recovery locations.
- Opt into folder-change tracking, comparable growth snapshots and rate-limited notifications. Select Portuguese or English.

Opening DiskWing never starts a cache migration. Chrome profiles, history, cookies, passwords, and browser caches are outside the migration catalog. SDKs, emulator data, projects, and local npx executables stay in place. Bun and uv source caches are retained because installed environments may depend on links to them.

## Build

Requires macOS 14+, Xcode 16+ (Swift 6 and the macOS SDK), and Python 3. Bundles target Apple Silicon. Default builds use system SQLite and no external Swift package; the separately enabled production updater pins Sparkle 2.10.1. The interface supports Portuguese and English.

~~~sh
git clone https://github.com/Gabriellimmaa/DiskWing.git
cd DiskWing
python3 build.py
open dist/DiskWing.app
~~~

The script builds directly from the checkout and ad-hoc signs the app. It does not install it, enable login items, or change shell settings. Optional flags retain the original CLI:

~~~sh
python3 build.py --configuration release --scratch /path/to/build --output /path/to/DiskWing.app
~~~

The default scratch directory is .build/ and the output is dist/DiskWing.app. No specific SSD name is required. Ad-hoc signing does not provide Developer ID notarization.

## Test

~~~sh
swift test -j 2
python3 -m unittest discover -s Tests/Packaging -v
~~~

Installed-tool checks and resource benchmarks are skipped by default. On a prepared development Mac:

~~~sh
DISKWING_RUN_NATIVE_TESTS=1 swift test -j 2
DISKWING_RUN_INSTALL_TESTS=1 swift test -j 2 --filter NativeWorkflowTests
~~~

The native checks require npm, Bun, CocoaPods, Python with pip, uv, Homebrew, Java and an already installed Gradle wrapper distribution. Actual installs/builds use disposable projects, pinned public packages and disabled install hooks. CACHESSD_TEST_TEMP selects a temporary directory. Offline availability varies by tool and artifact. See [testing](docs/TESTING.md).

## Use and limitations

Choose a folder in **Explorar espaço**, or inspect recognized caches in **Caches e SSD**. Review each operation. Shell routing requires the separate **Revisar integração** action and a new terminal session. Dock-launched applications retain their own settings.

Use **Preparar para ejetar** before disconnecting. Existing processes retain their environment; physical disconnection can interrupt them. Local fallback may need internet to download missing dependencies.

Personal-file movement verifies a copy and sends the source to Trash. Space is not recovered until you review and empty Trash in Finder. DiskWing never empties Trash. APFS shared blocks and snapshots mean file-size totals are not a promise of recoverable space.

Analysis is local, does not follow links, and does not intentionally download cloud placeholders. Limits are one million entries, depth 80 and a 512 MiB index budget, with explicit partial coverage. Navigation/search are paginated; exports stream all indexed entries. Reports contain paths: inspect them before sharing. There is no telemetry or automatic cleanup. Optional events currently trigger full scoped rescans at least fifteen minutes apart; missing/partial scopes never imply saved space.

Install on the internal disk with python3 scripts/install_local.py dist/DiskWing.app to keep the application available without the SSD. Public signing, updater consent and removal are described in [distribution](docs/DISTRIBUTION.md). Human beta and seven-day evidence remain required before v1; see [release gates](docs/beta/PROTOCOL.md).

## Development and compatibility

Start with [AGENTS.md](AGENTS.md) and [project context](docs/context/PROJECT_CONTEXT.md). The approved Lift identity is in [design/brand](design/brand/README.md); older concepts are archived in [design/concepts](design/concepts/README.md).

Internal CacheSSD module names, bundle identifiers, on-disk formats, and integration markers remain stable to preserve existing alpha configurations. See [compatibility](docs/COMPATIBILITY.md).

Please read [contributing](CONTRIBUTING.md) and [security](SECURITY.md). Code and original project assets are MIT licensed; bundled Manrope font files retain their SIL Open Font License. See [third-party notices](THIRD_PARTY_NOTICES.md).

Copy/migration destinations must support extended security to preserve metadata. APFS is locally qualified; ExFAT is refused. A 256 MiB free-space floor and bounded verification workspace can stop an operation while preserving its source. See [filesystem qualification](docs/validation/FILESYSTEMS-2026-11-10.md).
