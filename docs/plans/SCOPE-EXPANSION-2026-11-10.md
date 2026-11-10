# Expanded cache and explorer scope

Authorized by the maintainer on 2026-11-10. This amends the live product scope;
the historical approved cache plan remains unchanged. Implementation and
qualification are separate, and build 6 and its previous-version backup remain
preserved during this work.

## Product contract

1. Cache management transfers existing eligible cache data and directs future
   writes to the selected SSD through each application's supported mechanism.
   An empty or absent cache must also be configurable. A verified copy alone
   does not mean routing is active. Report retained originals and any scope
   outside the integration explicitly.
2. The explorer lets the user inspect storage, navigate by size and explicitly
   send selected eligible content to macOS Trash, including application caches.
   Manual deletion has a distinct policy from generic file relocation. Unknown
   content is never classified as disposable merely because of its location.
3. Coverage is explicit: system/data volumes, access failures, other mounts and
   resource limits must not disappear behind a claim that the entire Mac was
   scanned. Provide a direct entry for the internal data volume on split APFS.

## Acceptance criteria

| ID | Required evidence |
|---|---|
| C1 | Each adapter distinguishes cache payload, settings, profiles, credentials, installations and projects. |
| C2 | Existing native/project/environment/command configuration wins; inspection does not initialize personal caches. |
| C3 | Generated native workflows prove reuse of transferred data and new writes to SSD, plus local fallback and disable/restore behavior. |
| C4 | Empty/absent local caches can prepare a destination without creating personal source directories or silently enabling shell integration. |
| C5 | The UI distinguishes verified copy, retained/released original, future-write configuration and terminal activation. |
| C6 | Source release requires specific native evidence and stable source; missing/unqualified tools cannot inherit compatibility from fixtures. |
| E1 | Explicit Trash works for eligible home descendants, including Library caches, independently of the stricter Move policy. |
| E2 | Review shows the actual path, measured/unknown size, application-data consequences and that Trash still occupies space. |
| E3 | Structural roots, system, credentials, protected profiles/SDKs/environments, DiskWing records and ancestors remain protected. |
| E4 | Identity, tree readability, no redirection/cloud hydration, process use, cancellation and final source stability are checked. |
| E5 | Durable Trash recovery works for newly eligible cache paths and refuses overwrite of recreated content. |
| E6 | After a mutation, invalidate or refresh the displayed analysis; stale results cannot remain presented as current. |
| E7 | Internal data-volume entry, selectable scopes, partial coverage and PT/EN remain usable with keyboard navigation. |

## Cache expansion and evidence policy

The first implementation increment adds Yarn Classic, Go build cache and ccache
to the existing seven adapters. Yarn Classic retains its original cache because
existing Plug'n'Play projects may reference it. Modern Yarn, Go module stores,
pnpm stores/dlx, SDKs, installed runtimes, Chrome profiles and broad system cache
redirection are not silently included. Go/ccache unavailable on a test machine
remain unavailable/unqualified until a disposable native workflow proves their
contract. Catalog presence alone is not acceptance.

Research pnpm metadata separately from its linked package store, and graphical
applications separately from terminal inheritance. Xcode's documented build
locations are a candidate for a dedicated integration; private preference keys
or a successful CLI fixture do not prove normal Dock launch coverage. Preserve
Chrome and all existing protected data. Record the candidate matrix and rejected
mechanisms with primary-source evidence before expanding further.

Primary mechanism references: [Yarn Classic cache](https://classic.yarnpkg.com/lang/en/docs/cli/cache/),
[Yarn 1.22.22 rc discovery](https://raw.githubusercontent.com/yarnpkg/yarn/v1.22.22/src/util/rc.js),
[Go build cache](https://go.dev/cmd/go/),
[Go telemetry](https://go.dev/doc/telemetry),
[ccache configuration](https://ccache.dev/manual/4.14.1.html),
[Xcode build locations](https://help.apple.com/xcode/mac/current/en.lproj/deva52afe8a4.html).

## Autonomous team and execution

Use all available agent capacity, with no fixed organizational ceiling on total
specialists. This session exposes four concurrent slots including coordination.
Rotate specialists through the three worker slots as tasks finish. A worktree
and exclusive file ownership isolate each implementation. The coordinator alone
updates shared context, translations, traceability and integration.

| Wave | Parallel work | Completion gate |
|---|---|---|
| 0 | Cache/native-mechanism research; explorer/safety audit; independent scope review | Reproducible gaps, acceptance IDs and ownership recorded. |
| 1 | Trash policy/operation/recovery; cache adapters/future-write preparation; independent safety review. Coordinator handles UI and data-volume entry. | Targeted disposable tests; each implementation reviewed by a different author. |
| 2 | Rotate roles for native cache qualification, UI/accessibility journeys and adversarial recovery/configuration review. | Native evidence distinct from fixtures; no unresolved data-loss/core-flow findings. |
| 3 | Integrated regression, packaging and PT/EN sample journeys; independent final review. | Exact-head CI; affected qualification reopened for changed behavior. |
| 4 | New separately identified local candidate and durable handoff. | Preserve installed build 6; production signing, another Mac and human gates remain independent. |

Never run native, filesystem-image or scale qualification simultaneously. Each
run needs a coordinator-owned resource slot. Independent source reads and
isolated targeted tests can run concurrently in separate build directories;
do not oversubscribe storage with duplicate full suites. Merges are serialized.

Workflow: implement → meaningful targeted tests → independent review → fix →
integrated exact-head checks → PR/CI → serialized merge → verify main. Continue
executable work without asking for routine implementation approval. If a tool
or external resource is missing, record the concrete limitation and continue
independent work; do not substitute fabricated evidence.

## Preservation and handoff

Use generated homes, caches, stores, projects, volumes and injected Trash. Do
not test by migrating personal caches, deleting personal files, changing live
shell/Xcode/login configuration or unplugging development storage. Opening the
app performs no migration or cleanup. No automatic cleanup or telemetry is
introduced. Links/placeholders/special files unsupported by the reviewed Trash
contract are refused with an explanation; do not delete their targets.

Track requirement, branch/base, owner, writable files, dependencies, tests,
reviewer, status, integrated commit and next action in TRACEABILITY.json. Keep
raw/private evidence outside Git. A new functional candidate cannot inherit
build 6's artifact qualification or human approval. Developer ID/notarization,
signed update delivery, additional physical hardware, PT/EN VoiceOver acceptance
and real beta observations remain external gates.
