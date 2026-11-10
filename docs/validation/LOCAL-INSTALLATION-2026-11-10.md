# Maintainer installation and interface review

On 2026-11-10 the maintainer explicitly requested installation and opening of the qualified local DiskWing version to validate its interface. This is a real installation of the normal application, separate from the earlier disposable sample/helper qualification.

## Exact candidate

| Field | Value |
|---|---|
| Version / build | 1.0.0 / 6 |
| Runtime source commit | 4db260076b602c309c3493f9b06548b0751f7356 |
| Complete ZIP SHA-256 | 854bae67b4976d74cb95c568f09645aeb8ada10b25f7d5b78b7b4f4c07fc6c60 |
| Helper SHA-256 | da303799ef83fd8f99831517bec167a83cc407680db4e596dacf58bfe999cba5 |
| Application identifier | com.cachessd.app |
| Packaging profile | candidate; local ad-hoc signature |
| Prior app preserved | 0.2.0-dev / build 3 |
| Public v1 readiness | false |

The manifest and generated-data qualification remain in [candidate-1.0.0-local.json](candidate-1.0.0-local.json). No candidate rebuild, re-signing or version change was needed for this installation.

## Performed and observed

1. Recalculated the immutable archive SHA-256 against the reviewed candidate identity.
2. Extracted that exact archive into a private directory on external development storage; checked bundle identifier, version/build and helper SHA-256.
3. Used scripts/install_local.py to install in the current user's Applications directory. The installer verified internal storage, application identity and the code signature, copied through a staged bundle, and preserved the prior application under its own backup name.
4. Rechecked the installed bundle version/build and strict deep code signature. A later independent read-only documentation check reconfirmed both app identities/signatures and byte-for-byte agreement between all twelve archived application files and their installed counterparts. Archive resource-metadata entries are separate from those application files.
5. Opened the installed app through macOS Launch Services. NSWorkspace and CoreGraphics then reported the normal application process at the installed path, active and not hidden, with an on-screen window titled DiskWing measuring 1240 × 785. This is an observation after launch, not a claim about its foreground state in future sessions.

Exact local paths, the backup name, installer output and timestamps stay in ignored private installation records. These details are intentionally absent from public source documentation.

## Acceptance and boundaries

Installation and launch are complete. **The maintainer's interface feedback is pending.** Neither the request to test nor the observed window establishes visual approval, successful human journeys, PT/EN keyboard/VoiceOver acceptance, another physical Mac, macOS 14 qualification or beta participation.

The assistant did not initiate a personal cache migration, file move/Trash operation, shell integration, Xcode preference change, login item, notification activation or SSD ejection. Chrome was not operated. Opening the app may read its normal local configuration; no personal storage-saving claim is made.

The installed candidate has an ad-hoc local signature. Developer ID/notarization, enabled signed update delivery and production acceptance remain pending; no public release, tag or update feed was published by this installation.

## Continue from here

Preserve the installed build 6 and the prior-version backup during interface review. Collect the maintainer's observations and record the screen, language/window context, expected behavior and actual result before implementing corrections. Keep any personal paths or screenshots private or sanitize them before publication.

Documentation-only follow-ups preserve the immutable package. A functional change requires a new candidate identity and affected qualification; a production rebuild must use a larger build number and meet the existing signing/update, physical-Mac, accessibility and ten-person/seven-day gates. See [current state](../context/CURRENT_STATE.md), [the consolidated session](../context/SESSION-2026-11-10.md) and [the autonomous agreement](../AUTONOMOUS-DELIVERY.md).
