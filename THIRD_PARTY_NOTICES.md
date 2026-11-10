# Third-party notices

## Manrope

Copyright 2018 The Manrope Project Authors (https://github.com/googlefonts/manrope).

Bundled font files in design/brand/source/, its masters/source/ directory, and design/concepts/source/ are licensed under the SIL Open Font License 1.1. Each directory includes Manrope-OFL.txt. Font files retain that license and are not relicensed under MIT. Original DiskWing code, documentation, and logo artwork use the repository MIT license.

## Optional artwork tooling

Default local app builds have no external Swift package dependencies. Optional signed-update builds use Sparkle 2.10.1; its license and bundled third-party notices are preserved in LICENSES/Sparkle.txt and copied into the app. System SQLite and Apple SDKs are supplied by macOS/Xcode and are not vendored. Optional artwork generation uses sharp (Apache-2.0) and fontTools (MIT), installed separately from upstream distributions. Their package license notices apply to those tools and their transitive dependencies; dependencies are not vendored.

See design/README.md for setup. The macOS SDK and Apple tools are supplied by the developer's Xcode installation under their own terms; they are not distributed here.
