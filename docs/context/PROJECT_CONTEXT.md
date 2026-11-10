# Project context

## Intent and approved decisions

DiskWing helps Mac users understand and recover storage, with developer-cache integrations as an initial specialization. The founding requirement is to use the Mac and Chrome without the external SSD. Moving every system cache is outside the supported approach.

On 2026-11-10 the maintainer clarified the primary promise: preserve eligible existing cache data on SSD and direct future writes there, plus broad explicit manual Trash through the explorer, including application caches. The [expanded contract](../plans/SCOPE-EXPANSION-2026-11-10.md) separates manual deletion from generic relocation, requires honest internal-data coverage and reopens affected acceptance. Compatibility remains per application; a catalog entry or verified copy alone does not establish working routing.

The approved plan uses native per-tool configuration and chooses a destination when a command starts. Existing processes keep their environment. No whole-system cache-directory symlinks or automatic merging of generations. Chrome data and caches, SDKs, emulators, projects, and service executables remain local.

Every data-changing action has a review. Verify copies before releasing eligible caches; record recovery information. Bun and uv sources remain local because installed environments may reference them by links. Do not silently relax this protection.

## Product evolution

1. Research and read-only inventory identified selective native cache routing as the compatible direction.
2. Cache plan v1 was approved and retained as the historical baseline.
3. The product expanded to a disk-usage explorer inspired by OmniDiskSweeper, with search, interpretation, reviewed actions, and recovery for general users and developers.
4. A native local alpha was implemented/tested, without migrating personal caches.
5. DiskWing was selected as the public name. Concept 01, Lift, was approved; preserve its silhouette, Manrope lettering, and palette.
6. Consolidation was approved under MIT, with public consolidated context, private personal evidence, and preservation of the separate ChatGPT project.
7. The alpha-to-v1 roadmap was approved with both explorer/cache flows, Apple Silicon, PT/EN, recoverable operations, optional growth tracking, signed consented updates and a real ten-person/seven-day beta. Implementation and validation evidence remain separate.
8. The approved autonomous delivery cycle integrated PR12/19/20, qualified immutable local 1.0.0 build 6, independently reviewed the implementation and checkpoint-test follow-ups, and passed macOS 15/26 exact-head/main CI. Production distribution and human/physical gates remain pending.
9. The maintainer explicitly requested installation and opening of build 6 for interface validation. The exact candidate was installed on internal storage with the previous app preserved, and its normal window was observed. This authorizes that installation/launch, not personal cache changes; maintainer feedback has not yet been received.

Naming research was exploratory and time-specific. No domain purchase, trademark clearance, or release is established by it. A native Icon Composer .icon remains pending; completed .icns and asset catalogs are available.

## Sources of truth

- docs/plans/PLANO-V1-APROVADO.md: sanitized historical cache plan.
- docs/plans/ROADMAP-V0.1.md: evolution and beta criteria.
- docs/ROADMAP.md and docs/TRACEABILITY.json: live requirements, issues/milestones and remaining release gates.
- docs/ARCHITECTURE.md, docs/TESTING.md and docs/validation/: implementation contracts and evidence.
- docs/context/CURRENT_STATE.md: completed work and next priorities.
- docs/context/SESSION-2026-11-10.md: consolidated autonomous delivery, verification, installation and resumption history.
- docs/validation/LOCAL-INSTALLATION-2026-11-10.md: actual maintainer installation/launch, preserved prior version and pending interface feedback.
- docs/context/MIGRATION-2026-11-09.md: consolidation validation.
- docs/COMPATIBILITY.md: technical identifiers to preserve.
- design/brand/README.md: approved Lift; design/concepts holds historical alternatives.

Historical plans express intent; state and validation docs identify actual completion. Original chats remain in Codex. Public docs are consolidated memory. Personal .local/ archives must never be committed.
