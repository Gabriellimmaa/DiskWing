# Implementation evidence — 2026-11-10

Scope: the approved alpha-to-v1 roadmap. This is a development delivery, not a v1 release or completed human beta. The original import remains documented separately.

## Verified locally

| Check | Result |
|---|---|
| Full installed-tool suite | 69 Swift cases; 67 executed, two explicit skips, zero failures |
| Default isolated suite | 69 Swift cases; 58 executed, eleven explicit skips, zero failures |
| Packaging/installer/release-readiness suite | 15 Python tests, zero failures |
| Optional Sparkle 2.10.1 | Separate dependency/API/link build passed |
| Production application | arm64 release bundle, local ad-hoc signature, approved icon and bundled resource self-check |
| Native application smoke | Internal installation; DiskWing identity; Command-5/Command-O; PT/EN switching; 322 direct fixture entries, second page 121–240; global search found a nested item outside the current page |
| Resource benchmark | One million actual entries, complete scan, global search and final-page checks passed |

The two full-suite skips are the opt-in scale case and subprocess-only crash worker. The scale case passed separately; the parent crash test invokes the crash worker twice itself. Default skips additionally include two installed-tool checks and seven actual native workflows.

The scale fixture contained 999,000 real empty files in 999 directories plus its root. Scan: 192.94 seconds. Index after checkpoint: 502,796,288 bytes (479.5 MiB). XCTest process maximum resident size: 105,824,256 bytes (100.9 MiB). Creation, queries, teardown and test execution took about 304 seconds. This is one debug-build run on this Apple Silicon development Mac/external SSD, not a general speed guarantee or measurement of peak temporary disk usage. The fixture was removed afterward. See [raw sanitized metrics](scale.json).

The benchmark exposed a slow snapshot query and accumulated temporary Foundation objects. A directory-specific SQLite index and autorelease batches resolved those measured issues before the recorded successful run.

## Native workflow qualification

[Sanitized matrix](native-workflows.json), adapter revision 1:

| Tool | Version | Disposable workflow | Offline evidence |
|---|---|---|---|
| npm | 10.9.0 | is-number install and execution, external cache and local fallback | Native --offline succeeded |
| Bun | 1.3.3 | is-number install and execution; local original retained | Native --offline succeeded |
| pip | 26.2.1 | urllib3 target install/import, external cache and local fallback | --no-index misses as expected without a wheelhouse |
| uv | 0.13.7 | urllib3 target install/import in copy mode; local original retained | Native --offline succeeded |
| CocoaPods | 1.16.2 | Temporary Podfile with Result, no Xcode project integration | Cache reuse with --no-repo-update; disconnected network unverified |
| Homebrew | 6.0.17 | hello bottle fetch/reuse, no global formula installation | Cache reuse; disconnected network unverified |
| Gradle | 9.2.0 | Temporary Java build with commons-lang3, existing local distribution | Native --offline build succeeded |

Each workflow checked injected SSD absence routes locally and executed again with the retained local cache. These checks do not physically disconnect a cable or disable network access. Native versions differ across installations; exact qualification is bundled and unknown/custom configurations cannot release their original based on this matrix.

Bun creates absolute links to packages inside its own cache. Copies normalize verified internal links to relative links. Links outside the cache, including dangling external links, remain blocked. Bun/uv original retention is unchanged.

## Safety evidence

Tests cover unreadable/invalid shell configuration, unknown/missing measurements, a shared lease across mutating entry points, full destinations, protected nested project content, expected scanned identity, bytes/resource forks/mode/mtime, post-verification cancellation, post-publication failure, restore conflicts and source preservation. Actual subprocess _exit at publication and immediately after simulated Trash relocation leaves durable records and a recoverable verified destination. Recovery never overwrites a populated source; unavailable, changed or redirected copies remain for review.

Growth tests cover complete/partial/unavailable/wrong-volume states, actual FSEvents delivery, age-qualified comparisons, retention and folder coverage. Simulated timestamps prove comparison logic, not real seven-day use.

The installed app was inspected through its native accessibility tree, using disposable files only. No cache migration, shell activation, Xcode change, login registration, notifications, update consent or disk ejection was activated. Original CacheSSD.app remains recoverable. The language preference was returned to System after smoke testing. An accessibility-tree/keyboard smoke is not a full VoiceOver audit.

## Pending independent gates

- Developer ID Application certificate, notarization profile, accepted/stapled notarization and second-Mac Gatekeeper assessment.
- Real hosted signed appcast, update consent, valid/invalid signature acceptance/rejection, active-operation/relaunch and removal on another Mac.
- Complete hands-on VoiceOver/keyboard/language acceptance across supported macOS versions and users.
- Actual physical disconnect/power-loss and additional filesystem metadata/large-copy throughput checks.
- Five general users plus five developers with at least 80 percent independent success in each group, reviewed seven-day diaries and no critical blockers.

The beta evidence template is intentionally empty. The release-readiness validator rejects it. No public binary release, tag or update feed was created. Test logs, private configuration backups and personal inventories remain outside Git.
