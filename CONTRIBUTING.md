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
python3 -m unittest tools/test_build_catalog.py   # offline catalog-builder tests
./selftest.sh                                     # network check: every source returns only 4K+ items
```

## Guidelines
- Keep it dependency-free. Sources live in `Sources/Lucid`, grouped by area (see the README's project layout); put new code in the matching folder.
- **Never commit wallpaper media.** The repo only ships `catalog.json`, a list of links and credits.
- Any new content source must show its credit and license in the app, and must only list items that are 3840×2160 or larger.
- Keep the privacy promise: no analytics, no telemetry, and the app only contacts the sources listed in the README.
- Open an issue before a large change so we can agree on the approach.

## Pull requests
Branch from `main`, keep the change focused, make sure `./build.sh` succeeds, and fill in the PR template.
