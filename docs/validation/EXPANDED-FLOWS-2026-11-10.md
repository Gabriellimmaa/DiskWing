# Expanded core-flow qualification

The maintainer authorized the [expanded scope](../plans/SCOPE-EXPANSION-2026-11-10.md)
on 2026-11-10. This record describes a new engineering increment; it does not
replace build 6's immutable evidence or approve a public release.

## Implementation and independent review

- Manual Trash uses its own home-content policy, including application caches,
  instead of inheriting generic Move's six-folder whitelist. Structural roots,
  known credentials/profiles, SDKs/linked environments and DiskWing records stay
  protected. Unsupported links, special files and cloud placeholders are refused.
- Review exposes application-data/cache consequences. Content goes to macOS
  Trash, which the app never empties. The explorer is refreshed or marked stale
  after mutations; the cache inventory is refreshed as well.
- Cache setup accepts an empty/absent source, journals before mutation, uses
  no-follow destination creation, checks settings identity/content and leaves
  interrupted configuration records for review. It never creates the local
  source or enables shell integration automatically.
- The catalog adds Yarn Classic, Go build cache and ccache. New adapters require
  exact qualified versions for activation and routing. Yarn/Go origins remain
  local. ccache has no native qualification and remains inactive.
- Script capability v2 is an additive comment, preserving old paths/markers.
  Existing terminal integration requires explicit reviewed refresh and a new
  terminal; a prepared destination is not reported as a migrated cache.

The Trash author reported 70 affected passing tests; an independent reviewer
repeated all 20 new ManualTrash tests at 2c9bd8c with zero failures. The cache
review identified and resolved effective ccache/Yarn configuration loss,
post-checkpoint path redirection, unbounded/blocking settings reads and false
Yarn directory classification. A different author reviewed 46cf3ac and repeated
35 cache/configuration tests with zero failures.

## Native cache evidence

At e661d2f the cache worker ran 40 cases: 39 executed, one explicit ccache skip,
zero failures. Four generated native workflows covered:

| Tool/version | Evidence | Retention and limits |
|---|---|---|
| Yarn Classic 1.22.22 | [Sanitized report](expanded-yarn-2026-11-10.json): PnP project still executable, migrated cache reused offline, new dependency written to SSD, local fallback and empty-cache preparation | Original retained; no claim about modern Yarn or all existing projects |
| Go 1.27.3, Darwin arm64 | [Sanitized report](expanded-go-2026-11-10.json): generated binary built/executed, copied build cache reused, new SSD entries, local fallback and empty-cache preparation | Original retained; module stores/tool installations excluded |
| ccache | Runtime unavailable; explicit skip | No native qualification; cannot activate |

The Go runtime was downloaded into private temporary development storage from
the official distribution and checked against its published SHA-256. No runtime
was installed globally. Probes that could initialize personal Go telemetry were
replaced with static installation metadata; explicit validation uses a fresh
home/config. Native cache tests used generated data, controlled process guards
and injected volume availability, not a physical SSD removal. The subsequent
exact-version gate changes eligibility, not the tested cache mechanisms.

## Coverage and remaining gates

Internal storage uses the writable APFS data volume as an explicit scope.
Foundation firmlink/DirectoryEnumerator spelling differences require identity-
proven normalization, with private-index exclusion and no traversal through
links or other mounts. The native positive fixture and final integrated/package
results are recorded below when complete; initial failed probes are diagnostic,
not acceptance.

Only generated homes, caches, projects, stores, Trash substitutes and the tiny
native APFS fixture are operated. No personal migration/deletion, live terminal
activation, Xcode setting change, normal-app replacement or physical fault is
part of this increment. The maintainer's installed build 6 and previous backup
remain preserved. Other-Mac/macOS14, physical faults, human keyboard/VoiceOver,
real beta, signing/notarization and signed-update acceptance remain independent.

## Final local result

The independently reviewed code is ecdf1afd6562941741f055f80291b35be230ce41.
Its full Swift suite discovered 239 cases, executed 216, explicitly skipped 23
opt-in/worker cases and reported zero failures. All 51 packaging tests passed.
The APFS/native and related regressions passed 34 targeted cases with no skips:
identity-proven Data alias, private-index exclusion, leaf-link metadata without
duplicate allocation, normal temporary-directory aliases, coverage/indexation
and generated application journeys. Foundation's Data firmlink normalization
and `/private/var` abbreviation defects were reproduced and corrected before
this result. A vanished Data entry that cannot prove identity still stops the
scan explicitly; it never becomes a falsely complete scan.

The new local 1.0.0 build 7 has a clean-source
[manifest](candidate-1.0.0-build7-local.json) and passed the
[exact-archive qualification](expanded-build7-qualification.json): safe ZIP,
bundle identity, real temporary internal installation, signature/helper/resource
checks, generated acceptance flows and removal. Archive SHA-256:
`e9bfcfb829fc8a02011bc7827bd2511dc2c65cbe2ecb21b7f16422ac9d44e7d3`.
It is ad-hoc signed, not publicly notarized; publicV1Ready remains false.

A native visual sample review was attempted but the first CUA app selection
reported that the Mac was locked. No window/banner, minimum-size layout or
visual PT/EN journey was observed. Only the separately launched sample process
was closed, its exit confirmed, and its generated fixture/private record
retained. Automated PT/EN journeys above do not substitute for this missing
visual or human accessibility acceptance. Installed build 6 and its previous
backup were not replaced by build 7.

## Follow-up qualification reopened

Additional checks after build 7 found two code/compatibility follow-ups before
integration: npm's `config get cache` rejects real UUID-containing destination
paths as protected values, and macOS15 compares directory hints differently
when assessing a missing Trash source. The candidate is superseded pending
these fixes and a new build8; earlier successful archive checks remain valid
for their stated scope and are not sufficient promotion evidence.

The legacy native run also identified a CocoaPods prerequisite mismatch:
the default Homebrew launcher selects Ruby3.4 while its installed ffi dependency
requires an older Ruby. No gems or global launcher were modified. Qualification
with an explicitly selected existing Ruby3.3 profile, if performed, is separate
from availability of the default launcher. An unavailable launcher must keep
the adapter fail-closed and preserve its source.
