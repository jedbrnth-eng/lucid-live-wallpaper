# Changelog

All notable changes to Lucid. The format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [1.3.0] - 2026-10-26

### Added
- **Smart pausing.** Besides locking, display sleep, Low Power Mode and battery, Lucid now pauses below a battery level you pick (default 20%, on battery only), when your Mac is under serious heat, and optionally while the whole Mac's CPU use stays high for 30 seconds. Settings and the menu bar show a status line ("Playing", "Paused: full-screen app"). After a long pause (default 5 minutes) the video players are closed to free memory and reopen when playback resumes.
- **Your own files, your way.** Choose to copy imported files into Lucid's library (default) or use them where they are. Per wallpaper: fill, fit or stretch, which part stays visible when cropping, and playback speed.
- **Playlists on a schedule.** Play a playlist on all displays or on one display each, change on a timer or at times of day (`07:00, 18:30`), shuffle without repeats, cross-fades for photos too, and resume where it was after a restart.
- **Global shortcuts** (off by default) for pause/resume, next and previous, using macOS hot keys (no Accessibility permission). Conflicts are shown.
- **Dawn and dusk wallpapers** for Day & Night pairs: civil dawn until the sun is 6° up, and golden hour until last light.
- **Weather wallpapers** (off by default): a different wallpaper when it rains, snows, is clear or cloudy, using Open-Meteo with an approximate location.
- **Update check** (off by default): once a day, shows a link when a newer release is on GitHub. Nothing is installed automatically.
- Draft Homebrew cask in `packaging/` (not published) and `docs/lock-screen-feasibility.md` (why Lucid can't animate the Lock Screen, and what a screen saver would take).
- Unit tests grew from 33 to 106, including saved files written by the real 1.1.1 and 1.2.0 code and recorded Open-Meteo and GitHub responses. The headless development check now covers pausing, import, playlists, shortcuts, weather and renders every screen.

### Changed
- Settings are grouped with new Keyboard shortcuts and Weather sections and scroll in the Settings window.
- Preferences given as launch arguments (for example `-pauseWhenCovered NO`) are now honoured.
- Library items, Day/Night pairs and playlists gained optional fields; files saved by 1.1.1 and 1.2.0 load unchanged.

### Fixed
- A playlist playing on all displays no longer wipes a wallpaper or Day/Night pair you set on one display when it changes to the next item (starting the playlist still replaces them, as before).
- A video's desktop picture that finishes rendering after you already switched wallpapers no longer replaces the newer one.
- Importing the same file twice at once (for example dropping it twice) adds it once.
- A different photo that only shares a name and size with one in your library (two cameras' `IMG_0001.JPG`) is added instead of being treated as a duplicate.
- GIFs were recognised by their first byte as video; they are photos again. A file whose contents don't match its extension (a photo named `.mp4`) is refused.
- Manual Day/Night times saved outside 00:00–23:59 (hand-edited preferences) are read as that time of day instead of giving wrong phases.
- A damaged `playback.json` or zone.tab entry, or an impossible audio sample rate, can no longer crash Lucid.
- Opening Settings inside the main window could crash in development builds of this release (a missing shared object); every window now gets the same set, and the development check renders each screen to catch it.

### Security
- Imports check the file's contents, size and readability before copying, give copies sanitised names inside Lucid's Media folder, skip links that point outside a chosen folder, and never delete files used in place. Lucid now only deletes files strictly inside its Media folder.
- New network features use HTTPS only, fixed hosts, short timeouts, response size limits and strict parsing, and fail quietly.
- Releases publish `Lucid.zip.sha256`; `install.sh` verifies it and only uses HTTPS, including redirects. Only a release older than 1.3.0 (checksum "not found") installs without it; any other failure to fetch the checksum stops the install.
- Removing a wallpaper deletes only Lucid's own files: real files inside its Media and Thumbs folders, never a link or a path outside them, even if `library.json` says otherwise.
- Files dropped into Lucid's folder are never followed through links: a link there can no longer make Lucid move or delete the file it points to.
- The update check opens a release page only if it is exactly `https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/tag/…` (no `..`, user names, ports, queries or escapes).
- Turning off "Use my location" for Day/Night also forgets the saved approximate location.
- Development test switches (`-lucidCheck`, `-applyAerial`, `-testLive`, …) are read from the command line only, never from saved preferences; the headless check refuses to run without a throwaway `LUCID_SUPPORT_DIR` and keeps its settings apart from yours.
- The release workflow accepts only an `x.y.z` VERSION and passes it to the shell through the environment.
- `docs/security-review.md` documents every input, every `Process` use and the permissions Lucid asks for.

## [1.2.0] - 2026-10-26

### Added
- **Audio-reactive wallpapers** (off by default). Captures the sound your Mac plays with a Core Audio tap (macOS 14.2+, never the microphone), analyses it on device, and drives per-display looks: pulse on bass, glow with volume, spectrum bars. Capture stops whenever no reactive wallpaper is playing.
- **Day & Night wallpapers.** Pick a day and a night wallpaper per display or for all displays. Switches at sunrise and sunset (NOAA equations, location from your time zone or, if you allow it, your Mac's location) or at fixed times, with a short cross-fade. Re-checks after sleep, time zone and clock changes.
- Unit tests for the new logic (`./test.sh`, also run in CI) and a headless development check for Day/Night and audio-reactive looks (`-lucidCheck YES`, off by default).

### Changed
- Changing wallpaper now cross-fades the new window over the old one, then releases the old player and its window observer.
- `LUCID_SUPPORT_DIR` lets a development build use a throwaway data folder.
- Saved libraries, favorites, playlists and display settings now load entry by entry, so one entry Lucid doesn't recognise is skipped instead of discarding the whole file.
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

[Unreleased]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/tag/v1.0.0
