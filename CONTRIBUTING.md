# Contributing to Lucid

Thanks for taking a look. Lucid is a small native macOS app written in Swift, with no dependencies.

## Build
```
xcode-select --install     # once
./build.sh                 # creates build/Lucid.app
open build/Lucid.app
```
Requires macOS 14+ on Apple Silicon.

## Test
```
./test.sh                                         # unit tests for the UI-free Swift code (offline)
python3 -m unittest tools/test_build_catalog.py   # offline catalog-builder tests
./selftest.sh                                     # network check: every source returns only 4K+ items
```

New UI-free logic goes in a file that imports only Foundation (or Accelerate) and is listed in `Tests/pure-sources.txt`, with tests in `Tests/`. Write the failing test first.

To try a development build without touching your real library, run it against a throwaway folder:
```
LUCID_SUPPORT_DIR=/tmp/lucid-dev build/Lucid.app/Contents/MacOS/Lucid
```

## Guidelines
- Keep it dependency-free. Sources live in `Sources/Lucid`, grouped by area (see the README's project layout); put new code in the matching folder.
- **Never commit wallpaper media.** The repo only ships `catalog.json`, a list of links and credits.
- Any new content source must show its credit and license in the app, and must only list items that are 3840×2160 or larger.
- Keep the privacy promise: no analytics, no telemetry, and the app only contacts the sources listed in the README.
- Open an issue before a large change so we can agree on the approach.

## Pull requests
Branch from `main`, keep the change focused, make sure `./build.sh` succeeds, and fill in the PR template.

## License of your contribution
Lucid is free software under the [GNU GPL v3.0](LICENSE). By opening a pull request you agree that your contribution is licensed under GPL-3.0 too, and you keep your own copyright on it.

If you want something changed, send it here instead of starting a separate copy. Forks are allowed, but under the GPL a fork has to stay GPL-3.0, keep the original copyright and credit, publish its full source and say what it changed. It also needs its own name and icon, because the Lucid name and icon are not covered by the license.

## File headers
Every source file starts with this header, so credit survives if a single file is copied. Add it to new files:
```
// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper
```
