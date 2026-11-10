# Third-party notices

## Manrope

Copyright 2018 The Manrope Project Authors (https://github.com/googlefonts/manrope).

Bundled font files in design/brand/source/, its masters/source/ directory, and design/concepts/source/ are licensed under the SIL Open Font License 1.1. Each directory includes Manrope-OFL.txt. Font files retain that license and are not relicensed under MIT. Original DiskWing code, documentation, and logo artwork use the repository MIT license.

## Optional artwork tooling

Default local app builds have no external Swift package dependencies. Optional signed-update builds use Sparkle 2.10.1; its license and bundled third-party notices are preserved in LICENSES/Sparkle.txt and copied into the app. System SQLite and Apple SDKs are supplied by macOS/Xcode and are not vendored. Optional artwork generation uses sharp (Apache-2.0) and fontTools (MIT), installed separately from upstream distributions. Their package license notices apply to those tools and their transitive dependencies; dependencies are not vendored.

See design/README.md for setup. The macOS SDK and Apple tools are supplied by the developer's Xcode installation under their own terms; they are not distributed here.

The squarified treemap layout in `Sources/CacheSSDCore/Treemap.swift` is adapted
from DiskPilot's `src/renderer/js/treemap.js`, commit
`534a70a43b364bcbae1fc5c1f897b5770159052f`:
https://github.com/mhkasif/DiskPilot

## DiskPilot — MIT License

Copyright (c) 2025 DiskPilot Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
