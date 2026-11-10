<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="design/brand/logo/svg/diskwing-horizontal-color-reverse.svg"><img src="design/brand/logo/svg/diskwing-horizontal-color.svg" width="340" alt="DiskWing"></picture></p>

# Understand your Mac's storage

DiskWing is an open source macOS utility for exploring disk usage and reviewing selective cache migrations to an external SSD. It grew from the local CacheSSD prototype. **This is an early local alpha, not a notarized public release.**

[![macOS checks](https://github.com/Gabriellimmaa/DiskWing/actions/workflows/ci.yml/badge.svg)](https://github.com/Gabriellimmaa/DiskWing/actions/workflows/ci.yml)

[Português](README.pt-BR.md) · [Current state](docs/context/CURRENT_STATE.md) · [Roadmap](docs/plans/ROADMAP-V0.1.md) · [Recovery](docs/RECOVERY.md)

## What it does

- Explore folders by size, search results, inspect the largest files, and reveal items in Finder.
- Distinguish logical size from allocated blocks, with progress, cancellation, and partial-result indicators.
- Review migrations for npm, Bun, CocoaPods, pip, Homebrew, Gradle, and uv; verify copies before releasing supported local caches.
- Route new zsh commands to the available cache location. Without the selected SSD, new commands fall back to local defaults.
- Review personal-file actions, operation history, and recovery locations.

Opening DiskWing never starts a cache migration. Chrome profiles, history, cookies, passwords, and browser caches are outside the migration catalog. SDKs, emulator data, projects, and local npx executables stay in place. Bun and uv source caches are retained because installed environments may depend on links to them.

## Build

Requires macOS 14+, Xcode 16+ (Swift 6 and the macOS SDK), and Python 3. The app has no external Swift package dependencies. The interface is currently in Portuguese.

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

Two native-tool integration tests are skipped by default. To run all checks on a prepared development Mac:

~~~sh
DISKWING_RUN_NATIVE_TESTS=1 swift test -j 2
~~~

The native checks require npm, Bun, CocoaPods, Python with pip, uv, Homebrew, and an already installed Gradle wrapper distribution. They use isolated cache samples; they do not install dependencies into personal projects. CACHESSD_TEST_TEMP can select a temporary directory. See [testing](docs/TESTING.md).

## Use and limitations

Choose a folder in **Explorar espaço**, or inspect recognized caches in **Caches e SSD**. Review each operation. Shell routing requires the separate **Revisar integração** action and a new terminal session. Dock-launched applications retain their own settings.

Use **Preparar para ejetar** before disconnecting. Existing processes retain their environment; physical disconnection can interrupt them. Local fallback may need internet to download missing dependencies.

Personal-file movement verifies a copy and sends the source to Trash. Space is not recovered until you review and empty Trash in Finder. DiskWing never empties Trash. APFS shared blocks and snapshots mean file-size totals are not a promise of recoverable space.

Analysis is local, does not follow links, and does not intentionally download cloud placeholders. It is limited to 200,000 entries and 80 levels; displayed children and largest-file lists are bounded. Reports contain paths: inspect them before sharing. There is no telemetry or automatic background cleanup.

## Development and compatibility

Start with [AGENTS.md](AGENTS.md) and [project context](docs/context/PROJECT_CONTEXT.md). The approved Lift identity is in [design/brand](design/brand/README.md); older concepts are archived in [design/concepts](design/concepts/README.md).

Internal CacheSSD module names, bundle identifiers, on-disk formats, and integration markers remain stable to preserve existing alpha configurations. See [compatibility](docs/COMPATIBILITY.md).

Please read [contributing](CONTRIBUTING.md) and [security](SECURITY.md). Code and original project assets are MIT licensed; bundled Manrope font files retain their SIL Open Font License. See [third-party notices](THIRD_PARTY_NOTICES.md).
