# Expanded core-flow qualification

The [expanded scope](../plans/SCOPE-EXPANSION-2026-11-10.md) is implemented and independently reviewed. The current local candidate is **1.0.0 build 8**, source `9be84dd484a20a584251c93f8138e88ddbbe2691`, with a clean-source [manifest](candidate-1.0.0-build8-local.json) and successful [exact-archive qualification](expanded-build8-qualification.json). Build 7 is superseded. The installed build 6 and its earlier backup remain preserved.

## Implemented behavior

- Manual Trash has its own home-content policy, including application caches, instead of inheriting generic Move's six-folder whitelist. Structural roots, known credentials/profiles, SDKs/linked environments and DiskWing records remain protected. Links, special files and undownloaded cloud placeholders are refused.
- Review shows application-data/cache consequences. Content goes to macOS Trash, which the app never empties. Analyses and inventory are refreshed after mutations, or the analysis is explicitly marked stale.
- Empty/absent caches can prepare a destination with a durable configuration journal, no-follow directory creation and settings identity/content checks. The local cache is not created or removed, and terminal integration is not enabled automatically.
- Yarn Classic and Go build cache require exactly qualified versions and retain their origins. ccache remains inactive without native qualification. The seven legacy adapters retain their conservative compatibility policy; Bun/uv origins stay local.
- Native/project/environment/command preferences take precedence. An additive v2 marker detects old integration scripts, which require explicit reviewed refresh and a new terminal. Prepared destination, copied payload and routing availability have distinct states.
- The internal-storage shortcut selects the APFS data volume. Identity-proven mapping handles Foundation firmlinks and DirectoryEnumerator spelling changes while preserving mount boundaries, link metadata and private-index exclusion.

## Checks and independent review

The combined source at `07a0aa5` passed **244 discovered Swift cases: 219 executed, 25 explicitly skipped, zero failures**. Updating npm's qualification binding to 10.9.2 then passed 18 targeted configuration/application cases, with one explicit native-APFS skip and zero failures. All 51 packaging tests passed.

Independent reviewers examined each implementation and the final fixes. Their own repetitions included 20 initial and 23 follow-up ManualTrash cases,35 cache/configuration cases and 16 coverage/index/negative-alias cases. A further 34 targeted cases covered a real generated APFS alias, private-index exclusion, a leaf link without duplicate counting, system temporary-directory aliases, coverage/indexation and application acceptance. These are local/developer checks, not human acceptance.

Three confirmed follow-ups were corrected before build 8:

1. npm's protected-value filter rejects UUID-bearing `config get cache` paths. Validation now runs a fixed generated script through npm, offline with hooks disabled, fixed `/bin/sh` and quoted `npm_node_execpath`. It compares the exact destination without cleaning cache contents. Regressions preserve unindexed content and defeat an ancestor `node_modules/.bin/node` shadow.
2. macOS 15 URL directory hints differed for absent Trash sources. Raw-component `lstat` proof replaces redundant Foundation URL equality, preserving no-follow behavior. Recovery tests bind their checkpoint's journal ID rather than ambiguous equal-second ordering. macOS 15/26 and optional-updater CI passed this fix at [e761947](https://github.com/Gabriellimmaa/DiskWing/actions/runs/42870900205); final combined-head CI is recorded in the live ledger.
3. Data firmlinks and `/private/var` abbreviation required preserving the enumerator's physical spelling and remapping only identity-proven aliases. A vanished Data entry that cannot prove identity still stops the scan explicitly rather than producing a falsely complete result.

## Native cache evidence

At `29278464a81f5840916cfeb184e0775aa1910fed`, the author executed 48 of 49 cases with zero failures and one explicit ccache skip: 35 core/configuration, nine legacy/regression cases and four expanded native workflows. See the sanitized [native follow-up report](native-followup-2026-11-10.json), [Yarn report](expanded-yarn-2026-11-10.json) and [Go report](expanded-go-2026-11-10.json).

| Tool/profile | Observed evidence | Limits |
|---|---|---|
| npm 10.9.2 | Generated original cache held unavailable; SSD offline install succeeds without recreating it; npx sentinel and held digest preserved; original restored for local offline fallback | Simulates origin unavailability; transactional source release remains covered separately by core guards/tests |
| Yarn Classic 1.22.22 | Existing PnP project remains executable with its local original; copied cache reused offline, new dependency written to SSD and local fallback; empty-cache preparation | Original retained; modern Yarn and custom/PnP routing remain outside this adapter's automatic coverage |
| Go 1.27.3 Darwin arm64 | Generated binary built/executed with copied build cache; new SSD entries, local fallback and empty-cache preparation | Original retained; module stores/tool installations excluded; official runtime temporary, no global installation |
| Bun/pip/uv/Homebrew/Gradle | Real generated installs/builds/cache reuse and documented local fallback passed | pip requires a wheelhouse for empty-cache offline use; Homebrew network-offline availability is not established |
| CocoaPods 1.16.2 with explicit existing Ruby 3.3.6 | Generated Podfile install, migration and reuse passed using an explicit runtime profile | A clean incompatible launcher was separately refused with source/settings preserved. Inherited application environment was observed native-available; neither observation establishes universal default availability. No gems/global launcher changed; offline network isolation not established |
| ccache | Runtime unavailable; explicit skip | No qualification or activation |

All native homes, projects, caches and stores were generated. Source/destination directories were on the same filesystem and volume availability was injected. This does not prove physical internal-to-external throughput, cable removal or another Mac. Static Go/Yarn discovery does not execute commands that initialize personal telemetry/caches; explicit Go validation uses a fresh home/config.

## Interface and artifact

Build 8 samples native UI was observed in Portuguese/English at minimum 1050 × 690. Reviewed Trash/cancel/confirm refreshed the analysis in both languages; missing-cache preparation kept the local source absent and displayed pending routing; fixture-only integration exposed the reviewed update control. Yarn/Go source release stayed disabled, ccache migration/preparation stayed disabled, Esc cancelled review and basic keyboard language selection worked. No functional clipping/blocker was observed. The exact sample process was closed and its fixture/private record retained. This is a developer observation, not human VoiceOver/beta acceptance. An earlier locked-Mac attempt was not counted as a visual pass.

Build 8 archive SHA-256 is `b677e087e7e87cdddb607aa5224baa16d9d30ca77e2dd4c63f7c3a8863800ed7`. Its exact ZIP passed safe extraction, bundle identity, real temporary internal installation, signature/helper/resources, generated packaged flows and removal. No normal application replacement or personal migration/deletion/live integration was performed.

The signature is local ad-hoc. Developer ID/notarization, signed updates, another physical Mac/macOS 14, physical fault testing, hands-on accessibility and real beta evidence remain independent. publicV1Ready remains false. Build 7's prior [manifest](candidate-1.0.0-build7-local.json) and [archive checks](expanded-build7-qualification.json) are retained as superseded evidence, not promotion approval.
