# Graphical cache qualification

Scope: [the reviewed cache/volume increment](../plans/CACHE-VOLUME-EXPERIENCE-2026-11-10.md). This qualification uses generated application data; it does not migrate or inspect personal profiles. The installed build 8 and its backups remain preserved.

| Application / scope | Result | Boundary |
| --- | --- | --- |
| Google Chrome 157.0.8103.39, derived `Library/Caches/Google/Chrome` | Qualified locally | Apple Silicon, macOS 26.5.2 (25F84), APFS; normal LaunchServices opening, Google Developer ID identity, exact browser version |
| Chrome `GPUPersistentCache`, `GraphiteDawnCache`, `component_crx_cache`, `extensions_crx_cache` in Application Support | Local exceptions, separately measured | No qualified fallback/reconciliation; profile data remains local |
| Cursor HTTP cache | Local exception | Transfer and absent-SSD behavior not qualified; projects/extensions/accounts preserved |
| Xcode Derived Data | Local exception | Native custom location exists; automatic absent-SSD fallback not qualified; SDKs/simulators/projects/distribution archives preserved |
| Safari | Protected local exception; size unconfirmed | Historical path is not a complete effective-cache inventory; no sandbox bypass or qualified safe redirection |

The production Chrome gate is exact application version, Google-signed distribution, Apple Silicon, macOS major 26 and APFS destination. Other combinations remain explicit exceptions. macOS 15 CI unit tests do not extend graphical qualification to that OS. The catalog does not imply that every cache belonging to Chrome has moved.

## Real application proof

Source `46e7148c1bdd2bf77159561ca5aabd11a436e664` passed the headed native workflow in 50.672 seconds with one test, zero failures. The [sanitized machine record](chrome-cache-qualification-2026-11-10.json) contains hashes/counts, no personal paths, PIDs, local volume UUIDs or opaque raw metadata.

The harness opens the installed Google Chrome bundle through `NSWorkspace.OpenConfiguration` with a new instance, generated HOME/profile and ordinary derived cache location. It checks `Browser.getVersion`. No `--disk-cache-dir`, sandbox bypass or personal browser instance is used. The generated profile is a descendant of the normal Application Support namespace and exercises Chrome's normal Library/Caches derivation rather than a special cache argument.

After transfer, a new Chrome process reuses response A without a new HTTP request; response B is written and reused across restart. The engine's default observer captures live regular cache descriptors with kernel FREAD/FWRITE, verified file/root identity, process birth and exact signed application membership. It uses kernel executable paths rather than mutable process names. Only after that evidence and source stability does the engine actually remove the held original. A marker, empty directory or enabled integration alone cannot pass.

Profile bytes remain unchanged during transfer and a generated cookie survives. Starting without the simulated SSD continues with network/memory and no invented local persistent-cache directory. Reconnection preserves cached responses without merging databases; reviewed restoration returns a verified local cache and retains recovery data.

## Opaque OS-managed metadata

Standard macOS copy APIs can normalize `com.apple.quarantine`. The Chrome-only, versioned copy policy leaves that OS result intact. Content, ACLs, modes, timestamps and all other copy-relevant attributes remain exact; source stability uses the unchanged historical digest including quarantine. Quarantine presence/bytes must match a private same-type/same-volume reference created by the standard metadata API. Bounded metadata-only retries apply solely to staging/reference, never originals or an active published cache. API errors, missing attributes, unexpected differences or failure to converge preserve the source.

Durable private proof retains bounded opaque values and hashes; public evidence contains only hashes/counts. Unknown policy versions are not silently accepted. This demonstrates the tested standard-API outcome, not an interpretation of private security bits. Legacy migration digest bytes remain unchanged.

## Limits

The generated home and SSD directories share a filesystem; availability is simulated by moving only the generated destination. This does not prove physical cable removal, another Mac, macOS 14/15 graphical operation, all future Chrome releases, user VoiceOver/beta acceptance or notarization. Existing processes may need reopening to switch destinations. Runtime verification observes current access during its window; it does not reconstruct reads that already ended.

## Source references and integrated repeat

The path equivalence was checked against Chromium's [GetUserCacheDirectory](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/common/chrome_paths_mac.mm) (consulted blob6829c9cb92c228dd19d44c9f739bf4595720cc2d) and [Foundation directory roots](https://chromium.googlesource.com/chromium/src.git/+/refs/heads/main/base/base_paths_mac.mm) (consulted blob ef6a07a7a18e34331e5a3c0b318d294c2e9390bd). These consulted main-branch sources are not misrepresented as a checked Chrome157 source tag. The generated paths were also verified in the running application.

Apple's historical [CF home-directory implementation](https://github.com/apple-oss-distributions/CF/blob/main/CFPlatform.c) explains CFFIXED_USER_HOME; that historical mechanism is not a public compatibility promise. Actual isolation was exercised on the stated OS. Opening uses the documented [NSWorkspace configuration API](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration). The opaque-copy policy follows the standard [copyfile implementation](https://github.com/apple-oss-distributions/copyfile/blob/main/copyfile.c) and [manual](https://github.com/apple-oss-distributions/copyfile/blob/main/copyfile.3), without private flags or raw quarantine repair.

After integration and the coordinator's generic path-safety fix, the real Chrome test was independently repeated in the coordinator checkout: one test, zero failures,35.492s. The installed distribution, normal launch, source release and absence/reconnection assertions remained unchanged. The compile-only expression refactor for older Swift is behavior-equivalent and independently reviewed; macOS15 is still not a graphical qualification platform.
