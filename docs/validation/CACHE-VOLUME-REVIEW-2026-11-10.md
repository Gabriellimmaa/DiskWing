# Cache and volume increment: independent review

This record belongs to the [new approved increment](../plans/CACHE-VOLUME-EXPERIENCE-2026-11-10.md), not the build-8 acceptance. All fixtures are generated. No personal cache/file operation or installed build replacement is part of this qualification.

## Reviews completed so far

- Volume Trash implementation `d67bb0e`: reviewed by a different author, with 93 affected tests independently repeated. Scope binds reviewed item/root/volume identity; recovery uses same-volume exclusive rename and never replaces a conflict. Future scope contracts and unsupported filesystem operations are refused.
- Volume engine `5f68cf6` and `11b1e8a`: ownership of every indexed entry, repeated source proofs, durable reset/revalidation/aggregation, cancellation/resource checks, namespace collisions, display-root binding and atomic format/session initialization independently reviewed. The reviewer independently repeated 39 cases from the first hardened revision.
- Storage binding `4bdf0eb` plus `4043c0c`: independently repeated 57 targeted cases. No-follow parent/file opening, UUID/device/inode binding, explicit serialized closure, default temporary spelling and read-only existing-index lookup were examined. The unmarked-volume-table constructor preflight follow-up remains under review.
- Coordinator UI `89e2494`, `461e154` and `9df022b`: approved by a different author after review of physical Trash confirmation, future-record guards before mutation, source/index absence, explicit resume/fresh scan, actual index closure, a discovery gate throughout ejection, stale callback suppression and a global pool of three explorer reads across replaced views. Focused application tests passed, including a blocked-read fixture with an obsolete and replacement coordinator.

The reviewer did not author the coordinator UI/volume engine. The coordinator reviewed the Trash implementation authored by the reviewer. Specialist branches use separate worktrees; only the coordinator integrates shared UI, translations and public evidence.

## Native filesystem boundary

New disposable APFS and HFS+ images passed native macOS Trash, rename/detach/remount, conflict preservation and recovery by exclusive rename. ExFAT passed refusal before invoking Trash, with the original unchanged. Each image was created for its test and only its returned device was renamed/detached; no existing disk was used for fault injection. These cases do not establish physical cable-removal safety or another Mac.

## Gates still open

Graphical cache acceptance requires the real application's normal LaunchServices path, transferred-content reuse, new destination writes, persistent-profile preservation, fallback/reconnection and actual observer/source-release evidence. A touched marker, metadata configuration or successful copy is insufficient. An opaque macOS-managed quarantine-copy contract has separate bounded, versioned verification and must not rewrite unknown security bits or alter legacy digests; final cache review is recorded only after the exact implementation and native results pass.

The first new >1M-entry run was aborted for insufficient performance, and only its fixture was removed. It is not accepted scale evidence. The optimized bound-storage path must pass a fresh complete run.

Final PT/EN native sample UI, exact new-candidate qualification, exact-head CI and final integration remain separate gates. Developer observations and test counts never attest human beta, VoiceOver, macOS 14/another physical Mac, public signing or notarization.
