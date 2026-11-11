<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="design/brand/logo/svg/diskwing-horizontal-color-reverse.svg"><img src="design/brand/logo/svg/diskwing-horizontal-color.svg" width="340" alt="DiskWing"></picture></p>

# Understand your Mac's storage

DiskWing is an open source macOS utility for exploring disk usage and reviewing selective cache migrations to an external SSD. It grew from the local CacheSSD prototype. **This is an early local alpha, not a notarized public release.**

[![macOS checks](https://github.com/Gabriellimmaa/DiskWing/actions/workflows/ci.yml/badge.svg)](https://github.com/Gabriellimmaa/DiskWing/actions/workflows/ci.yml)

[Português](README.pt-BR.md) · [Current state](docs/context/CURRENT_STATE.md) · [Live roadmap](docs/ROADMAP.md) · [Recovery](docs/RECOVERY.md)

## What it does

- **Explore volumes:** select a mounted volume, navigate a virtual tree and synchronized space map, search the entire indexed volume and reveal eligible items in Finder.
- Keep logical size, estimated allocated blocks and observed free space distinct. Hidden files are included; inaccessible, interrupted and unverified areas remain explicit.
- **Caches on SSD:** choose an SSD, analyze applications, review one selection, transfer and activate, then check each application's result.
- Distinguish no transfer, configured destination, verified SSD use, temporary fallback and exceptions. Choosing an SSD or enabling shell integration alone never proves a transfer.
- Review eligible personal files, including unmanaged application caches, for the volume's macOS Trash. System roots, known sensitive data, installations, managed caches and recovery records stay protected. Trash is never emptied.
- Keep a private SQLite index with paged navigation and a durable resume queue. New indexes can use the chosen APFS SSD; internal indexes keep their storage budget.
- Use Portuguese or English. Existing optional folder monitoring remains opt-in.

Opening DiskWing never starts migration or cleanup. The catalog includes CLI tools and a graphical compatibility matrix for Chrome, Cursor, Xcode and Safari. **A catalog entry is not a compatibility guarantee.** Graphical transfer requires exact-version qualification, normal application cache-path behavior and fallback evidence. Unsupported applications stay local with a visible reason; see [current evidence](docs/context/CURRENT_STATE.md). No broad `Library/Caches` redirect is used. Profiles, history, cookies, passwords, SDKs, projects and installed environments are preserved.

System/Data appear together only when their APFS volume group is proven. Each item retains its physical filesystem identity; other mounts are separate scan targets. A partial scan is never called complete. The tree remains accessible without using the map.

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

Choose **Explore volumes**, select a volume and navigate its tree or space map. Opening a folder keeps that volume selected. The cache SSD is chosen separately in **Caches on SSD**.

For caches, follow **Choose SSD → Analyze caches → Review → Transfer and activate → Check results**. Quit the listed applications and save work before continuing; DiskWing never forces them to quit. Command-line routing requires a reviewed terminal update and a new terminal. A graphical provider uses only its own qualified cache directory. Configuration is not proof of SSD use, and a retained local copy is not counted as released space.

Without the SSD, qualified applications continue using their documented fallback, which may require network access. Chrome can use network and memory while its persistent SSD cache is absent. Reopening may be required after reconnecting. Temporary generations are preserved; arbitrary cache databases are not merged. Unexpected cable removal during an operation remains unqualified.

Use **Prepare to eject** and wait for macOS before disconnecting. Existing processes may still hold SSD files. Restoring or resuming a graphical cache requires its own reviewed action.

Trash is reviewed per item and rechecks the mounted volume and identity. Native Trash must be qualified for that filesystem; unsupported volumes are refused without a permanent-delete alternative. Space remains occupied until you empty Trash in Finder. Shared APFS blocks and snapshots prevent promising recoverable space from summed file sizes.

Analysis does not follow links or intentionally download cloud placeholders. The volume scanner has no fixed depth, entry-count or visible-row cutoff. Internal indexes keep a 512 MiB budget and 256 MiB reserve; optional external APFS indexes use a 1 GiB reserve. Limits and interruption preserve partial results and a durable queue; resume revalidates changed directories. Search and navigation are paged and exports stream indexed entries. Exported paths should be reviewed before sharing. There is no telemetry or automatic cleanup.

Install on the internal disk with python3 scripts/install_local.py dist/DiskWing.app to keep the application available without the SSD. Public signing, updater consent and removal are described in [distribution](docs/DISTRIBUTION.md). Human beta and seven-day evidence remain required before v1; see [release gates](docs/beta/PROTOCOL.md).

## Development and compatibility

Start with [AGENTS.md](AGENTS.md) and [project context](docs/context/PROJECT_CONTEXT.md). The approved Lift identity is in [design/brand](design/brand/README.md); older concepts are archived in [design/concepts](design/concepts/README.md).

Internal CacheSSD module names, bundle identifiers, on-disk formats, and integration markers remain stable to preserve existing alpha configurations. See [compatibility](docs/COMPATIBILITY.md).

Please read [contributing](CONTRIBUTING.md) and [security](SECURITY.md). Code and original project assets are MIT licensed; bundled Manrope font files retain their SIL Open Font License. See [third-party notices](THIRD_PARTY_NOTICES.md).

Copy/migration destinations must support extended security to preserve metadata. APFS is locally qualified; ExFAT is refused. A 256 MiB free-space floor and bounded verification workspace can stop an operation while preserving its source. See [filesystem qualification](docs/validation/FILESYSTEMS-2026-11-10.md).

For portable packaged checks and the private second-Mac review template, see [acceptance handoff](docs/acceptance/SECOND_MAC.md). Automated checks do not complete the human beta.
