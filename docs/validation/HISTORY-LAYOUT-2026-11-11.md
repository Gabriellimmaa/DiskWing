# History layout correction — 2026-11-11

## Reproduced defect

The maintainer reported that opening History breaks the application layout.
Native observation of installed 1.0.0 build 11 reproduced it: pending recovery
cards and the incomplete-migration summary exceed the available detail height,
pushing the header and sidebar content above the visible window. Switching to
Explore volumes restores the layout; returning to History reproduces it.
No recovery action or personal-data mutation was initiated. An existing volume
scan was left running. Personal paths and screenshots remain private.

## Change and independent review

`HistoryView` now uses one vertical scroll viewport for the header, recovery
cards, growth comparison, empty state, operation records and explanatory footer.
A lazy stack replaces the nested native List, with explicit row separators.
Record order, identities, timestamps, actions, disabled states and selectable
text remain intact. Operation records have accessibility groups containing
their individual controls. No persisted format, operation policy or Lift asset
changes.

The independent `history_review` specialist examined the implementation and
regression test and found no blocking findings. Native row selection had no
binding or operation behavior to preserve. Actual human VoiceOver acceptance
remains separate from this source review.

## Validation

`HistoryLayoutTests` constructs only generated sample homes/stores, twelve
interrupted journals and zero or 150 operation records, in PT/EN. It hosts the
actual complete application view at the 1050 × 690 minimum size and checks both
minimum height and width. It restores the previous in-process language.

Negative control against the original application source failed all four
height assertions: PT minimum 2309 pixels and EN minimum 2249 pixels, both above
690. With the correction the same test passed, including width checks (one test,
zero failures, 4.264 seconds). This verifies the actual layout contract rather
than a source-code pattern. The full default suite passed: 390 discovered cases,
359 executed, 31 explicit opt-in/worker skips, zero failures (98.185 seconds). All 51 packaging tests passed.
No extra native-tool, physical-disk or scale run was needed for this view-only fix.

A separate generated samples bundle from the same runtime source was observed
at minimum 1050 × 690 content size in PT/EN, then at the default size. Empty
history, twelve pending recoveries, two legacy interrupted-migration summaries,
long generated paths and 150 operation records were checked. The title, sidebar
and banners stay inside the window. One scroll area reaches the unique last
record and explanatory footer in each language. Repeated History → Explore →
History navigation restores the page normally. The generated sample preference
was changed to English; the normal application's language was unchanged.

[PR #25](https://github.com/Gabriellimmaa/DiskWing/pull/25) merged at
`eebbd349f919d41ad1a385d655c1b69259ccc726`. Its exact head `e06cbcd`
passed [macOS 15/26 CI](https://github.com/Gabriellimmaa/DiskWing/actions/runs/42953370768),
including the optional updater compilation. The independent reviewer confirmed
that same implementation commit from a separate worktree.
[Post-merge main CI](https://github.com/Gabriellimmaa/DiskWing/actions/runs/42954223690)
also passed on macOS 15/26, including optional updater compilation. The final
documentation-only follow-up leaves this tested runtime source unchanged.

## Artifact and remaining limits

Local **1.0.0 build 12**, clean source `e06cbcd`, has full archive SHA-256
`c366649fed33de49a34c9c32bbd870f290e1a851b0739da6f53ea13195fa7343`.
Its [manifest](candidate-1.0.0-build12-local.json) and
[exact-archive qualification](history-build12-qualification.json) verify archive
identity, safe extraction, signature, disposable internal installation, packaged
helper/resources, generated journeys and temporary removal. It is ad-hoc signed;
no public binary/tag/update feed, Developer ID or notarization is implied.

After the existing scan was no longer active (its UI offered a pending resume),
the normal app was quit gracefully. The exact verified archive was installed with
the official internal installer, preserving build 11 in a new backup. Every
installed regular file matches the extracted archive; every build 11 backup byte
matches the preflight app; build 8/6/3 backups also match preflight. Strict deep
signatures passed for the installed app and all four backups. All 15 tracked
settings/history/operation/integration files remained byte-identical, with no new
records. Index bytes were not fingerprinted, so this is not a claim about scan
completion or the contents of a scan index. Raw paths, hashes and installation
logs stay private.

The normal installed app was reopened and History observed with the maintainer's
existing records: its title, sidebar, recovery cards and single scroll viewport
are visible normally. No recovery, migration, cleanup, scan or real integration
was initiated by the assistant. The application remains open on History.

This is developer verification of the reported defect, not the maintainer's
subsequent acceptance. Human PT/EN keyboard/VoiceOver, another physical Mac and
production/beta gates remain pending. `publicV1Ready` stays false.
