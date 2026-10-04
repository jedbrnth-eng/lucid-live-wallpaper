# Lucid

**Live 4K wallpapers for Mac.** A free, native live-wallpaper app for macOS. Moving space, nature and ocean wallpapers on every display, with no account, no subscription and no tracking.

![Lucid showing the Apple Aerials catalog](docs/screenshot.png)

**[Download the source (.zip)](https://github.com/jedbrnth-eng/lucid-live-wallpaper/archive/refs/heads/main.zip)**, then follow [Install](#install) below. About 2 minutes.

## Features
- **Live 4K catalog:** ~590 curated moving wallpapers from ESA/Webb, ESA/Hubble, ESO, NASA and Wikimedia Commons. Every clip is verified as 3840×2160 or larger, then turned into a seamless loop (HEVC, no audio). Each item shows its full credit and links to its license.
- **Apple Aerials:** Apple's 4K aerial films. Films already on your Mac apply instantly; others download from Apple's servers when you pick them (about 300–600 MB each).
- **NASA 4K Space and Wikimedia 4K Photos:** high-resolution stills, license shown on every item.
- **Pixabay 4K Video** (optional): paste your own free Pixabay key in Settings. It is stored in your Keychain.
- **My Library:** bring your own wallpapers. Drag videos, photos or whole folders onto the window or the Dock icon, use **Import…**, or just drop files into `~/Library/Application Support/Lucid/Media` and they appear within seconds. Anything below 4K is flagged.
- **Per-display wallpapers**, auto-change timer, open at login.
- **Battery-friendly:** pauses when the wallpaper is covered, in Low Power Mode, on battery, when the screen locks or the display sleeps.
- **No dependencies, no telemetry.** Native SwiftUI/AppKit in one source file.

## Requirements
- macOS 14 or later, **Apple Silicon** (the build target is arm64)
- To build from source: Xcode Command Line Tools (`xcode-select --install`)
- Optional: `ffmpeg`/`ffprobe`, only for converting WebM/MKV files and rebuilding the catalog

## Install
Lucid is built from source on your own Mac, so there is no "unidentified developer" warning to fight and you can read exactly what runs.

1. **Get the tools (once):** open Terminal and run `xcode-select --install`. Skip this if you already have Xcode or its Command Line Tools.
2. **Get the code:** [download the .zip](https://github.com/jedbrnth-eng/lucid-live-wallpaper/archive/refs/heads/main.zip) and unzip it, or clone it:
   ```
   git clone https://github.com/jedbrnth-eng/lucid-live-wallpaper.git
   ```
3. **Build:**
   ```
   cd lucid-live-wallpaper
   ./build.sh        # creates build/Lucid.app (about a minute)
   open build/Lucid.app
   ```
4. **Keep it:** drag `build/Lucid.app` into Applications, then right-click its Dock icon → Options → Keep in Dock. The first launch from Applications may need right-click → **Open**, because the app is ad-hoc signed, not notarized.

If `./build.sh` says "Permission denied", run `chmod +x build.sh` first.

## Use it
Open Lucid. It also lives in the menu bar.

- **Pick a wallpaper:** browse **Discover** (Apple Aerials, Live 4K, NASA, Wikimedia, Pixabay), hover a card and click **Apply**, or open it and choose **Set as Wallpaper**.
- **Several monitors:** use **Set on Display** to give each screen its own wallpaper.
- **Add your own videos and photos:** drag files or folders onto the window or the Dock icon, click **Import…** in **Downloaded**, or drop them into `~/Library/Application Support/Lucid/Media`. They show up under **Downloaded → My Files**.
- **Favorites and playlists:** tap the heart on anything, or make a playlist that shuffles every few minutes.
- **Settings:** open at login, auto-change timer, battery behavior, optional Pixabay key.

## How it works
Each display gets a borderless window at desktop level, above the system wallpaper and below the desktop icons, holding a muted, hardware-decoded looping `AVQueuePlayer`. A frame from the video is also set as the real desktop picture, so Mission Control and other Spaces show a matching still.
Data lives in `~/Library/Application Support/Lucid/`.

## Privacy
No analytics or telemetry. The app only contacts the content sources above (NASA, ESA, ESO, Wikimedia Commons, Apple's servers for Aerial films you choose, and Pixabay if you add a key) to browse and download what you choose.

## Test
```
./selftest.sh                                      # every source returns only ≥3840×2160 items
python3 -m unittest tools/test_build_catalog.py    # offline catalog-builder tests
python3 tools/build_catalog.py catalog.json        # rebuild the Live 4K catalog (slow)
```

## Content and licenses
**The code** is MIT licensed (see `LICENSE`). **This repo contains no wallpaper media.** `catalog.json` is a list of links and credits. The app downloads clips from their original sources onto your Mac.

The wallpapers belong to their creators, each under its own license, and the app shows the credit and license for every item:
- **NASA:** generally public domain. Credit NASA, and don't imply endorsement.
- **ESA/Webb, ESA/Hubble, ESO:** CC BY 4.0. Soundtrack music is licensed separately, so the loop maker removes audio. ESO footage of identifiable people is not for commercial use.
- **Wikimedia Commons:** per file (CC0, CC BY, CC BY-SA…). Credit the author if you share a file.
- **Apple Aerials:** Apple content that ships with macOS, for personal use on your Mac only. It is never bundled or redistributed.
- **Pixabay:** free to use, but files must not be redistributed as-is.

Loops are modified (cross-faded, re-encoded) copies for **personal use on your own Mac**. If you republish any of them, follow each item's license, including attribution and share-alike. Full research notes: [`SOURCES.md`](SOURCES.md).

*Not affiliated with or endorsed by Apple, NASA, ESA, ESO, Wikimedia or Pixabay.*
