# Autonomous delivery to DiskWing 1.0

Approved 2026-11-10. Target: a public, signed/notarized 1.0 with both disk exploration and reviewed selective cache management, PT/EN, Apple Silicon and macOS 14+. The maintainer authorized implementation, independent review, CI, pull requests, merges and publication within this scope. Work proceeds in active project sessions with durable handoffs, using existing resources without purchasing services. Signing credentials, another Mac and participants are not currently available.

## Team and ownership

One coordinator integrates changes; up to three workers are active at a time, normally two implementers and one independent reviewer. Specialist roles rotate: data safety/recovery; explorer/performance; cache integrations; macOS UX/accessibility; independent QA; distribution/updater; evidence/beta. An author cannot provide the sole approval of their own implementation.

Every task records requirement M0–M8, priority, classification (confirmed defect, experiment, external dependency), owner, dependencies, writable files, branch/base, acceptance and evidence. Worktrees/builds/fixtures use the development SSD except explicit minimal internal-installation/temporary-alias tests. Shared files have one owner at a time; the coordinator owns public context, translations, traceability and integration. Heavy native/filesystem/scale qualification runs serially. No worker pushes or merges independently.

Workflow: reproduce → implement → targeted tests → independent review → CI for exact head → serial merge → verify main. Repeated failures require independent diagnosis rather than blind retry. Before ending a session, update the execution ledger with integrated SHA, pending branches/tasks, direct checks, limits and the next action. On resumption inspect actual Git/CI state before recreating workers. This is not a persistent external service.

## Execution waves

0. Merge PR #12 and verify main. Maintain this agreement, AGENTS and the execution ledger in TRACEABILITY.json; link findings to existing milestones.
1. Renew release-source consent for every review; recover interrupted restores according to operation type; preserve explicit/effective cache configuration; bound/cancel all preflight work; distinguish complete/partial/unknown measurements; reproduce repeated-index-budget behavior; resume pending growth scans after Low Power Mode ends.
2. Add explicit isolated GUI acceptance context with generated home/store/volumes/preferences and substitute OS integrations. Never fall back to live state. Restrict mutations to generated paths and show sample-mode identity. Test both GUI journeys, recovery discovery, meaningful PT/EN messages, keyboard/accessibility semantics and layout constraints while preserving Lift.
3. Bind candidate reports to commit/version/build/full archive SHA-256. Fail closed on malformed/unknown/mismatched readiness evidence. Test updater consent/operation/relaunch coordination. Separate local builds from production, which requires Developer ID and accepted/stapled notarization. Preserve sanitized qualification reports; run arm64 CI on macos-15 and macos-26. macOS 14 remains an external compatibility check because its hosted image was retired.
4. When external resources arrive: sign/notarize; verify another physical Mac and macOS 14; hands-on PT/EN keyboard/VoiceOver; valid/tampered update exercise in a separate channel; five general and five developer beta participants with at least 80% independent success in each cohort and seven real days; resolve blockers; qualify and publish 1.0.

## Qualification and release

Cover interruption at copy/verification/publication/configuration boundaries, no overwrite under conflicts or changed identity, legacy digests/journals, custom native configuration, missing/unqualified tools, missing SSD/local routing, unknown/partial readings, repeated limited-index scans and energy transitions. GUI journeys operate only on samples. Run one-million-entry and many-file benchmarks plus a 4 GiB actually written copy, with time/memory/cancellation recorded; APFS, read-only/full images and safe ExFAT refusal; real temporary internal installation and packaged resource execution.

A green test count is not release acceptance. No unresolved data/security/core-flow/distribution blocker may be promoted. Evidence identifies the tested artifact; functional changes reopen affected qualification and unrelated artifacts cannot inherit approval automatically. Unknown schemas and old evidence are preserved, not silently approved.

Default public delivery is GitHub Releases for binaries and GitHub Pages for separate HTTPS update channels, with no purchased domain. Archive/sign according to the pinned Sparkle requirements. Public signing/update deployment remains gated by actual credentials and verified acceptance; no credentials/private keys enter Git.

## Invariants and external handoff

Preserve Chrome, personal files, installed environments, SDKs and projects. Bun/uv origins remain local. No automatic cleanup or intentional cloud hydration; no physical fault injection on the development SSD. CacheSSD identifiers, historical plans and settings remain compatible. No private invitation/contacting participants without specific authorization. Agent/CI results never stand in for physical-device or human evidence.

Continue every executable task before ending a cycle. When only external prerequisites remain, provide a complete local candidate and one consolidated dependency packet: Developer ID/notarization/update key, publication permissions, another Mac/macOS 14, accessibility reviewer, disposable fault device and ten participants/real observations. Save state and resume when inputs arrive. Completion means public source/docs, signed/notarized 1.0, verified updates and actual human acceptance—not merely a compiled app.
