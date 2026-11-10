# Contributing to DiskWing

Start with AGENTS.md and docs/context/PROJECT_CONTEXT.md. Discuss large new operations or changes to recovery behavior in an issue before implementing them.

Use Swift 6 with a macOS SDK, Python 3 for packaging, and the commands in README.md. Run isolated Swift tests and packaging tests for relevant changes; run native checks only on a prepared Mac using isolated samples.

Keep changes focused. Describe the user-visible result, verification, and what remains untested. For operation changes, include source preservation, interruption, missing-SSD, and recovery scenarios. Never use personal caches as disposable fixtures.

The interface currently uses Portuguese. Keep contributor documentation in English and update README.pt-BR.md when usage changes. Preserve the approved Lift identity and existing configuration compatibility.

Do not commit build outputs, private .local archives, personal reports, secrets, or downloaded dependencies. Contributions are provided under the repository MIT license; third-party materials must retain applicable licenses and attribution.
