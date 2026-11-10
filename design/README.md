# DiskWing artwork

brand/ is the approved Lift identity, selected 2026-11-09. concepts/ preserves four earlier studies, not additional approved identities.

Manrope fonts retain SIL OFL. Original artwork/scripts are MIT. Original machine-specific evidence is preserved privately.

## Optional regeneration

Requires Node.js 20.9+, npm, Python 3.11+, and Apple's iconutil for .icns. Run inside design/:

~~~sh
npm ci
npm run brand
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python concepts/source/build_logos.py
npm run concepts
iconutil -c icns brand/macos/DiskWing.iconset -o brand/macos/DiskWing.icns
~~~

Generators overwrite derived artwork; use a clean checkout and review the diff. Assets/AppIcon.icns is the packaging copy of brand/macos/DiskWing.icns; update both after an approved change.

icon-composer-source contains a specification, not a native .icon document.
