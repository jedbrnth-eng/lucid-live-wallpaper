# Lock Screen and Screen Saver: feasibility (Lucid 1.3.0)

Scope: can Lucid show a live video on the macOS Lock Screen and/or as a Screen Saver using **public APIs only**, on macOS 14 (Sonoma) to macOS 26 (Tahoe)? Research done October 2026. Anything marked **Unverified** has not been tested on hardware for this document.

## TL;DR

- **Screen Saver: feasible, with caveats.** The only public route is a `.saver` bundle (a `ScreenSaverView` subclass) hosted by Apple's `legacyScreenSaver` process. It can play video with AVFoundation. The host has been buggy since Sonoma and is worse on Tahoe.
- **Lock Screen wallpaper: not feasible with public APIs.** The moving Lock Screen (Aerials) is Apple-only. Third-party projects that do it use the private `WallpaperExtensionKit` / `com.apple.wallpaper` extension point, or patch Apple's `idleassetsd` assets. Lucid should do neither.

## 1. ScreenSaver.framework (`.saver`)

**What it is.** You subclass `ScreenSaverView`, set it as `NSPrincipalClass` in a `BNDL` bundle with the `.saver` extension, and override `startAnimation` / `stopAnimation` / `animateOneFrame`. Public headers declare only `ScreenSaverView` and `ScreenSaverDefaults`.
- https://developer.apple.com/documentation/screensaver
- https://developer.apple.com/documentation/screensaver/screensaverdefaults
- https://wadetregaskis.com/how-to-make-a-macos-screen-saver
- https://github.com/AerialScreensaver/AppexSaverMinimal/blob/main/BACKGROUND.md (classes, `.saver` vs `.appex`)

**Building without Xcode.** You can build a `.saver` with `swiftc -emit-library -Xlinker -bundle`, a minimal Info.plist and ad-hoc `codesign`. This has been reported working on macOS 26 on Apple Silicon, which matches Lucid's swiftc-only build.
- https://ytyng.com/en/blog/macos-26-screensaver-webview-without-xcode

**Install location.** Double-clicking a `.saver` asks the user whether to install it for this user (`~/Library/Screen Savers`) or for all users (`/Library/Screen Savers`, needs admin). Copying the bundle into `~/Library/Screen Savers` also works. On Tahoe the saver is listed under System Settings > Wallpaper > Screen Saver > Other/Custom (the separate pane was removed).
- https://github.com/AerialScreensaver/ScreenSaverMinimal (README, "Installing")
- https://theevilbit.github.io/beyond/beyond_0016
- https://github.com/JohnCoates/Aerial/issues/1396 , https://forum.iscreensaver.com/t/macos-26-tahoe-beta/772

**Host process and known bugs (Sonoma to Tahoe).** Since Catalina, third-party `.saver` plug-ins load inside the sandboxed `legacyScreenSaver.appex`. Documented problems:
- Instances pile up. A new `ScreenSaverView` is created on every start and every time the settings preview opens. Old instances are not stopped or released, and `stopAnimation` is often not called. Memory and CPU grow, and users report `legacyScreenSaver` using more than 1 GB of RAM.
  https://mjtsai.com/blog/2025/12/10/how-to-make-a-macos-screen-saver ,
  https://github.com/AerialScreensaver/ScreenSaverMinimal (README "About Sonoma+") ,
  https://discussions.apple.com/thread/255256761 , https://developer.apple.com/forums/thread/738547
- **Workaround:** observe the distributed notification `com.apple.screensaver.willstop` and call `exit(0)` to kill the host. The community prefers `exit(0)` over `NSApplication.terminate`. It is heavy-handed, and the notification sometimes never arrives (seen on 14.1 with fast start/stop).
  https://github.com/JohnCoates/Aerial/issues/1305 , https://github.com/JohnCoates/Aerial/issues/1339 ,
  https://www.jwz.org/blog/2023/10/xscreensaver-6-08-out-now/
- **`isPreview` and frame bugs.** `init(frame:isPreview:)` can receive the wrong `isPreview` value and a 0x0 frame (Sonoma, Sequoia). On Tahoe the `isPreview` bug has **no known workaround**. Tahoe also starts 2 instances when the settings sheet opens, and multi-monitor support breaks in new ways. Apple tracks instance build-up as FB19204084.
  https://developer.apple.com/forums/thread/787444 , https://github.com/JohnCoates/Aerial/issues/1396
- **Stale code after updates.** The host keeps the bundle mapped in memory, so an updated `.saver` only takes effect after `killall legacyScreenSaver`. `ScreenSaverDefaults` can also be stale.
  https://ytyng.com/en/blog/macos-26-screensaver-webview-without-xcode , https://github.com/Waitsnake/AnimatedGif/issues/74

