# New volume engine: actual >1M-entry qualification

The original generated filesystem test completed normally on source `3e37ce9dd329f43030905ee686b68fcbe5fb9e95`: **one test, zero failures, zero skips**, exit0. Its [sanitized record](volume-scale-2026-11-10.json) preserves the original result and duration. Earlier interrupted performance attempts are not counted as passes.

- 1,002,003 indexed entries and 1,001,001 files, complete rather than partial.
- Paused at 600,001 examined entries; added 35 bytes inside an already completed directory; resumed/revalidated successfully.
- Logical 52 bytes, allocated 8,192 bytes; the sparse/empty generated workload is not a physical storage-saving measurement.
- Rare global and post-pause-added searches each matched once. The last page contained 1 of 1,000 children, with no next page.
- Peak RSS 94,814,208 bytes (90.42 MiB), below 512 MiB. Independently captured kernel lifetime peak physical footprint 96,879,360 bytes (92.39 MiB) is recorded separately and is not relabeled peak RSS.
- Index bytes 1,477,466,928 on the bound APFS SSD factory. Internal 512 MiB limits are not silently bypassed; this is the explicitly chosen external-index policy.

## Time and limitations

The test was Debug, with the generated source tree and index on the same external APFS SSD. Total test time was 4,193.035s (69min53s), including 95.685s cleanup. Fixture creation took 84.098s; scan/resume/queries took 4,013.252s. An auxiliary consistent SQLite backup took 44.993s during final queries, so this is not an isolated latency benchmark. No personal files, physical cable faults, release UI speed or another Mac are attested.

The scan and aggregation completed before a concrete query-plan bottleneck: default global LIKE searches with minimum 0 used a size index and performed random table lookups. The old query eventually passed the original assertions; its duration is never overwritten by a faster later replay. Source `b706651` changes only the global-search table plan, preserving predicates, escaping, sorting, tie-breaks and pagination. It has separate baseline/Unicode/escape/session/metric/page tests and independent review. A read-only replay on the consistent retained generated index records its own time/plans/results.

The original million-file fixture was removed after the successful test. A marker/ownership/hash-bound consistent SQLite copy remains private solely for query qualification; it is never authorized for filesystem actions. Only hashes/counts and sanitized metrics are public. No index is silently migrated from the legacy location.
