# Project context

## Intent and approved decisions

DiskWing helps Mac users understand and recover storage, with developer-cache integrations as an initial specialization. The founding requirement is to use the Mac and Chrome without the external SSD. Moving every system cache is outside the supported approach.

The approved plan uses native per-tool configuration and chooses a destination when a command starts. Existing processes keep their environment. No whole-system cache-directory symlinks or automatic merging of generations. Chrome data and caches, SDKs, emulators, projects, and service executables remain local.

Every data-changing action has a review. Verify copies before releasing eligible caches; record recovery information. Bun and uv sources remain local because installed environments may reference them by links. Do not silently relax this protection.

## Product evolution

1. Research and read-only inventory identified selective native cache routing as the compatible direction.
2. Cache plan v1 was approved and retained as the historical baseline.
3. The product expanded to a disk-usage explorer inspired by OmniDiskSweeper, with search, interpretation, reviewed actions, and recovery for general users and developers.
4. A native local alpha was implemented/tested, without migrating personal caches.
5. DiskWing was selected as the public name. Concept 01, Lift, was approved; preserve its silhouette, Manrope lettering, and palette.
6. Consolidation was approved under MIT, with public consolidated context, private personal evidence, and preservation of the separate ChatGPT project.

Naming research was exploratory and time-specific. No domain purchase, trademark clearance, or release is established by it. A native Icon Composer .icon remains pending; completed .icns and asset catalogs are available.

## Sources of truth

- docs/plans/PLANO-V1-APROVADO.md: sanitized historical cache plan.
- docs/plans/ROADMAP-V0.1.md: evolution and beta criteria.
- docs/context/CURRENT_STATE.md: completed work and next priorities.
- docs/context/MIGRATION-2026-11-09.md: consolidation validation.
- docs/COMPATIBILITY.md: technical identifiers to preserve.
- design/brand/README.md: approved Lift; design/concepts holds historical alternatives.

Historical plans express intent; state and validation docs identify actual completion. Original chats remain in Codex. Public docs are consolidated memory. Personal .local/ archives must never be committed.