**Video playback.** Yes, through AVFoundation (`AVPlayerLayer`/`AVPlayer` in the view's layer). Aerial 1.x to 3.x shipped as a `.saver` that streamed and played HEVC/H.264 Apple TV videos this way, including HDR on Catalina and later.
- https://github.com/JohnCoates/Aerial (legacy `.saver` versions), https://github.com/JohnCoates/Aerial/issues/801

**Sandbox and file access.** This decides whether the saver can read Lucid's media.
- `legacyScreenSaver` is sandboxed. Container APIs (`NSHomeDirectory`, `FileManager` Application Support/Caches URLs, `UserDefaults`) resolve inside `~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/...`. Intel/Rosetta uses a `.x86-64` suffixed container. https://forums.developer.apple.com/forums/thread/117136 , https://developer.apple.com/forums/thread/839190
- **Writes** are limited to that container. **Reads** reach most of the disk. The exceptions are TCC-protected folders (Documents, Downloads, Desktop), removable or network volumes, and symlinks that escape the sandbox. Aerial therefore told users to put custom videos in `/Users/Shared/`. https://github.com/JohnCoates/Aerial/issues/801 , https://github.com/JohnCoates/Aerial/blob/master/Documentation/Troubleshooting.md
- An Apple DTS reply (2026, macOS 27 beta) says the process that runs a legacy saver "isn't tightly sandboxed". It suggests keeping saver state in `~/Library/Application Support/<Product>` instead of the container preferences. https://developer.apple.com/forums/thread/839190 (quoted from the search index; the page sits behind a bot check)
- Aerial 4 now keeps all its data in `/Users/Shared/Aerial/`, "which any app can read and write". https://aerialscreensaver.github.io/faq
- **Conclusion:** a `.saver` can **probably read** a file under the real `~/Library/Application Support/Lucid/...`. Lucid is not sandboxed, so that folder is not another app's container and should not trigger the Sonoma "App Data" prompt. The saver must build the real home path with `getpwuid(getuid())`, not `NSHomeDirectory()`. **Unverified on 14, 15 and 26.** Ship a runtime check and a fallback location.

**Signing and Gatekeeper.** Gatekeeper checks plug-ins too. Downloaded (quarantined) software must be Developer ID signed and notarized, or the user must approve it manually. Since Sequoia, Control-click no longer bypasses the check; the user has to use System Settings > Privacy & Security > Open Anyway. A locally built, ad-hoc signed, non-quarantined `.saver` loads (reported on 26). Behaviour of an unnotarized but quarantined `.saver` inside `legacyScreenSaver` on 15/26 is **Unverified**. It may fail silently instead of showing a prompt.
- https://support.apple.com/en-us/102445 , https://developer.apple.com/news/?id=saqachfa
- https://github.com/AerialScreensaver/ScreenSaverMinimal ("Distribution": sign + notarize + staple)

**Not public:** the `.appex` screensaver extension point (`com.apple.screensaver`) used by Apple and Aerial 4. It is private, undocumented and not allowed on the Mac App Store. https://github.com/AerialScreensaver/AppexSaverMinimal

## 2. Lock Screen

- **What the Lock Screen shows.** Since Sonoma, the Lock Screen draws the current wallpaper. The clock can appear on the Lock Screen only, or on both the Screen Saver and the Lock Screen. If an Aerial is the wallpaper, it animates on the Lock Screen and slows to a still on unlock. A screen saver that is already running stays behind the lock UI ("the screensaver proper is those windows with the lock UI on top", observed for app-extension savers). Whether a **legacy `.saver`** keeps rendering behind the password UI on every version is **Unverified**.
  https://support.apple.com/en-asia/guide/mac-help/mchlp1103/mac , https://github.com/AerialScreensaver/AppexSaverMinimal/blob/main/BACKGROUND.md
- **Lucid's desktop window.** A normal app window at desktop level is hidden by the lock shield. Lucid's current renderer cannot show through. (Observed behaviour; Apple does not document it.)
- **Public API for a moving Lock Screen wallpaper: none.** `NSWorkspace.setDesktopImageURL` accepts still images only. Aerial/"dynamic" wallpapers come from the `com.apple.wallpaper` extension point, backed by the private `WallpaperExtensionKit` and hosted by `WallpaperAgent`. Apple has not documented it for third parties. Nothing in WWDC 2023 to 2025 opened it up (**Unverified**: no session found). You cannot set a `.saver` as a wallpaper either.
  https://github.com/AerialScreensaver/Aerial (README: 4.1 "backed by Apple's private `WallpaperExtensionKit`"),
  https://github.com/kageroumado/phosphene (README: "Uses private `WallpaperExtensionKit` APIs"),
  https://github.com/AerialScreensaver/ScreenSaverMinimal ("About Sonoma+": the Aerial wallpaper is "exclusive to Apple")
- Products that advertise live Lock Screen video on macOS 26 (MacWall, MirageWallpaper, Phosphene) appear to use that private extension point. Phosphene states this outright; for the others it is **Unverified**.
  https://macwall.app/docs/live-lock-screen-and-screen-saver , https://github.com/laobamac/MirageWallpaper/releases
- **NOT recommended: patching `idleassetsd`.** Editing the Aerials manifest (`entries.json`) and video files under `/Library/Application Support/com.apple.idleassetsd/Customer/` needs admin rights. It is undocumented, can be undone by OS updates or asset downloads, has known black-after-unlock problems, and the best-known tool reports that it **stopped working on Tahoe**.
  https://medium.footle.org/screensaver-spelunking-cfe6e31dd21c , https://github.com/FalconLee1011/Customized-Aerial-Screen-Saver ,
  https://github.com/AlexisBCD/macos-custom-video-wallpaper-fix

## 3. Recommendation for Lucid

**Ship (optional, opt-in): `LucidSaver.saver`**, a separate public-API screen saver that loops one user-chosen clip.

Minimal design:
1. **Files.** `Sources/LucidSaver/LucidSaverView.swift` (a `ScreenSaverView` subclass with an `AVPlayerLayer`, muted, looping via `AVPlayerLooper`), `Resources/LucidSaver-Info.plist` (`CFBundlePackageType=BNDL`, `NSPrincipalClass=LucidSaver.LucidSaverView`, unique `CFBundleIdentifier`), and a build step: `swiftc -emit-library -Xlinker -bundle -module-name LucidSaver ...` then ad-hoc or Developer ID `codesign`. arm64 only, to match Lucid.
2. **Picking the clip.** In Lucid, add "Use as Screen Saver…" on a library item. Lucid copies (or hard-links, same volume only) the file to a fixed handoff path and writes a small `saver.json` (`{"file": "...", "fill": "aspectFill"}`).
3. **Handoff path.** Primary: `~/Library/Application Support/Lucid/ScreenSaver/` (real home, from `getpwuid`). Fallback: `/Users/Shared/Lucid/ScreenSaver/` (Aerial's proven location; readable by every user, so mention the privacy trade-off in the UI). The saver tries the primary path, then the fallback, then draws a "Choose a clip in Lucid" placeholder. Never point it at Documents, Downloads, Desktop, external drives or symlinks.
4. **Install.** Lucid opens the bundled `.saver` with `NSWorkspace` so the system install dialog appears (user-initiated), then opens Wallpaper settings. Lucid never writes into `/Library` or system preferences.
5. **Lifecycle hardening.** Observe `com.apple.screensaver.willstop` and call `exit(0)`, guarded so it never runs in the preview. Treat `isPreview` as unreliable: also check the window or frame size. Fix a 0x0 frame using `NSScreen` size. Keep at most one player per display, release the player when the view leaves its window, and pause when `window == nil`. Base this on ScreenSaverMinimal's workarounds.
6. **Settings.** No `ScreenSaverDefaults` sharing with the app. The JSON file is the only contract.

**Not feasible / will not ship:** a live video wallpaper on the Lock Screen; registering as a wallpaper/Aerial provider (private `WallpaperExtensionKit`); `.appex` screensavers (private); any `idleassetsd` modification; making Lucid's desktop window draw over the lock screen.

**Risks:**
- Apple breaks `legacyScreenSaver` in each major release (Sonoma, Sequoia and Tahoe all regressed), so expect maintenance work every year.
- Memory and CPU leaks from the host if the `exit(0)` workaround misfires.
- Gatekeeper friction for an unnotarized download. Lucid has no Developer ID, so users see "Open Anyway", or the saver fails to load. **Unknown**, needs testing on 15/26.
- File-read access is inferred, not guaranteed. **Must be tested** on 14, 15 and 26 before release, with a log line recording which path the saver resolved.
- HDR/high-bitrate clips in a sandboxed host can decode differently from the app. **Unverified.**

**Test plan before enabling:** clean macOS 14, 15 and 26 VMs/hosts. Download the release zip (quarantined), install, check that the saver lists and plays from both paths, check the lock screen with "require password immediately", run 50 start/stop cycles watching `legacyScreenSaver` RSS, and test with 2 displays.

## Decision for 1.3.0

Not shipped in 1.3.0. The `.saver` route is the only public-API option, but it is only safe to ship after the test plan above
passes on macOS 14, 15 and 26 (file access from the saver host and Gatekeeper behaviour for an unnotarized, quarantined bundle
are both unverified, and Tahoe's `isPreview` bug has no known workaround). Lucid 1.3.0 therefore writes nothing into
`~/Library/Screen Savers`, `/Library`, `idleassetsd` or any Apple wallpaper location. Revisit once the app is notarized.
