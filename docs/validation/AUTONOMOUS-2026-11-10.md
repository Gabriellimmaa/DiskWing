# Autonomous v1 preparation — 2026-11-10

This record supplements historical reports. It is local/agent evidence, not human beta, another physical Mac, notarization or public v1 acceptance. Raw logs, generated-session paths and participant evidence remain private.

## Baseline and independent review

PR #12 merged at fff0d6b after its approved CI; main run 42762937392 passed. Work uses feature/autonomous-delivery and three isolated SSD worktrees. The coordinator is the only integrator.

| Area | Integrated commits | Independent review |
| --- | --- | --- |
| Restore-aware recovery, cancellable preflight, legacy digest memory | f704b32, 498f2cf, cf6260c | Coordinator and distribution reviewer; changed-volume generation issue fixed before promotion |
| Effective cache configuration, npm selectors, conservative discovery | d86c710, 8d1bdbe, e94fb3d, 4bc68ab | Distribution reviewer; quoted/abbreviated selectors, global files and deep ancestors covered |
| Coverage and repeat-scan budget | f57a1ab, 55b9e59 | Distribution reviewer; 2,200-file experiment reproduced quota exhaustion before the fix |
| GUI sample context/consent/energy and isolation | 0e2e16e, dde371d, 749cf6b, 1871a45 | Coordinator, safety and distribution; scoped storage/Trash/recovery follow-ups recorded below |
| Updater policy and bridge | 8adf40e, dc29c81, de8bfe1, 5c84879 | Safety and distribution; future-schema and startup-lock findings fixed |
| Archive, readiness and runner matrix | 79a164d, 253d7f1, 95e0c86, e4175f3 | Safety reviewer; hash/parse race reproduced, then rejected by single-snapshot verification |
| Exact-archive lifecycle diagnostic | 74e2427, 7533378 | Coordinator and safety; 16 Python checks repeated independently; snapshot/hash, ZIP namespace/local-header/link checks and lifecycle reviewed |
| Full PT/EN controller journeys | f2e9c3b | Coordinator and distribution; generated checkpoints explicitly simulated |
| Scoped sample recovery | 41110c0, 5eaaa33 | Distribution; sibling-copy read reproduced after journal change, then refused under lease |

These commits identify integrated equivalents of the inputs reviewed in isolated worktrees; the coordinator checked integration and the execution ledger links subsequent qualification. Author tests and independent checks are separate evidence. No author supplied the sole approval.

## Local resource qualification

All heavy tests ran serially on generated fixtures, never on personal caches or a physical development-disk fault target.

| Check | Direct result | Limits |
| --- | --- | --- |
| One million index entries | Complete; 160.22 s scan; index 502,853,632 bytes; peak resident 112,328,704 bytes | One Mac/filesystem; no human usability claim |
| 4 GiB actually written | 4,294,967,296 logical bytes; 4,308,598,784 allocated; verified copy 71.48 s; peak resident 27,803,648 bytes; cancellation/source preservation passed | Same-volume generated data; not cross-device throughput or cable/power loss |
| Many-file copy | 20,001 files, 201 directories; 50.04 s; peak resident 35,815,424 bytes; source/copy verified | Includes a sparse 64 MiB file; distinct from written-4-GiB case |
| Disposable filesystems | Four APFS/ExFAT checks passed, plus many-file case (five total) | Only newly generated disk images; physical SSD never detached |
| Native workflows | Seven real disposable install/build/fetch workflows passed; qualified versions unchanged | Hooks/config/auth isolated; local fallback verified; offline limits remain explicit |

Native versions: npm 10.9.0, Bun 1.3.3, CocoaPods 1.16.2, pip 26.2.1, Homebrew 6.0.17, Gradle 9.2.0, uv 0.13.7. Native offline reuse passed for npm/Bun/Gradle/uv. pip no-index correctly misses without a wheelhouse; Homebrew/CocoaPods reuse is not proof of network disconnection.

Benchmark report fields contain no paths or disk UUIDs. Hashing changed only buffer lifetime; historical SHA-256 input compatibility has regression coverage.

## GUI experiments and corrections

The acceptance application has its own bundle ID and generated context. First launch on the external development volume stalled before the first window; process sampling located filesystem work in synchronous App initialization. A minimal private internal temporary workspace opened immediately. This does not prove a specific TCC cause; bootstrap was moved out of App initialization and the external behavior must be recorded separately.

Native inspection confirmed sample banner, 151-entry pagination (120/page), global nested search, keyboard selection and shortcuts, Escape cancelling review, fresh release-source checkbox, cache migration/restore preserving the SSD copy, simulated disconnection, local-mode control, generated-shell integration/disable and PT/EN switch. No native package tool, real shell, login, Xcode, notification or volume ejection was activated.

A legitimate personal move hit a /private/var versus /var comparison after copy verification. Origin/copy were preserved and the recovery banner appeared; resolution kept both. Three positive regressions (SSD/internal physical/internal alias) and the external-link refusal cover the correction. Full controller journeys cover move → restart/recovery → resolve and cache → restore → local → disable in both languages. Simulated durable checkpoints are not physical crash observations.

Final recovery was repeated through the native UI from a temporary internal copy of the same sample bundle: reopening discovered the generated pending checkpoint, restoration succeeded and SHA-256 matched across source, verified destination and preserved original. The pending checkpoint was simulated deliberately. A first internal launch waited about 45 seconds in macOS assessment before AppKit; relaunching the same bytes succeeded immediately, without changing TCC or quarantine.

