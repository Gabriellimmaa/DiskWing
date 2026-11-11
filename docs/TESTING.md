# Testing

~~~sh
swift test -j 2
python3 -m unittest discover -s Tests/Packaging -v
python3 build.py
~~~

Use CACHESSD_TEST_TEMP=/path/on/a/disposable/development/volume to keep fixtures off a nearly full internal disk. Tests use isolated homes, stores, projects and injected volume providers. Never substitute personal caches, shell settings, projects, browser profiles or SDKs.

The default suite includes safety, abrupt subprocess exit/recovery, metadata/resource forks, indexed pagination/global search/export/retention, comparable growth and a real FSEvents callback, plus translation/resource checks. Default skips are explicit: two installed-tool query checks, seven actual native workflows, one million-entry explorer benchmark, four disposable filesystem-image cases, one copy resource benchmark, one written-4-GiB qualification and the subprocess-only crash worker. The parent crash test runs the worker itself and verifies recovery.

## Separate opt-in native checks

The expanded flows add isolated `ManualTrashTests`, `ExpandedCacheTests` and
`ExpandedFlowsTests`: application-cache Trash/recovery, distinct Move policy,
empty/absent-cache routing setup, custom configuration, stale-result refresh
and APFS alias refusal. The optional
`ExpandedFlowsTests/testNativeDataAliasWithGeneratedSharedFixtureAndPrivateIndexExclusion`
uses `DISKWING_RUN_NATIVE_TESTS=1` and creates/removes only a tiny uniquely named
generated directory under `/Users/Shared`. It checks a real data-volume firmlink,
personal-file classification and private-index exclusion without reading any
personal content. Run this and expanded native cache workflows serially under
the coordinator's native resource slot. It is single-Mac metadata evidence,
not a full-disk personal scan or another-Mac acceptance.

`DISKWING_RUN_EXPANDED_NATIVE_TESTS=1` enables `ExpandedNativeWorkflowTests`
for Yarn Classic, Go and ccache in generated homes/projects. Use a prepared
PATH with the intended runtime; `DISKWING_EXPANDED_NATIVE_REPORT_DIR` writes
sanitized, non-overwriting reports. A missing runtime is an explicit skip,
never qualification. Yarn/Go workflow reports are linked from the expanded
scope evidence. Their originals remain local; ccache cannot activate without
its own exact-version evidence. Hooks are disabled for generated package installs.

~~~sh
DISKWING_RUN_NATIVE_TESTS=1 swift test -j 2
DISKWING_RUN_INSTALL_TESTS=1 swift test -j 2 --filter NativeWorkflowTests
~~~

A prepared Mac needs npm, Bun, CocoaPods, Python/pip, uv, Homebrew, Java and an already installed Gradle wrapper distribution. Requested missing tools fail. The original Gradle query test may skip if no local distribution exists.

Actual workflows download small pinned public artifacts into disposable projects with a clean environment and disabled install hooks: npm/Bun is-number, pip/uv urllib3, CocoaPods Result, Gradle commons-lang3. Homebrew fetches hello into a temporary cache without installing a global formula. Existing local Gradle executables are used read-only; distribution download is not a prerequisite fulfilled by modifying personal data.

Native --offline proves the tool's offline mode for the tested artifact. It is not a disconnected network or cable test. pip --no-index correctly misses without a wheelhouse. Homebrew/CocoaPods tests establish cache reuse, not offline availability. The matrix in validation/ records exact versions, original retention and local fallback execution. Configuration/version changes require requalification before source release.

## Explicit CocoaPods runtime profiles

Native workflows may use `DISKWING_NATIVE_COCOAPODS_RUBY` and
`DISKWING_NATIVE_COCOAPODS_LIBEXEC` together to select an already installed
compatible Ruby executable and CocoaPods libexec directory. The test creates a
launcher only inside its generated fixture; it does not install gems, replace
symlinks or alter the application's production default. Reports identify the
profile and distinguish it from adapter inspection in the test process's
inherited environment.

`DISKWING_NATIVE_COCOAPODS_UNAVAILABLE_LAUNCHER` can explicitly select an existing
incompatible launcher for the refusal case. Without an unavailable launcher,
that case skips rather than inventing a failure. A clean fixture's failure is
not evidence that the user's application environment is unavailable. Keep
runtime/profile evidence separate and never repair the user's tools merely to
make a test pass.

