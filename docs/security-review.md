# Security review and threat model (Lucid 1.3.0)

Lucid is a local, unsandboxed, ad-hoc signed macOS app (GPL-3.0, no third-party dependencies). It has no account, no
server of its own and no telemetry. This note lists every input Lucid takes, what it does with it, and the mitigations.
Reviewed for 1.3.0 on 2026-10-26.

## Inputs

| Input | Where it comes from | What Lucid does with it | Mitigations |
|---|---|---|---|
| **Imported files** (drag and drop, Import…, Dock, the Lucid folder, opt-in ~/Downloads watcher) | Any file the user picks | Reads the first 16 bytes, decodes with AVFoundation/ImageIO, copies into `Application Support/Lucid/Media` (or plays in place if the user chose that), converts WebM/MKV with ffmpeg if installed | `ImportPolicy.check`: known extension, non-empty, max 16 GB, header must be a known video/photo signature (programs, scripts and truncated files refused). Damaged files are rejected before anything is copied. A chosen symlink is resolved and must be a regular file; folder import skips symlinks and hidden files and only takes files really inside the chosen folder (max 500). Copies get a sanitised name (letters, digits, `-`, `_`; length-bounded; extension letters/digits only) and the destination must be strictly inside `Media/`. A failed conversion leaves no partial file. Lucid deletes only its own copies inside `Media/`, never an in-place file. |
| **Saved JSON** (`library.json`, `favorites.json`, `playlists.json`, `state.json`, `playback.json`, `weather.json`) | Lucid itself, older or newer Lucid versions, or hand edits | Decoded at launch | Every list and dictionary decodes entry by entry (`LossyArray`/`LossyDictionary`); optional 1.3.0 fields (`options`, `dawn`/`dusk`, `times`, `weather`) decode leniently, so one bad entry is dropped, never the file and never a crash. Saved files from 1.1.1 and 1.2.0 (written by the real old model code) and 1.2.0 development builds are unit-tested. Writes are atomic. No migration deletes user files. |
| **Network responses** | Content providers (existing), Open-Meteo (new, opt-in), GitHub releases API (new, opt-in) | Parsed as JSON | New code: HTTPS only, fixed hosts, ephemeral sessions (no cookies or cache), 15 s request / 20 s total timeout, HTTP 200 and same final host required, size caps (weather 64 KB, streamed and cut off; GitHub 512 KB). Parsers read only the fields they need and reject wrong types/ranges (weather code must be an integer 0-99; release page must be `https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/...`). Errors are silent: the normal wallpaper stays. Rate limits: weather at most every 30 min, back-off from 5 min doubling to 6 h, 60/day cap; update check once a day. Recorded real responses are unit-tested; no test uses the network. |
| **Global shortcuts** | The keyboard | Pause/resume, next, previous | Carbon `RegisterEventHotKey`: macOS delivers only the exact combinations registered; Lucid never sees other keystrokes and needs no Accessibility or Input Monitoring permission. Off by default. Duplicates and well-known macOS shortcuts are refused; a combination owned by another app is reported (`eventHotKeyExistsErr`), not stolen. |
| **System audio** (existing, opt-in) | Core Audio process tap | FFT on device for audio-reactive looks | Off by default; macOS permission prompt; never the microphone; nothing recorded or sent; capture only while a reactive wallpaper plays. |
| **Location** (existing, opt-in) | CoreLocation, only when the user turns on "Use my location" for Day/Night | Sunrise/sunset; rounded to 0.01° before it is saved | No new prompt in 1.3.0. Weather uses the time-zone city unless that opt-in is already on; either way the coordinates sent are rounded to 0.1° (about 10 km). |
| **`install.sh`** | `curl … | bash` from the README | Downloads `releases/latest/download/Lucid.zip`, installs into /Applications (or ~/Applications), clears the quarantine flag, opens Lucid | 1.3.0: curl restricted to HTTPS also across redirects, TLS 1.2+; verifies `Lucid.zip.sha256` when the release has one (refuses a mismatch or a malformed checksum file; continues with a notice for older releases that have none). Tested with a harness that stubs curl/pgrep/open and installs into a scratch folder: no checksum -> installs with notice; match -> "Checksum OK"; mismatch -> exit 1, nothing installed; garbage -> exit 1. |

## Process / AppleScript uses (all of them)

`grep -rn "Process()\|NSTask\|NSAppleScript\|osascript\|system(\|popen\|posix_spawn" Sources tools *.sh .github`:

- `Sources/Lucid/Media/LoopMaker.swift` (`Transcoder.toHEVC`): runs ffmpeg from a fixed list of paths (`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`), with an argument array (no shell). The only variable arguments are the absolute input and output paths (they start with `/`, so they can't be read as ffmpeg options). Residual risk: ffmpeg parses an untrusted file the user chose; a malicious file could target an ffmpeg bug. A process running as the user could also replace a user-writable ffmpeg, but it could already do anything Lucid can.
- `install.sh`: `osascript -e 'tell application "Lucid" to quit'`, a constant string.
- No other `Process`, `NSTask`, AppleScript, shell or `system()` call. No user string ever reaches a shell.

## Permissions (Info.plist)

- `NSAudioCaptureUsageDescription`: system audio for audio-reactive looks, never the microphone. Asked only when the feature is turned on.
- `NSLocationUsageDescription` / `NSLocationWhenInUseUsageDescription`: Day/Night; 1.3.0 wording adds that a rounded location is sent to Open-Meteo only if Weather wallpapers are also on. Asked only when "Use my location" is turned on.
- No microphone, camera, Accessibility, Input Monitoring, Screen Recording, contacts or files-and-folders entitlement is requested.

## Release pipeline

- `release.yml` (1.3.0 change, additive): also writes `Lucid.zip.sha256` and attaches it to the release. Nothing else changes; no step is removed or weakened.
- What a checksum does and doesn't do: it detects a damaged or swapped download, and lets people and package managers (the draft Homebrew cask) pin the exact bytes. It does **not** prove who built the zip: anyone who can publish a release can publish a matching checksum. Real authenticity needs Developer ID signing + notarization (a decision for the owner; needs an Apple Developer account).
- Recommended, not done here: pin `actions/checkout` to a full commit SHA instead of `@v4` in both workflows (a moved tag could change what runs with `contents: write`).
- `install.sh` clears the quarantine flag by design, which skips Gatekeeper's first-launch check. The README says so; the checksum check runs before that.

## Static checks run for 1.3.0

- `swiftc -typecheck -warnings-as-errors` over all app sources, over the pure (unit-tested) sources, and over the tests: exit 0, no warnings.
- No `try!`, `as!` or force unwraps in the new parsing code (`Weather.swift`, `UpdateCheck.swift`, `ImportPolicy.swift`, `PlaylistScheduler.swift`, `Hotkey.swift`, `PausePolicy.swift`).
- `codesign --verify --deep --strict` on the built app: OK (ad-hoc signature).
- Dependencies: none added (Apple frameworks only; Carbon added for hot keys).
- Secret scan of the 1.3.0 diff (`git diff ed0e740` added lines) for personal emails, the developer's home path and machine name, and GitHub/OpenAI/AWS token and private-key patterns: no matches. Fixture paths are made up (`/Users/example/...`).

## Known residual risks

- The app is not notarized; users approve it once with "Open Anyway" (or the installer clears the flag).
- ffmpeg (optional, user-installed) parses untrusted video when converting WebM/MKV.
- Open-Meteo's free tier is for non-commercial use; Lucid is free and open source. If that changes, revisit.
