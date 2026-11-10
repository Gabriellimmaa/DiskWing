# Repository consolidation — 2026-11-09

Approved: MIT; consolidated public context; private machine-specific evidence; retain the separate ChatGPT project.

Final CacheSSD 0.1.0 sources were compared with the delivered archive before import. Original plans, logs, intermediate sources, packages, artwork, and visible messages are preserved in ignored .local/migration/ storage with a SHA-256 inventory. Reasoning traces, credentials, internal global Codex state, and unrelated memories are not imported.

Public structure: SwiftPM at the root; docs/ for context/plans; design/ for approved and historical artwork; .github/ for contribution/CI. DiskWing is the visible name; technical/data identities remain compatible.

## Validation

The original alpha passed 26 Swift tests. Consolidation adds packaging-boundary tests and makes two installed-tool checks opt-in.

Local checks completed:
- 265 archived source/artwork/package files verified, zero unavailable files; 18 implementation/test/package files matched the delivered source ZIP.
- Isolated Swift suite: 24 passed, two native checks explicitly skipped, zero failures.
- Native checks enabled: all 26 Swift tests passed, no skips or failures.
- Five Python packaging-boundary tests passed.
- Production bundle: strict ad-hoc signature, DiskWing display name, compatible bundle ID, and approved Lift icon bytes verified.
- Artwork generators and iconutil completed in an isolated copy using declared sharp/fontTools dependencies; approved assets were preserved. npm audit reported zero known vulnerabilities for the locked artwork dependency tree.

CI and final source-removal status are checked after publication. Raw paths, UUIDs, and logs remain private.

## Continuity

The old workspace goes to Trash only after verified preservation and publication checks. Existing chats stay in Codex and join the repository project. The separate ChatGPT project is preserved.

The local project points to the checkout. Its old display label requires the official project-edit UI when no rename tool is available. No internal Codex state is edited. Consolidation does not activate cache operations or publish a release.