## Resource benchmark and updater compilation

~~~sh
DISKWING_RUN_SCALE_TESTS=1 \
CACHESSD_TEST_TEMP=/your/development/fixture-directory \
DISKWING_SCALE_REPORT=/your/private/scale-report.json \
swift test -j 2 --filter ScaleTests

DISKWING_ENABLE_UPDATER=1 swift build --scratch-path .build-updater -j 2
~~~

The scale test creates 999,000 real empty files in 999 directories (one million entries including the root), checks complete scope/global search/last-page access, memory and index bytes, then removes only its own fixture. Allow several minutes and enough external free space. Do not run two SwiftPM operations against the same scratch directory at once. The optional updater build verifies APIs/linking; no feed, keys, installation or signing is activated.

## Separate disposable filesystem and copy qualification

~~~sh
DISKWING_RUN_FILESYSTEM_TESTS=1 \
CACHESSD_TEST_TEMP=/your/development/fixture-directory \
swift test -j 2 --filter FilesystemQualificationTests

DISKWING_RUN_COPY_SCALE_TESTS=1 \
CACHESSD_TEST_TEMP=/your/development/fixture-directory \
swift test -j 2 --filter CopyScaleTests
~~~

Create the fixture directory first on a filesystem supporting extended security, with at least 2 GiB free. The four filesystem tests create blank APFS sparse images and a 128 MiB ExFAT image with hdiutil; they mount under the system /Volumes location and detach only the exact device returned for their own image. They never format, fill, detach or force-unmount an existing disk. A failed detach retains its fixture for recovery. Failures to create/mount an image are test failures, not evidence that the application safely refused it.

Cases cover real cross-volume APFS copy/recovery with bytes, ACLs, resource forks, modes and nanosecond mtime; read-only APFS; actual low space on the disposable APFS image; and early ExFAT refusal. The copy benchmark creates 20,001 files (one 64 MiB sparse fixture) and 201 directories, verifies both trees, tests memory below 256 MiB and removes its own fixture. This is not a multi-gigabyte sequential-throughput or physical cable test. Reports are opt-in via DISKWING_FILESYSTEM_REPORT_DIR and DISKWING_COPY_SCALE_REPORT; keep machine-specific logs private and review reports before publication.

After a process crash, inspect the durable operation record first. A leftover .DiskWing-verification-* folder is disposable scratch, never a recovery source. Remove only a confirmed owned scratch folder after the operation has stopped; do not remove operation/configuration journals or staging copies to free space blindly.

## Portable packaged acceptance

See [another-Mac handoff](acceptance/SECOND_MAC.md) for the packaged helper command, temporary internal installation/removal runner and private manual-review template. The helper runs generated explorer/copy/recovery/cache/shell fixtures without Swift or Python. The lifecycle runner needs Python 3 and internal fixture storage. Normal user settings, installed apps and personal files are never used. Reports retain pending human/release gates and do not make the beta ready. A regression test exercises real system temporary-directory aliases in addition to the configured fixture volume.

## Public CI

CI runs isolated Swift tests, Python packaging/readiness tests, an arm64 ad-hoc development bundle, signature/icon/resource checks and a real disposable internal installation/helper/removal exercise. The separate updater job compiles the exact Sparkle dependency. The explorer scale job requires a manual dispatch with run_scale enabled. A separate filesystems job requires run_filesystems and runs the disposable image/copy tests; default CI never mounts images. Native workflows require explicit local opt-in and suitable tool availability. Default CI never installs personal tooling or publishes releases.

Developer ID, Apple notarization, runtime updater consent/signature rejection, VoiceOver, other Macs, real cable removal and the human beta remain independent acceptance gates. See [current evidence](validation/IMPLEMENTATION-2026-11-10.md). Raw machine-specific logs stay in ignored .local/ storage.

## Written large-file qualification

~~~sh
DISKWING_RUN_LARGE_COPY_TESTS=1 \
CACHESSD_TEST_TEMP=/your/development/fixture-directory \
DISKWING_LARGE_COPY_REPORT=/your/private/new-report.json \
swift test -j 2 --filter LargeFileQualificationTests
~~~

