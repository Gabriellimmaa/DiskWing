# Maintainer installation of build 11

On 2026-11-10 the maintainer explicitly authorized installing and opening
DiskWing 1.0.0 build 11 for testing, preserving build 8 and without migrating
personal caches.

The exact candidate ZIP was checked against SHA-256
`79b3658490c84cf08f276a193a4766dc3fb765360cd325a07b5ceb4a3d5d8149`.
Safe archive paths, normal application identifier, version/build, helper hash
and strict deep signature were verified before installation. The existing
build 8 was quit gracefully through its application menu.

The official internal-disk installer replaced the current application through
a staged bundle and preserved build 8 under a new backup name. Every regular
application-file byte was compared with the extracted candidate. Every regular
file in the build 8 backup and preexisting build 6/build 3 backups matched its
preflight hash; strict deep signatures passed for all four bundles.

The normal installed application process and its **Explore volumes** window
were observed after launch. No scan, transfer, cleanup or recovery action was
initiated. All 15 tracked settings, operation/configuration records and terminal
integration files retained their preflight fingerprints, with no new tracked
records. Exact local paths, backup names, hashes and installer output remain
in ignored private installation records.

Installation and launch are complete; maintainer feedback is pending. Opening
the application is not personal cache migration, human acceptance, notarization
or public release. The [candidate qualification](CACHE-VOLUME-BUILD11-2026-11-10.md)
and its platform/performance limitations remain unchanged. Preserve the installed
build 11 and all earlier backups during review; actual personal operations still
require review of the real selection.