Minimum-window testing reproduced clipped explorer controls and a missing Cmd+O after deferred startup. The responsive correction (e952f4b), persistent commands (e2ae872) and model observation forwarding (fd9fed7) were independently reviewed. Native rechecks at 1050 × 690 content size in PT/EN confirmed the explorer's header, filters, table, inspector and footer remain within the window, Cmd+O scans samples, and language changes update native labels and formatting. The isolated window menu also works through keyboard navigation. The Picker retains its accessibility label while hiding the narrow visible caption.

Final suite/candidate results will be recorded in the qualification supplement. These local UI observations do not establish human keyboard/VoiceOver acceptance. VoiceOver and independent human task success remain pending.

## Promotion boundaries and remaining dependencies

Production readiness requires a clean production manifest and matching full ZIP, actual Developer ID/notary/staple/Gatekeeper/updater checks and candidate-bound reviewed evidence. Dev/acceptance/local candidates, malformed or unsupported schemas, stale/other-candidate records, linked evidence and automated records presented as human are refused. The reader hashes and parses one bounded buffer.

Required external inputs: Developer ID Application certificate, existing notarization access and protected Ed25519 update key; another physical Apple Silicon Mac plus macOS 14 minimum; PT/EN keyboard/VoiceOver human reviewers; a separate disposable physical-fault device; five general and five developer participants with >=80% independent success per cohort and seven real days. Repository publication is authorized and checked through source delivery; it is not a new approval dependency.

No public binary, feed, tag or notarization claim is made by this preparation. A production rebuild will be a different candidate and must receive its own applicable evidence.

## Integrated qualification checkpoint

The integrated local run discovered 172 Swift cases: 157 executed, 15 explicit opt-in/worker skips, zero failures, with the two installed-tool query cases enabled. A subsequent ten-case category/index follow-up and nine bootstrap-observation cases passed. The final APFS/ExFAT suite was repeated after scoped-recovery alias changes: four passed. Python packaging/readiness/exact-archive suite: 51 passed; sixteen new archive cases and nine bootstrap cases were also repeated independently. Exact-head CI is the final authority for the complete current suite on both runner versions.

Sample GUI archive identities observed in this cycle: 891539cf960d4c6bb74963a0ebfb2fec9a2d67331b7d8b8a5293555e325e4fda (internal relaunch and recovery); c56bd7bd327099b3b7701c1cddbbff54b5ffadfe721de3797da2692523a47256 (window control); later responsive/observation fixes were rebuilt under new manifests. These are ad-hoc dev/sample archives, not a public candidate or transferable human approval. The exact local 1.0.0 archive and its new full-archive lifecycle report will be recorded separately after main delivery.

Public review inputs contain no newly introduced personal home/volume paths, certificates or private observations. No normal installed app, Chrome data or real integration was changed. Only generated disk images were mounted/detached. Source publication permission is present; no new approval is required for the approved PR/merge cycle.

## First cross-version CI feedback

PR19 head 30e6b4d: macOS26 passed the complete suite, packaging, immutable-archive internal lifecycle and optional updater compile. macOS15 passed optional updater compilation but failed five default-configuration/routing assertions. Every failing negative case shared the bounded ancestor walker; injected empty pip globals/environment ruled out host global configuration as the common cause. The source depended on Foundation URL equality to recognize the filesystem root.

The follow-up stops at the actual root path, preserves the root configuration check and forty-level conservative limit, refuses non-file directories and retains fail-closed behavior if traversal stalls elsewhere. Root/localhost variants and the original affected cases pass locally; independent review approved the change. The new exact-head macOS15 CI remains the decisive confirmation. The earlier local build4 from30e6b4d is superseded, private and ineligible for promotion; a newly qualified candidate will use a new build number.

## Controlled checkpoint follow-up

The root-path correction passed the complete macOS15 CI suite, packaging and archive lifecycle. The same head encountered a different macOS26 failure: the crash worker received a nonempty busy inspection after copy verification and never reached its intended publication checkpoint. Source data was preserved; later assertion failures were cascading expectations. The process responsible was not recorded, so an indexer/security service remains a hypothesis. Independent reproduction confirmed that an unrelated reader can trigger this check without changing bytes.

Checkpoint tests now inject a controlled BusyCheck and assert the exact checkpoint, while production defaults still execute the real inspection and propagate errors. The real open-file test remains mandatory. Generated GUI/helper contexts also use explicit controlled checks and never gain a public bypass option. This separates process-inspection evidence from fault-boundary evidence instead of accepting arbitrary thrown errors.

Review also found a real late-use gap: a personal move needed a final busy inspection before Trash. A deterministic regression proved that a reader appearing after publication/trashing must preserve both source and verified destination and keep the recovery record pending. Cancellation/content must be rechecked after a potentially slow inspection. The integrated pre-follow-up run executed 162 of 179 cases with 17 explicit skips and zero failures; final exact-head CI will qualify the completed correction. No former candidate inherits this affected qualification.

The final terminal order is process inspection, source identity, cancellation/content verification, then cancellation once more immediately before Trash. Four regressions reproduced cancellation or child mutation during the slow query and now preserve source and published copy without invoking Trash. Default real process checks and their open-file control remain intact; no ambient test flag can disable them in the application. Independent review approved both the API injection and terminal ordering.
