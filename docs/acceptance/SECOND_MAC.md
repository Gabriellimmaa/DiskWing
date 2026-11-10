# Portable acceptance and another-Mac handoff

This kit prepares M6/M7 acceptance without changing a person's caches or settings. An automated pass is not proof of another Mac, VoiceOver use, notarization, physical unplug safety or beta success. Keep those gates open until a reviewer records direct evidence.

## Packaged core check (no Swift toolchain or Python required)

Use the helper inside the candidate DiskWing.app, with an existing writable fixture directory and a new report filename:

~~~sh
/path/to/DiskWing.app/Contents/MacOS/CacheSSDHelper acceptance-check \
  --workspace /your/existing/fixture-directory \
  --output /your/existing/report-directory/new-core-report.json
~~~

Allow at least 1 GiB free on a filesystem supporting extended security. The command creates a private .DiskWing-acceptance-* child and only changes its generated home, store, sample files and synthetic cache. It checks bundled PT/EN resources, indexed search, interrupted personal-copy recovery, cache copy/restore/local fallback and shell integration install/disable in the generated home. Native packages are not installed. SSD availability and Trash are injected; there is no mount, network, notification, login, Xcode or real shell activation. Personal copies are recovered from the verified destination while keeping the simulated Trash original.

The report contains the helper SHA-256, macOS/architecture, suite version, timestamps, fixed check statuses and pending manual gates. It omits user names, paths, device IDs, tool inventories, signing identities and raw errors. Existing reports and symbolic links are refused. Exit zero means this automated suite passed and its fixtures were removed. On failure, the failed check and unrun checks are explicit; the private child remains for review. No broad scratch cleanup is performed.

## Temporary internal installation/removal check

From a reviewed checkout, use Python 3 and the candidate bundle. Choose an existing fixture workspace on internal storage:

~~~sh
python3 scripts/qualify_bundle.py /path/to/DiskWing.app \
  --workspace /your/internal/fixture-directory \
  --output /your/existing/report-directory/new-bundle-report.json
~~~

This calls the normal installer into its own private temporary Applications directory, checks the installed helper against the source SHA-256, runs it with a clean environment and a working directory outside the checkout, and removes only that temporary application. It verifies that the core report remains available after app removal, then removes its own generated root and writes a private report. The existing installed DiskWing.app is untouched. Failures retain the generated root and name the failed stage without exposing raw command output. The normal installer rejects an external installation destination before copying.

The helper and resources are executed from the internal copied bundle. The source SSD is not physically detached. The installer checks an ad-hoc signature's integrity; this does not establish Developer ID, Gatekeeper acceptance, notarization or runtime update behavior. Tests of the actual application's preferences, login registration, Finder Trash UI and removal remain manual.

The default CI runs this temporary-installation suite. Filesystem images and large-tree benchmarks remain separate explicit opt-ins.

## Human acceptance on another Mac

Copy REVIEW_TEMPLATE.json to private .local/acceptance/ and record an anonymous machine alias, candidate version/build/helper SHA-256, reviewer alias and timezone-qualified date. The reviewer must attest that this is another physical Mac; automated reports deliberately collect no hardware identifier and cannot establish that fact. Do not publish the private record or raw observations.

Use generated sample folders/projects. Record both PT/EN results for explorer, cache review, partial/unavailable states, keyboard focus/cancellation, VoiceOver reading order/labels, source/destination facts and history/recovery. Follow [interface acceptance](../ACCESSIBILITY.md). Record install, restore, disable, restart/new-terminal behavior and reviewed removal under [distribution](../DISTRIBUTION.md). An automated fixture shell file is not an active personal shell session.

Mark each check passed/failed/blocked/not-run with an evidence reference; do not change not-run to passed because the helper passed. Keep critical findings as issues. Actual signing/update checks need their own credentials and acceptance evidence. Physical cable/power tests require a separate disposable device, never the development SSD. Beta participation still requires the [ten-person/seven-day protocol](../beta/PROTOCOL.md); this kit enrolls nobody and sets no release-readiness declaration.
