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
than a source-code pattern. Full default/packaging checks and native sample
observations are in progress; this report will record their actual results.

## Artifact and remaining limits

The correction requires a new build and affected package qualification.
Installed build 11, its ongoing scan, immutable candidate and earlier backups
remain preserved during validation. This is a scoped interface fix; personal
migrations, beta/human acceptance, another physical Mac and notarization remain
separate gates. `publicV1Ready` stays false.