Requires more than 12 GiB free. Writes and synchronizes 4 GiB, checks actual allocation (no sparse fixture), cancels a transfer, then copies/verifies both trees with bounded memory. This is generated same-volume data, not physical unplug or proof of cross-device throughput. Run heavy suites serially. The one-million-entry and filesystem/copy benchmarks are separate.

## Isolated GUI acceptance

~~~sh
python3 build.py --acceptance-bundle
mkdir -p .local/gui-fixtures
open -n dist/DiskWingAcceptance.app --args --acceptance-workspace "$PWD/.local/gui-fixtures"
~~~

If macOS has not permitted the separate samples domain to access a removable volume, use a small private temporary internal fixture directory instead. Do not grant broader permissions merely to run acceptance. Confirm the visible sample banner before acting. This creates a private .DiskWing-samples-UUID session containing home, support, simulated SSD and generated files. Reopen using --acceptance-session with that exact directory. Invalid/incomplete launch state shows an error and retry screen, with no access to the real home. Preparation runs in a worker after application launch so filesystem access cannot block the first window. The samples app refuses ordinary launch, and the normal app refuses these flags. Its independent bundle ID protects normal AppKit saved state. Never run samples through the normal app bundle.

Selections and outputs are restricted to the generated session; redirected storage fails closed. Login, notification, Xcode, Finder/open and eject are substitutes. The SSD switch renames only its generated directory, preserves bytes and exercises absence without touching a mounted disk. Native tools and Sparkle are disabled. Process-use checks are controlled in generated GUI/helper fixtures; production constructors keep the real inspector. Checkpoint tests use explicit injection and prove the intended boundary, while the real-open-file test qualifies the default separately. The sample-only window menu selects the minimum 1050 × 690 content size or the default size; it changes no normal-window preferences. AppAcceptanceTests cover journeys, scope isolation, fresh consent, reconnect and energy resumption; native GUI checks supplement these tests and never attest human VoiceOver usability.

CI runs on macos-15 and macos-26. The macOS 14 minimum requires external validation. Manual heavy jobs run serially (scale, filesystems, written copy), preserve sanitized JSON reports and upload no application binaries or raw logs. Optional updater compilation is distinct from signed-update acceptance.


## New cache/volume experience

The current [approved increment](plans/CACHE-VOLUME-EXPERIENCE-2026-11-10.md) has
independent acceptance. `VolumeScanTests` cover APFS grouping/alias proofs, hidden
and deep paths, queued resume, changed directories/files, hard links, future
formats, guarded retention/reset/aggregation and explicit partial coverage.
`VolumeTrashTests` cover mounted identity, relative recovery after rename,
conflicts and no permanent-delete fallback. The default app suite also exercises
one reviewed cache batch, unknown graphical records before any CLI configuration,
volume selection independent of cache SSD, stale/unloaded row action safety,
nested tree/map selection, and original index storage on resume.

The new volume scanner's heavy test is separate from the historical scanner:

~~~sh
DISKWING_RUN_VOLUME_SCALE_TESTS=1 CACHESSD_TEST_TEMP=/existing/ssd/fixtures \
  DISKWING_VOLUME_SCALE_REPORT=/private/report.json \
  swift test -j 2 --filter VolumeScanScaleTests
~~~

It requires at least 8 GiB free, creates over one million real generated files,
pauses and resumes after changing a completed directory, and checks complete
coverage, last-page/global search access, bytes and peak memory below 512 MiB.
Run it serially with other native/filesystem/scale suites. The manual CI scale
job runs both historical and new volume benchmarks and preserves separate
sanitized reports.

`DISKWING_RUN_FILESYSTEM_TESTS=1` additionally enables native Finder Trash on a
new APFS image, UUID-bound recovery after volume rename/detach/remount, conflict
preservation and safe ExFAT Trash refusal. Only devices returned for each newly
created image may be renamed or detached. The developer SSD is never a test
fault target. Image APFS support is not physical cable-removal qualification.

Graphical provider acceptance must use a real application, transferred response
reuse without the original, new SSD writes, persistent profile preservation and
absence/reconnection. A redirected cache argument alone is not qualifying proof.
Generated GUI samples are explicitly simulated, cannot qualify providers and
must not touch installed application profiles. Starting the samples from an
internal temporary directory avoids requiring broader removable-volume access;
never grant a real data permission merely to make the samples pass. The installed
build 8 remains preserved while new candidates are qualified separately.
