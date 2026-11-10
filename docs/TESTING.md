# Testing

~~~sh
swift test -j 2
python3 -m unittest discover -s Tests/Packaging -v
python3 build.py
~~~

Use CACHESSD_TEST_TEMP=/path/on/a/disposable/development/volume to keep fixtures off a nearly full internal disk. Tests use isolated homes, stores, projects and injected volume providers. Never substitute personal caches, shell settings, projects, browser profiles or SDKs.

The default suite includes safety, abrupt subprocess exit/recovery, metadata/resource forks, indexed pagination/global search/export/retention, comparable growth and a real FSEvents callback, plus translation/resource checks. Default skips are explicit: two installed-tool query checks, seven actual native workflows, one million-entry benchmark and the subprocess-only crash worker. The parent crash test runs the worker itself and verifies recovery.

## Separate opt-in native checks

~~~sh
DISKWING_RUN_NATIVE_TESTS=1 swift test -j 2
DISKWING_RUN_INSTALL_TESTS=1 swift test -j 2 --filter NativeWorkflowTests
~~~

A prepared Mac needs npm, Bun, CocoaPods, Python/pip, uv, Homebrew, Java and an already installed Gradle wrapper distribution. Requested missing tools fail. The original Gradle query test may skip if no local distribution exists.

Actual workflows download small pinned public artifacts into disposable projects with a clean environment and disabled install hooks: npm/Bun is-number, pip/uv urllib3, CocoaPods Result, Gradle commons-lang3. Homebrew fetches hello into a temporary cache without installing a global formula. Existing local Gradle executables are used read-only; distribution download is not a prerequisite fulfilled by modifying personal data.

Native --offline proves the tool's offline mode for the tested artifact. It is not a disconnected network or cable test. pip --no-index correctly misses without a wheelhouse. Homebrew/CocoaPods tests establish cache reuse, not offline availability. The matrix in validation/ records exact versions, original retention and local fallback execution. Configuration/version changes require requalification before source release.

## Resource benchmark and updater compilation

~~~sh
DISKWING_RUN_SCALE_TESTS=1 \
CACHESSD_TEST_TEMP=/your/development/fixture-directory \
DISKWING_SCALE_REPORT=/your/private/scale-report.json \
swift test -j 2 --filter ScaleTests

DISKWING_ENABLE_UPDATER=1 swift build --scratch-path .build-updater -j 2
~~~

The scale test creates 999,000 real empty files in 999 directories (one million entries including the root), checks complete scope/global search/last-page access, memory and index bytes, then removes only its own fixture. Allow several minutes and enough external free space. Do not run two SwiftPM operations against the same scratch directory at once. The optional updater build verifies APIs/linking; no feed, keys, installation or signing is activated.

## Public CI

CI runs isolated Swift tests, Python packaging/readiness tests, an arm64 production bundle and signature/icon/resource checks. The separate updater job compiles the exact Sparkle dependency. The scale job requires a manual dispatch with run_scale enabled. Native workflows require explicit local opt-in and suitable tool availability. Default CI never installs personal tooling or publishes releases.

Developer ID, Apple notarization, runtime updater consent/signature rejection, VoiceOver, other Macs, real cable removal and the human beta remain independent acceptance gates. See [current evidence](validation/IMPLEMENTATION-2026-11-10.md). Raw machine-specific logs stay in ignored .local/ storage.
