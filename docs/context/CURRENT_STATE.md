# Current state

Updated 2026-11-10. The maintainer's [cache/volume experience plan](../plans/CACHE-VOLUME-EXPERIENCE-2026-11-10.md) is implemented on `codex/cache-volume-ux` in [PR #24](https://github.com/Gabriellimmaa/DiskWing/pull/24). Source promotion still awaits final scale, exact candidate/UI recheck and exact-head CI. Apple Silicon, macOS 14+, Lift, MIT and PT/EN remain the app scope; provider qualification has narrower explicit limits.

## Two primary flows

**Explore volumes** selects a mounted volume, independently from the cache SSD. Proven APFS System/Data members appear in one logical tree; every actionable entry retains its physical source/root identity. Hidden entries are included; unknown, protected, interrupted and other-mount coverage is explicit. A virtual native tree and attributed MIT treemap share metric/selection/navigation, including a containing-block highlight for nested selection. SQL pages and three global pending reads bound UI memory, including replaced views.

The new scanner has no fixed depth/item/row cutoff. Durable directory work, source revalidation, hard-link accounting, guarded retention/reset/aggregation and explicit fresh-versus-resume behavior preserve honest totals. Indexes can use the selected APFS SSD with a 1 GiB reserve; internal indexes retain 512 MiB/256 MiB protections. Storage opening is UUID/device/inode-bound and no-follow; existing-index discovery is read-only. Ejection suspends metadata discovery and closes actual old/current index connections. A missing source/index never becomes a complete zero-size result.

**Caches on SSD** chooses SSD → analyzes applications → reviews one selection → transfers/activates → tracks each result. Selected SSD/integration flags with no destinations show **No caches transferred**. Copy/configuration/verified current use are separate; retained local copies do not claim released space. CLI integration is part of the selected review, and empty caches are prepared within the same flow. Existing terminals need reopening. CLI executions that already ended are not claimed as runtime-observed.

Google Chrome 157.0.8103.39 has real normal-launch qualification on macOS 26.5.2(25F84), arm64/APFS. The derived Library/Caches directory can transfer; four fixed Application Support subcaches remain separately measured local exceptions. Cursor/Xcode/Safari remain explicit exceptions; Safari effective total is unconfirmed. Google identity, version/platform, root/link and durable copy-policy contracts are checked. The original is released only after reviewed source stability and real application access evidence. Missing SSD can use Chrome network/memory; reconnect/reopening is distinct from unexpected physical unplug. See [graphical evidence](../validation/GRAPHICAL-CACHES-2026-11-10.md).

Manual **Trash** has a separate policy from generic Move and works for eligible personal content on qualified volumes, including unmanaged caches. Volume/item identity is rechecked; native APFS/HFS+ Trash and same-volume recovery after rename/remount/conflict passed; ExFAT refusal passed. No permanent-delete fallback or empty-Trash action exists. Managed caches, recovery, credentials/profiles, system roots, installations, links/placeholders and unknown unsafe data remain protected.

After a reviewed volume removal, the row stays marked **In Trash** with stale totals until explicit refresh. Pagination/ordinals do not shift under a pending query. Another unchanged item may be reviewed without a full-volume rescan, with all current filesystem checks preserved. Cache operations mark an old explorer snapshot stale without starting a hidden scan that blocks their result/verification flow.

## Preservation and evidence

The installed normal **1.0.0 build 8** and build 6/build 3 backups remain preserved. All 12 installed archive-file bytes and strict signatures were rechecked. No personal cache migration, file deletion, shell/Xcode/login activation or physical disk fault was performed. Earlier installation records remain [here](../validation/LOCAL-INSTALLATION-BUILD8-2026-11-10.md).

The integrated default suite passed378 discovered/348 executed/30 explicit skips, then383 discovered/353 executed/30 skips after later fixes, with zero failures. All 51 packaging cases passed. Independent review covers the cache, storage, source guards and UI; the real Chrome workflow passed both in the worker (50.672s) and integrated coordinator (35.492s). New samples were observed in PT/EN at minimum size; their findings led to small result-navigation/translation/layout fixes awaiting final-package recheck. See [review](../validation/CACHE-VOLUME-REVIEW-2026-11-10.md) and [native UI notes](../validation/CACHE-VOLUME-UI-2026-11-10.md).

Earlier new-volume scale attempts were explicitly aborted for performance and their own generated fixtures removed. They are not accepted evidence. A final run on the bound factory, with scoped validation amortization and a scoped 64 MiB SQLite cache restored after the operation, is in progress. FULL durability and all transaction/resource/source identity boundaries remain enforced. No prior legacy benchmark is used to attest the new engine.

The intermediate local build 9 is preserved separately and was not installed; a newer final candidate will have its own clean-source manifest, exact ZIP and qualification. Neither a successful local build nor these developer observations is notarization or human acceptance.

## Remaining gates

1. Finish the actual new >1M-entry run and record measured time/RSS/coverage/totals/resume/search/last-page evidence.
2. Recheck the final sample package after the small UI findings, qualify the exact new normal ZIP with a disposable internal lifecycle, and pass PR/main CI on macOS 15/26 with optional updater compilation.
3. With actual resources: Developer ID/notarization and signed-update exercise; another physical Apple Silicon Mac/macOS 14; a disposable physical-fault device; hands-on PT/EN keyboard/VoiceOver and five general plus five developer participants with seven real days. Agent/CI evidence never substitutes for these gates.

`publicV1Ready` remains false. The [roadmap](../ROADMAP.md), [ledger](../TRACEABILITY.json), [earlier expanded-flow record](../validation/EXPANDED-FLOWS-2026-11-10.md) and [historical session](SESSION-2026-11-10.md) retain their own source/artifact boundaries. Further ccache/pnpm/store breadth, duplicate detection, assisted uninstall and Intel support remain outside the currently qualified set. No background agent service is assumed after the active session.
