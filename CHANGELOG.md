# Changelog

All notable changes to Lucid. The format follows [Keep a Changelog](https://keepachangelog.com/).

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
