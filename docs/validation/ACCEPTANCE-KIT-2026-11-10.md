# Portable acceptance kit — 2026-11-10

Follow-on M6/M7 preparation after [PR #11](https://github.com/Gabriellimmaa/DiskWing/pull/11) merged at 1cdcaabf. [Main CI](https://github.com/Gabriellimmaa/DiskWing/actions/runs/42758794618) passed for that base. Public v1, another-Mac acceptance and the human beta remain unverified.

## Delivery and direct evidence

The packaged helper's explicit acceptance-check command creates a private generated home/store and runs five checks: bundled PT/EN resources, indexed search, interrupted personal-copy recovery, synthetic cache copy/restore/local fallback and shell install/disable in the generated home. It never reads or changes normal cache/settings data, launches native installs or activates a real terminal integration. Simulated Trash keeps the original privately while recovery uses the verified destination.

scripts/qualify_bundle.py used the normal installer to copy the production application into its own temporary internal Applications directory. The installed helper matched the source SHA-256 and ran all five checks with a clean environment, outside the checkout. The temporary application was removed while its report remained available; generated fixtures were then removed and a private report written. The existing installed application remained untouched. See [sanitized result](bundle-acceptance.json).

| Check | Result |
|---|---|
| Swift suite with native installs and filesystem qualification | 89 cases: 86 executed, three explicit skips, zero failures |
| Default isolated Swift suite | 89 cases: 73 executed, sixteen explicit skips, zero failures |
| Packaging/readiness/qualification tests | 20 Python tests passed |
| Packaged internal installation/helper/removal | All three lifecycle checks and all five core checks passed on this development Mac |
| Alias regression | Real macOS temporary directory, legacy digest compatibility and scratch cleanup passed; custom fixture links and existing report files/links remain refused |
| Production bundle | arm64 release, verified local ad-hoc signature, approved icon, helper PT/EN/resources checked |

The native-enabled suite reran all seven disposable tool workflows and four APFS/ExFAT image cases. The three skips are the copy-resource benchmark, the one-million-entry explorer benchmark and subprocess-only crash worker; the parent test still invokes its crash worker. Resource benchmarks were previously qualified and were not repeated for this increment. Default skips additionally include two native queries, seven native workflows and four filesystem-image cases.

## Issue found during real internal installation

The first temporary-install attempts failed rather than reporting success. macOS can represent the same temporary directory as /var or /private/var; SQLite NOFOLLOW also rejects symlinked parent components. VerificationStore now resolves its requested workspace to the physical parent before creating private scratch. SQLite NOFOLLOW remains enabled. The acceptance fixture uses stable generated-home paths and physical database paths; output preflight compares normalized directory paths. New regression tests exercise actual system temporary aliases as well as the configured SSD fixture directory.

Failed generated fixtures were retained for diagnosis, then archived privately on the development SSD after the fix. Raw errors, paths and fixture records were not added to Git. The final successful temporary installation and generated fixtures were removed.

## Evidence boundaries and next work

The [handoff](../acceptance/SECOND_MAC.md) includes a private manual-review template, candidate/helper fingerprint, PT/EN keyboard/VoiceOver checks and actual install/restore/disable/removal observations. The template remains not-run. Reports deliberately collect no hardware ID and cannot attest another physical Mac. Their pending human/release gates remain explicit; no result is imported as participant success or a release-readiness declaration.

This was one development Mac, not another Mac or a full VoiceOver session. SSD absence and Trash are injected, not physical unplug or Finder Trash UI. Ad-hoc signature integrity is not Developer ID, Gatekeeper/notarization or a real signed-update acceptance/rejection check. No certificate, update feed, public binary release, user enrollment or seven-day observation was created. The normal installed app, Chrome, user caches, shell configuration, login/Xcode/notification preferences and personal files were untouched.

CI now runs the generated internal-installation/helper/removal check after the ordinary build. Hosted CI and local results are separate evidence; PR CI status is recorded in the PR and linked issues. A hosted automated pass does not complete the remaining human gates.
