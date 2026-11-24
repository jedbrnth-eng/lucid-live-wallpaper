# AGENTS.md

Lucid: native macOS live-wallpaper app (Swift, SwiftUI/AppKit/AVFoundation, no dependencies, no Xcode project).
4K static and moving wallpapers, a curated Live 4K catalog, playlists and a menu-bar extra. macOS 14+, Apple Silicon.

## Commands (run from the repo root)
```
./build.sh                                        # swiftc build -> build/Lucid.app (ad-hoc signed)
./test.sh [name-filter]                           # unit tests for UI-free sources (offline)
python3 -m unittest tools/test_build_catalog.py   # catalog-builder tests (offline)
plutil -lint build/Lucid.app/Contents/Info.plist  # bundle check, as in CI
./selftest.sh                                     # (network check, not run locally) every source returns only 4K+ items
```
No linter is configured. CI (`.github/workflows/ci.yml`) runs build, tests, bundle check and catalog checks.

## Verification path
- Logic: `./test.sh` must end with `Test summary: N tests, N passed, 0 failed`.
- App end to end, headless, never touching your real library or desktop picture:
  `LUCID_SUPPORT_DIR=<throwaway dir> build/Lucid.app/Contents/MacOS/Lucid -lucidCheck YES`
  It quits by itself; read `<throwaway dir>/check.json` (see `Sources/Lucid/App/DevCheck.swift` for each key).
- Manual runs of a dev build: always set `LUCID_SUPPORT_DIR` to a throwaway folder.

## Layout
- `Sources/Lucid/App/`: entry point, app delegate, menu bar, file import, dev check (`DevCheck.swift`).
- `Sources/Lucid/Core/`: models, paths (`Paths.swift`, `LUCID_SUPPORT_DIR`), preferences, Keychain.
- `Sources/Lucid/Engine/`: per-display wallpaper windows (`Surfaces.swift`), smart pausing, downloader.
- `Sources/Lucid/Media/`: import rules, transcoding, seamless loop maker.
- `Sources/Lucid/Content/`: content providers and the Live 4K catalog. `catalog.json`: bundled list of links + credits.
- `Sources/Lucid/Views/`: SwiftUI screens. Other folders: Audio, DayNight, Hotkeys, Store, Update, Weather.
- `Tests/`: `main.swift` runner, `pure-sources.txt` (sources compiled into tests), fixtures.
- `tools/build_catalog.py`: builds `catalog.json`. `build.sh`: compiler flags and framework list.

## Rules
- New UI-free logic goes in a Foundation/Accelerate-only file listed in `Tests/pure-sources.txt`, test first.
  Why: `./test.sh` compiles only those files, without a window server.
- A new framework import needs `-framework X` in `build.sh`. Why: there is no Xcode project; the link fails otherwise.
- New code goes in the matching `Sources/Lucid/<Area>/` folder; `build.sh` picks up every `.swift` there.
- Never commit wallpaper media. Why: the repo ships only `catalog.json` (links and credits).
- Content sources must show credit and license in the app and list only items >= 3840x2160. Why: 4K is the bar.
- Wallpapers stay audio-free. Why: footage and soundtrack rights differ.
- No analytics or telemetry; the app only contacts the sources listed in the README. Why: privacy promise.
- Wallpaper windows keep `canHide = false`. Why: hiding the app (Cmd-H) would otherwise remove the video.
- Keep the import checks in `Media/ImportPolicy.swift` (extension + magic-byte sniff, `looksLikeMedia`).
  Why: a renamed script must not pass as media.
- Every new source file gets the SPDX header from CONTRIBUTING.md.
- Releases: bumping `VERSION` on main auto-publishes; keep `Info.plist` versions in sync and add
  a `## [x.y.z]` CHANGELOG section first. Why: release notes are cut from that section.

Learned something durable about this repo? Add one line here in your PR.
