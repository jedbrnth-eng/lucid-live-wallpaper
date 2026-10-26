# Changelog

All notable changes to Lucid. The format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [1.2.0] - 2026-10-26

### Added
- **Wallpaper Engine sync.** Link your own Wallpaper Engine folders (Workshop `431960`, `myprojects`, a single item or a Steam library). Lucid reads each `project.json`, keeps the list in sync as folders are added, changed or removed, and shows items on a new **Wallpaper Engine** page with preview, title and tags. Videos play natively (WebM and similar are converted to HEVC once). Web wallpapers run in WebKit with Wallpaper Engine's audio and property listener APIs. Scenes and Windows applications are listed honestly as *Unsupported on Mac*, with an opt-in to use a scene's animated preview as a labelled stand-in. Lucid only links to your files and never copies or shares them.
- **Audio-reactive wallpapers** (off by default). Captures the sound your Mac plays with a Core Audio tap (macOS 14.2+, never the microphone), analyses it on device, and drives per-display looks: pulse on bass, glow with volume, spectrum bars. Capture stops whenever no reactive wallpaper is playing.
- **Day & Night wallpapers.** Pick a day and a night wallpaper per display or for all displays. Switches at sunrise and sunset (NOAA equations, location from your time zone or, if you allow it, your Mac's location) or at fixed times, with a short cross-fade. Re-checks after sleep, time zone and clock changes.
- Unit tests for the new logic (`./test.sh`, also run in CI) and a headless development check (`-lucidCheck YES`).

### Changed
- Changing wallpaper now cross-fades the new window over the old one, then releases the old player and its window observer.
- `LUCID_SUPPORT_DIR` lets a development build use a throwaway data folder.
- License changed from MIT to GPL-3.0 for all new work. Versions released before this change stay available under MIT.

## [1.1.1] - 2026-10-17

### Added
- README: a one-click Download button and plain install steps (no Terminal needed).

### Fixed
- Apple Aerials catalog not found on macOS 26/27, where macOS moved it to `~/Library/Application Support/com.apple.wallpaper/aerials`. Lucid now checks both locations.

## [1.1.0] - 2026-10-04

### Added
- Live 4K now has a **Category** menu: Space, Nature & Landscapes, Ocean & Beaches, Sky & Time-lapse and Cities, with clip counts.
- **Sort by** menu: Featured, Name, Shortest or Smallest Download.
- Menu bar: a **Recently Used** submenu to switch back to a recent wallpaper in one click.

### Changed
- The Live 4K source filter is now a compact menu instead of a row of chips.

## [1.0.1] - 2026-10-04

### Fixed
- Live wallpapers keep playing when you hide Lucid (⌘H). Before, hiding the app left only the still desktop picture.

### Changed
- The source code is split from one file into feature folders under `Sources/Lucid`. No behavior change.
- The app reports its real version (1.0.1) in Finder and About.

## [1.0.0] - 2026-10-04
First public release.

### Added
- One-line installer (`install.sh`) and an automated release workflow that publishes `Lucid.zip`.
- Live 4K catalog of about 590 curated moving wallpapers from ESA/Webb, ESA/Hubble, ESO, NASA and Wikimedia Commons, each with credit and license.
- Apple Aerials browser; films already on the Mac apply instantly, others download from Apple on demand.
- NASA 4K Space and Wikimedia 4K Photos stills, and optional Pixabay 4K video (your own key, stored in the Keychain).
- My Library: import your own videos and photos by drag and drop, **Import…**, or by dropping files into the Lucid folder. WebM, MKV and similar formats are converted to HEVC.
- Per-display wallpapers, playlists, favorites, auto-change timer and open at login.
- Battery-friendly playback: pauses when covered, in Low Power Mode, on battery, when locked or the display sleeps.

[Unreleased]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/tag/v1.0.0
