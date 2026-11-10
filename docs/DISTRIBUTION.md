# Installation, signing, updates and removal

Local builds use an ad-hoc signature and have no updater dependency or network update checks. Run python3 build.py and python3 scripts/install_local.py dist/DiskWing.app. The installer verifies bundle identity/signature, requires internal storage and preserves an existing application as a recoverable hidden backup. Quit the previous app before replacing it. Opening the app does not activate terminal integration, tracking, notifications or login registration.

Public release candidates require a Developer ID Application identity, an existing notarytool Keychain profile, an HTTPS appcast and a public Ed25519 key. Private keys, Apple credentials and certificates never enter Git.

~~~sh
python3 build.py --profile production --with-updater \
  --sign-identity 'Developer ID Application: YOUR ORGANIZATION (TEAMID)' \
  --feed-url 'https://your-release-host.example/appcast.xml' \
  --public-ed-key 'YOUR_BASE64_PUBLIC_ED25519_KEY' \
  --notary-profile 'YOUR_EXISTING_KEYCHAIN_PROFILE' \
  --version 1.0.0 --build-number 4
~~~

The builder pins Sparkle 2.10.1, preserves framework links, signs nested code from inside out, verifies hardened signatures, submits to Apple, checks Accepted, staples and assesses before replacing the previous output. Signing/notarization has not been exercised without the required Developer ID certificate. A successful optional Swift build proves API/link compatibility only.

Use Sparkle's generate_keys and generate_appcast from the resolved artifact. Keep the Ed25519 private key in the signing Keychain. Sign every update archive, use monotonically increasing build numbers, serve via HTTPS and verify the downloaded appcast/archive on a second Mac. Test invalid signatures and rollback recovery. Host/feed deployment is a separate reviewed action; this repository does not create a public endpoint or release.

Update checks are optional, off by default and initiated by a manual check or explicit automatic-check consent. Automatic download/install and system profiling are disabled. The standard Sparkle UI requires installation consent. Operations/recovery and updates exclude each other in the app; cross-process operation leases are checked before update/relaunch. Quit requests during an active scan/copy are deferred by cancellation refusal. A CLI operation or power failure still requires the documented recovery journal review.

## Rehearsal before another-Mac acceptance

Use [the portable acceptance kit](acceptance/SECOND_MAC.md) and scripts/qualify_bundle.py to rehearse an internal installation in its own generated directory, run the installed helper and remove only that temporary app. It leaves the normal installed application and support records untouched. Ad-hoc signature integrity, simulated local fallback and generated-home shell disable are automated evidence; actual second-Mac GUI/Gatekeeper/new-terminal/removal and signed-update checks still need a reviewer.

## Removal

1. In Settings, review Disable terminal integration; open a new terminal and verify native local defaults. Existing terminals/processes retain their environment until reopened.
2. Disable Open at login, automatic checks, tracking and notifications if enabled.
3. Restore a cache only if needed and enough internal space exists. Existing populated local caches are never overwritten; choose local mode to preserve them.
4. Quit DiskWing and move the application to Finder Trash. Keep local CacheSSD support records and external MacCaches/CacheSSD copies until all copies, settings backups and personal files are reviewed.
5. Do not automate removal of support records, external copies, shells, projects or browser data. Finder Trash remains under user control.

Legacy CacheSSD identifiers/paths remain intentional. An old CacheSSD.app can coexist temporarily; verify which bundle is running and re-review terminal integration if the helper location changes.

References: [Sparkle setup](https://sparkle-project.org/documentation/), [programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Immutable candidates and promotion

The default --profile dev allows a dirty checkout and ad-hoc signing. --profile candidate requires a clean commit and can prepare a local unsigned-distribution candidate with --version 1.0.0 --build-number 4. It is deliberately ineligible for public readiness. --profile production additionally requires release configuration, Developer ID, notarization and the configured signed updater. Production verifies accepted notarization, staple and Gatekeeper before exposing output. --acceptance-bundle is dev-only and cannot enable updates.

Every build archives the entire signed application, including UI/resources and framework links, with ditto. dist/ retains a content-addressed ZIP and schema-1 manifest with commit, version, build number, full ZIP SHA-256/size, helper hash and verification flags. Never replace a candidate ZIP or reuse a different package's observations. An ad-hoc signature proves local integrity only.

Default public hosting is GitHub Releases plus separate HTTPS GitHub Pages appcasts. Once credentials exist, create/sign one final artifact and circulate it as a prerelease. Qualify that same ZIP, then promote release metadata without rebuilding or moving published tags. New functional bytes reopen affected acceptance. Publish the Ed25519-signed appcast only after downloading/verifying its archive and exercising valid/tampered updates, consent and operation blocking in a separate test channel. No empty production feed or public binary is deployed by local preparation.

See beta/PROTOCOL.md for schema-2 candidate-bound private evidence and the complete external dependency packet. The legacy installer/helper lifecycle report identifies only the helper and is insufficient to bind GUI/resources. Use qualify_candidate.py to verify and extract the exact ZIP, compare its independently reviewed candidate, and record the complete candidate in the result.
