# Cache and volume candidate build 11

Local candidate 1.0.0 build 11 was built from clean source 2380b1a6048e1cb82d280e498f72fdb560b06fca. The immutable ZIP SHA-256 is 79b3658490c84cf08f276a193a4766dc3fb765360cd325a07b5ceb4a3d5d8149. See its [manifest](candidate-1.0.0-build11-local.json) and [exact-archive qualification](cache-volume-build11-qualification.json).

Archive identity, safe extraction, version/domain/helper/resource identity, strict signature, temporary internal installation, generated portable helper workflows and removal passed. This temporary lifecycle was inside its own generated directory, not the maintainer's normal Applications location. Build 8 and build 6/build 3 backups remain preserved; no personal-file/cache operation or real integration activation was performed.

Affected evidence is separate: [real Chrome](GRAPHICAL-CACHES-2026-11-10.md), [new scanner >1M](VOLUME-SCALE-2026-11-10.md), [read-only query replay](volume-search-replay-2026-11-10.json), [native filesystem Trash](volume-trash-filesystems-2026-11-10.json), [PT/EN sample UI](CACHE-VOLUME-UI-2026-11-10.md), and [independent review](CACHE-VOLUME-REVIEW-2026-11-10.md). Application-source equality preserves the observed UI boundary between samples 10 and final 11; the changed Core search path has independent baseline and >1M replay checks.

This is an ad-hoc local candidate, not a notarized public release. Chrome qualification is only 157.0.8103.39/macOS 26/arm64/APFS. Whole-volume scans and global searches remain slow on the measured Debug/SSD fixture; their actual times are retained. Physical cable/power faults, another Mac/macOS 14, human VoiceOver/beta and signed updates remain pending.
