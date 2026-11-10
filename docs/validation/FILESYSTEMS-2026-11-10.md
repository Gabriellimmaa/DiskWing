# Filesystem and copy qualification — 2026-11-10

Follow-on M1/M3 development increment after [PR #10](https://github.com/Gabriellimmaa/DiskWing/pull/10) merged at 6e95e499. [Main CI](https://github.com/Gabriellimmaa/DiskWing/actions/runs/42755083061) passed for that base. This document records local qualification for the subsequent increment; it does not establish v1 release readiness.

## Behavior

Tree verification now stores one entry at a time in a private disposable SQLite workspace and streams sorted JSON into SHA-256. A Swift collation preserves historical Unicode ordering. Compatibility tests compare the exact historical root-metadata-plus-JSON bytes, including empty directories and escaped paths. Existing settings, journals and digest values retain their formats.

File copying reads/writes chunks up to 1 MiB, supports cancellation during one large file, handles short writes, detects source growth/mtime changes, copies metadata and synchronizes the output. Directory metadata is applied deepest-first. No existing output is overwritten. Quota/cancellation/verification errors preserve the source and leave recoverable staging under the existing operation journal.

Destinations must advertise extended-security support before copy publication or source release. Unsupported destinations are refused with PT/EN guidance. The cache screen displays this limitation for the selected volume.

## Direct local checks

| Check | Result |
|---|---|
| Full opt-in Swift suite | 82 cases: 80 executed, two explicit skips; zero failures |
| Default suite | 82 cases: 66 executed, sixteen explicit skips; zero failures |
| Packaging/installer/readiness | 15 Python tests; zero failures |
| Legacy digest and streaming-copy tests | Eight isolated cases passed: Unicode/empty digest compatibility, single-file cancellation, source growth, no overwrite, directory metadata, quotas/cleanup and recursion guards |
| APFS cross-volume copy/recovery | Distinct filesystem devices; bytes, ACLs, resource forks/custom xattrs, modes and nanosecond mtime match; interrupted post-Trash operation recovered from verified external copy while preserving the private original |
| APFS low space | Filled only a generated image; migration refused before journal/cache destination creation; original unchanged |
| APFS read-only | Read-only image rejected writes; original unchanged |
| ExFAT | Actual mounted image reports no extended-security support; refused before publication, Trash or operation journal; destination empty and original unchanged |
| Copy resource benchmark | 20,001 files, 201 directories, 67,348,864 logical bytes; verified destination and unchanged source |
| Production bundle | arm64 release, local ad-hoc signature, Lift icon equality, helper/resource checks |
| Optional updater | Separate Sparkle 2.10.1 API/link build passed; no runtime update performed |

The copy benchmark measured 44.19 seconds for measurement, original digest, copy and both final digests; maximum resident size in the XCTest process was 140,115,968 bytes (133.6 MiB), below the 256 MiB test bound. Fixture creation/teardown are outside this measured interval. One file is a 64 MiB sparse source; this is a many-file/resource check on one development SSD, not a multi-gigabyte throughput guarantee. The standalone run also passed. See [sanitized copy metrics](copy-scale.json).

The full-suite skips are the one-million-entry explorer benchmark (passed separately in the earlier delivery) and subprocess-only crash worker (invoked by its parent test). Default skips additionally include two installed-tool queries, seven actual native workflows, four filesystem images and the copy benchmark. The [seven native workflows](native-workflows-copy-qualification.json) passed again after these changes, including local routing under injected SSD absence. Offline and source-retention limits remain as recorded in the original qualification.

The [four filesystem reports](filesystems.json) use blank images created under the private fixture root. Only their exact returned devices were detached; no physical disk was filled, formatted or ejected. Initial ExFAT fixture creation failed because of its image layout/label configuration; the fixture was corrected to an explicit MBR layout and short label before successful tests. That initial setup failure was not counted as application-refusal evidence.

## Reproduction and remaining gates

See [testing commands](../TESTING.md). The ordinary CI runs isolated tests/build/package checks. Filesystem images and the copy benchmark require explicit opt-in or the separate manual run_filesystems CI job. This increment adds that CI job; a local pass is not a hosted-job pass.

No personal caches, Chrome profiles, terminal integration, Xcode preferences, login items, notifications, installed application or update consent were changed in this increment. No release, feed, certificate or credentials were created. The installed app remains the PR #10 build until deliberately updated.

Still pending: another Mac and device/filesystem matrix, multi-gigabyte sequential throughput, physical power/cable faults, complete hands-on VoiceOver/PT/EN acceptance, Developer ID/notarization and real signed-update acceptance/rejection, then five general users plus five developers and actual seven-day observations. Original implementation evidence remains [separate](IMPLEMENTATION-2026-11-10.md).
