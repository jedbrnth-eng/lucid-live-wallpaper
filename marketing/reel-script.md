# Lucid: launch reel for TikTok and Instagram Reels

Shot-by-shot production package. Vertical 9:16, 1080×1920, 30 fps delivery (shoot 4K60). Target runtime 27 s.

Read the "Problems with the brief" section first. Several things in the original ask will get the video flagged, ignored, or make the project look dishonest. The script below is already corrected for them.

---

## Problems with the brief (fix these before you shoot)

1. **Lucid is a Mac app. Reels and TikTok are phone-first.** Every piece of app footage is 16:9 and the frame is 9:16. You cannot just drop a screen recording in; it becomes a thin strip with a blurred background like every low-effort ad. Two fixes, both used below: (a) crop hard into the region that matters (the Apply button, the one Terminal line) so the UI fills the vertical frame, and (b) shoot the physical Mac with a phone camera for every "beauty" moment. A real screen, filmed in a dark room, is what makes it feel like an Apple ad. A screen recording never will.

2. **"Real users" do not exist yet.** First public release was 2026-10-04. Faking testimonials for an open-source project is the fastest way to kill it on Reddit and Hacker News, and it is also the kind of thing platforms label. The real version: film 2 or 3 people seeing it for the first time, unscripted, phone camera, natural reactions. Do not feed them lines. If their reaction is flat, don't use it. Second source of real users: post to r/macapps and r/MacOS the day before, and screenshot genuine comments (ask permission in a reply). Both are real. Scripted "users" are not.

3. **The 10-second claim depends on the viewer's Wi-Fi, not your code.** The installer downloads `Lucid.zip` from GitHub releases. On a fast connection it is 10 s. On hotel Wi-Fi it is 40 s. The script shows the install in real time with a running stopwatch, no cuts. Measure it on your machine before you shoot. If it comes in at 13 s, the on-screen text says "about 10 seconds" and the timer shows 13. If it comes in at 25 s, change the claim; do not fake the timer.

4. **Do not put Apple Aerials in the ad.** The README screenshot and demo currently feature them. Apple Aerials are Apple content for personal use on your Mac. Using them in a promotional video is redistribution. Every wallpaper on screen in this reel comes from the Live 4K catalog under CC BY or public domain, and every one gets credited in the caption. The shot list names the exact clips.

5. **Do not name or show a competitor.** "Many competing apps charge for the same thing" is the hook, but a logo or a product name in a comparison ad invites a takedown and makes you look petty. Screenshot a real paywall, blur the app name and icon, show only the price UI. Verify the price the day you post.

6. **"4K" cannot be seen on a phone.** The viewer is watching 1080p on a 6-inch screen. The 4K claim is carried by the on-screen badge in the UI, the text, and by a macro camera shot of a real display where the pixels are not visible. Don't waste a shot "proving" 4K. It can't be proven in this format.

7. **The GitHub URL is unreadable at phone size.** `github.com/jedbrnth-eng/lucid-live-wallpaper` is 44 characters. Nobody types that from a 1.5-second end card. The CTA below uses "Link in bio" plus "Search: Lucid Live Wallpaper on GitHub" and shows the URL small as a trust signal only. Put the link in the bio and in a pinned comment before the video goes live. Better: register a short domain that redirects.

---

## Format specs

| | |
|---|---|
| Canvas | 1080 × 1920, 30 fps export (shoot phone footage at 4K60 so you can slow it down) |
| Runtime | 27 s. Under 30 keeps completion rate up, which is the single biggest ranking signal. |
| Safe zones | Keep text out of the bottom 320 px (caption and buttons) and the right 150 px (TikTok action rail). Center titles between y=400 and y=1500. |
| Frame 0 | The first frame is the cover on TikTok. The hook text must already be on screen at frame 1. No fade-in. |
| Captions | Burned in. Most people watch muted. The on-screen text below IS the caption track. |
| Type | Inter (free, Open Font License). SF Pro's license restricts it to Apple-platform UI mockups, so don't ship it in an ad. Weights: Medium for body, Semibold for hooks. Tracking −2 %. White #FFFFFF, secondary #A1A1AA, accent #7C5CFF (your release badge color). |
| Grade | Crush blacks slightly, never lift them. Dark room, single practical light source, screen is the key light. No LUT with teal/orange. |
| Transitions | Hard cuts and one dip-to-black. No wipes, no zoom transitions, no "cinematic" light leaks. Apple cuts on the beat and holds. |

---

## Shot list

Timecodes are mm:ss.f. "Camera" means phone or mirrorless on a tripod filming a real Mac. "Screen" means a 4K QuickTime screen recording (⌘⇧5), cropped into the vertical frame in the edit.

### S01 · 00:00.0 – 00:02.0 · HOOK

| | |
|---|---|
| Source | Camera. Dark room. MacBook open on a desk, camera 30° off-axis so the screen fills about 70 % of the vertical frame, slight top-down. Focus on the screen. Shutter 1/60 at 30 fps to avoid screen flicker. |
| On screen (Mac) | Desktop only, no windows. Wallpaper: **"Pan of the Crab Nebula" (ESA/Webb, CC BY 4.0)**, already applied and moving. |
| Camera move | None. Locked off. Movement comes from the wallpaper itself. |
| Text | Centered, Semibold 88 px, two lines, cut in on frame 1:<br>**Still paying for**<br>**live wallpapers?** |
| Sound | Silence for 6 frames, then one sub-bass hit (40–60 Hz, 400 ms decay) exactly as the text appears. No music yet. Room tone under. |
| Why | A question that names the viewer's expense stops the thumb. The silence-then-thump is the pattern interrupt. The nebula moving behind the text is the proof before the pitch. |

### S02 · 00:02.0 – 00:03.5 · THE PRICE

| | |
|---|---|
| Source | Screen. A real paywall from a paid Mac live-wallpaper app, app name and icon blurred (gaussian, strong), only the price and "Subscribe" or "Unlock" button legible. Crop to the price. |
| Text | Lower third, Medium 56 px, #A1A1AA:<br>Some apps charge for this. |
| Sound | Single dry UI tick on the cut. Still no music. |
| Note | Verify the price the day you post. Keep the screenshot as evidence. |

### S03 · 00:03.5 – 00:05.5 · THE TURN

| | |
|---|---|
| Source | Dip to black (4 frames). Black frame. |
| Text | Centered, Semibold 96 px:<br>**This one's free.**<br>Then at 00:04.5, below it, Medium 48 px, #A1A1AA, fades in over 8 frames:<br>and open source. |
| Sound | Music starts here, on "free": a single low piano note or soft synth pad, held. Sub-bass hit on "free". Nothing on "open source." |
| Why | The music starting on the word "free" ties the emotion to the price. Apple does the same thing: silence, then one note. |

### S04 · 00:05.5 – 00:15.5 · THE 10-SECOND INSTALL (real time, no cuts)

| | |
|---|---|
| Source | Screen. Terminal, dark theme, font size bumped to 18 pt so it reads at phone size. Crop to a 1080×1920 region that frames the prompt line and about 8 lines below it. |
| Action | 00:05.5 paste the install line. 00:06.0 press Return. Progress bar runs. "Downloading Lucid..." → "Installing to /Applications..." → "Done. Opening Lucid..." → Lucid window appears. |
| Timer | Stopwatch burned in, top-right inside safe zone, Medium 44 px, monospace digits, starts on Return, stops when the Lucid window appears. Whatever it reads is what it reads. |
| Text | 00:05.5, top-center, Medium 56 px: **One line. Paste it.**<br>00:12.0, same position, replaces previous: **About 10 seconds.** |
| Sound | Music builds slowly (add a second layer: filtered arpeggio or soft hi-hat pattern). Keyboard click on Return (real recorded, not a stock typewriter). A low riser from 00:12 to 00:15.5. |
| Why | Ten uncut seconds is long on TikTok. The timer is what makes people stay: they want to see if it makes it. If you speed-ramp this, you lose both the proof and the retention device. Don't. |
| Audience note | Terminal filters out people who will never install an unsigned Mac app from GitHub anyway. That is your audience self-selecting. Lean in, don't hide it. |

### S05 · 00:15.5 – 00:18.5 · THE APPLY MOMENT

| | |
|---|---|
| Source | Screen, then Camera. |
| 00:15.5 – 00:16.5 Screen | Discover → Live 4K grid. Crop to a 2×2 block of tiles. Cursor hovers **"Zoom into Webb's View of the Pillars of Creation" (ESA/Webb, CC BY 4.0)**. The 4K and LIVE badges must be visible in the crop. Click **Apply**. |
| 00:16.5 – 00:18.5 Camera | Hard cut on the click to the same camera setup as S01 but a wider frame: the whole desk, MacBook, maybe a monitor. The desktop changes to the Pillars clip and it starts moving. Hold. No text for the first 20 frames. |
| Text | 00:17.2, bottom-center above safe zone, Medium 56 px: **Click Apply.** Nothing else. Let it breathe. |
| Sound | The drop lands on the cut (00:16.5): full music, a deep whoosh under a soft chime. Then the music opens up. This is the loudest moment in the video. |
| Why | This is the ad. Everything before it is setup. If this shot isn't beautiful on a real screen in a real room, reshoot it until it is. |

### S06 · 00:18.5 – 00:21.5 · THE CATALOG

Four cuts, 0.75 s each, all Camera on real displays, locked off, each a different wallpaper. Cut on the beat.

| Cut | Wallpaper (all from the Live 4K catalog) | License |
|---|---|---|
| 1 | "2016-09 Aurora timelapse Saguenay", 0x010C / Wikimedia Commons | CC BY-SA 4.0 |
| 2 | "Pan of the Carina Nebula (NIRCam Image)", NASA, ESA, CSA, STScI | CC BY 4.0 |
| 3 | "Rialto Beach Waves 2022", Sea Cow / Wikimedia Commons | CC BY-SA 4.0 |
| 4 | "Aerial views of Midtown Manhattan at night", the Dronalist / Wikimedia Commons | CC BY 3.0 |

If you have two displays, make cut 4 a wide shot of both running different wallpapers.

| | |
|---|---|
| Text | Persistent through all four cuts, top-center, Medium 56 px: **590+ wallpapers. All 4K.**<br>Small line under it, 40 px, #A1A1AA: Space · Nature · Ocean · Cities<br>On cut 4 only, if dual display: replace with **A different one on every screen.** |
| Sound | Music at full. A soft transient (air, not a whoosh) on each cut. |

### S07 · 00:21.5 – 00:24.0 · REAL PEOPLE

| | |
|---|---|
| Source | Camera, handheld phone, natural light. Three cuts, ~0.8 s each, of real people seeing the wallpaper change on their own Mac for the first time. Over-the-shoulder or a reaction close-up. Unscripted. |
| Text | 00:21.5, top-center, Medium 48 px, #A1A1AA: First reactions. |
| Sound | Music ducks 6 dB. Let their real audio bleed in. One genuine "oh" is worth more than any VO line. If nobody reacts, cut this scene entirely and extend S06 by 2.5 s. Do not fake it. |
| How to get it | Install it on friends' or coworkers' Macs while filming. Tell them nothing except "watch the desktop." Get verbal okay on camera to use the clip. |

### S08 · 00:24.0 – 00:27.0 · CTA

| | |
|---|---|
| Source | Black. |
| 00:24.0 | App icon (`icon/AppIcon.png`) scales from 96 % to 100 % over 10 frames, centered, 360 px wide. Below it, wordmark **Lucid**, Semibold 80 px. |
| 00:24.8 | Under the wordmark, Medium 52 px, one line fading in: **Free. Open source. Mac.** |
| 00:25.6 | Under that, Medium 48 px, accent #7C5CFF: **Link in bio** <br>Then 36 px, #A1A1AA: Search "Lucid Live Wallpaper" on GitHub<br>Then 28 px, #52525B: github.com/jedbrnth-eng/lucid-live-wallpaper |
| 00:26.6 – 00:27.0 | Hold. Nothing moves. |
| Sound | Music resolves to a single held note at 00:24.0. One final sub hit on the icon landing. Music ends at 00:26.0. Last second is silence. Apple ends in silence, not on a sting. |
| Note | The last frame is also the loop point. On TikTok the video restarts; a black end card into the S01 nebula is a clean loop. |

---

## On-screen text, in order (copy-paste for the editor)

1. Still paying for live wallpapers?
2. Some apps charge for this.
3. This one's free.
4. and open source.
5. One line. Paste it.
6. About 10 seconds.
7. Click Apply.
8. 590+ wallpapers. All 4K.
9. Space · Nature · Ocean · Cities
10. A different one on every screen.
11. First reactions.
12. Lucid
13. Free. Open source. Mac.
14. Link in bio
15. Search "Lucid Live Wallpaper" on GitHub

Fifteen lines in 27 seconds. If you want to add anything, cut something first.

---

## Voiceover (optional)

Recommended version: **no voiceover.** Apple's product spots mostly don't have one. Text plus sound design reads as more expensive than a stock TTS voice, and every TTS voice sounds like every other TikTok ad. If you do want VO, the best free voice is yours, recorded close to a phone mic in a closet full of clothes. Authenticity sells open source.

If you still want synthetic VO, the script is five lines, delivered flat and slow, with a pause after each:

| Timecode | Line |
|---|---|
| 00:00.3 | Still paying for live wallpapers? |
| 00:03.7 | This one's free. And open source. |
| 00:06.0 | One line in Terminal. About ten seconds. |
| 00:16.8 | Click Apply. |
| 00:24.2 | Lucid. Free, on GitHub. |

### Free voice sources, with the catch on each

| Source | Cost | Quality | The catch |
|---|---|---|---|
| **Your own voice** | Free | Depends on you | None. Best option for an open-source project. |
| **Kokoro-82M** (Hugging Face, `hexgrad/Kokoro-82M`) | Free, runs locally | Very good, near commercial TTS | Apache 2.0 model weights. Clean for commercial use. Needs Python. |
| **Piper TTS** (`rhasspy/piper`) | Free, runs locally, offline | Good, slightly robotic on long lines | MIT. Clean for commercial use. The `en_US-ryan-high` and `en_GB-alan-medium` voices are the usable ones. |
| **edge-tts** (Python package, uses Microsoft Edge's neural voices) | Free | Excellent (`en-US-GuyNeural`, `en-US-AndrewNeural`) | Microsoft does not grant a commercial license for the Read Aloud voices. Fine for a draft, risky for the posted video. |
| **ElevenLabs free tier** | Free, 10k characters/month | Best of the list | Free tier is non-commercial and requires attribution. A promo for your app is arguably commercial. Starter plan is $5 if you want it clean. |
| **Higgsfield** (connected to this session) | Credits | Good | Not free. |

Draft command with Piper (clean license), one line per file so you can place them separately in the edit:

```bash
pip install piper-tts
piper --model en_US-ryan-high --download-dir voices --data-dir voices \
  --output_file vo_01.wav <<< "Still paying for live wallpapers?"
```

Slow any TTS output to 92–95 % speed in the edit. Every TTS voice talks too fast for an Apple-style read.

---

## Music

### Direction

One track, built in three stages, no vocals, no drums until the drop.

| Section | Timecode | What it does |
|---|---|---|
| Silence | 00:00 – 00:03.5 | No music. Sub hits and UI ticks only. |
| Hold | 00:03.5 – 00:12 | A single sustained piano or warm synth pad, one chord, minor key. Add a second quiet layer (filtered arpeggio or soft hi-hat) at 00:08. |
| Rise | 00:12 – 00:16.5 | Low riser, filter opening, tension. No resolution. |
| Drop | 00:16.5 | Full arrangement enters on the Apply cut: chord progression opens up, kick or sub pulse, airy pad. This is the loudest second. |
| Ride | 00:16.5 – 00:24 | Stay full through the catalog and reactions. Duck 6 dB under the real people. |
| Resolve | 00:24 – 00:26 | Collapse to one held note. End. |
| Silence | 00:26 – 00:27 | Nothing. |

Reference feel: Apple's "Shot on iPhone" and MacBook Air spots. Minimal piano, electronic texture, one big open moment. Tempo 90–110 BPM so the 0.75 s catalog cuts land on beats.

### Free music sources

| Source | License | Notes |
|---|---|---|
| **Pixabay Music** | Pixabay Content License, commercial OK, no attribution | Search "cinematic minimal piano", "ambient tech". Largest clean library. |
| **YouTube Audio Library** | Free; some tracks need attribution (shown per track) | Most tracks are licensed for use off YouTube too. Filter: Genre "Cinematic", Mood "Calm" or "Inspirational". |
| **Uppbeat** | Free with a credit line in the caption | Good curated cinematic tracks. The credit line is small; put it in the caption. |
| **Free Music Archive** | Per track, filter to CC BY or CC0 | Check each track. CC BY-NC tracks are not usable for a promo. |
| **Kevin MacLeod (incompetech.com)** | CC BY 4.0 | Overused on YouTube, so avoid the famous ones. |
| **TikTok Commercial Music Library** | Licensed for business accounts | If you post from a Business account you can only use this library, not trending sounds. If you post from a personal account using a trending sound to promote an app, you are technically outside the license. For an open-source free app this is a gray zone. Don't bet the launch on it. |

Practical path: find three candidate tracks on Pixabay, drop each under the rough cut, pick the one where the drop lands at 00:16.5 with the least time-stretching.

---

## Sound effects

| Moment | SFX | Spec |
|---|---|---|
| 00:00.2 hook text | Sub-bass hit | 40–60 Hz sine with a 400 ms exponential decay. Make it yourself in any DAW. Stock "cinematic boom" is too long and too bright. |
| 00:02.0 price cut | UI tick | Dry, short (30 ms), no reverb. |
| 00:03.5 "free" | Sub-bass hit | Same as the hook. |
| 00:06.0 Return key | Keyboard click | Record your actual MacBook keyboard with your phone 10 cm away. Stock typewriter sounds are a tell. |
| 00:12 – 00:16.5 | Riser | White-noise riser with a low-pass filter opening. 4.5 s. |
| 00:16.5 Apply cut | Whoosh + chime | Low whoosh (not airy, more like a door closing in reverse) layered with a soft bell or glass chime at low volume. The chime should be felt, not heard. |
| 00:18.5 – 00:21.5 catalog cuts | Air transients | Short breathy "pf" sounds, 50 ms, barely audible. They make hard cuts feel intentional. |
| 00:24.0 icon lands | Sub-bass hit | Same as the hook, slightly longer decay (600 ms). |

Free SFX: **Freesound.org** (filter License: Creative Commons 0), **Pixabay Sound Effects**, **Mixkit**. Avoid Zapsplat on the free tier unless you want to add their credit.

### Mix

- Loudness target −14 LUFS integrated (TikTok and Instagram normalize to roughly that; louder gets turned down and sounds squashed).
- Peaks at −1 dBTP.
- Music sits at −18 to −16 LUFS under VO or real audio, full −14 at the drop.
- High-pass everything except the sub hits at 80 Hz. Phone speakers can't reproduce it; it just eats headroom.
- Check the mix on a phone speaker before export. If the hook thump disappears, add a 120 Hz layer under it. Phone speakers render the harmonic, not the fundamental.

---

## Shooting checklist

**Mac prep**
- Clean desktop. Hide Dock (⌘⌥D), hide all desktop icons, turn off notifications (Focus mode).
- Screen brightness 70–80 %. At 100 % the camera clips the highlights.
- Terminal: dark theme, 18 pt font, window sized so the crop region is clean. Clear scrollback before each take.
- Pre-download the wallpapers you'll apply so the Apply moment is instant. The ad is about the apply, not the download.
- Record screen with ⌘⇧5 at native resolution. Not Zoom, not OBS defaults.

**Camera**
- Phone on a tripod. 4K60, manual exposure locked, shutter 1/60 (or 1/120 at 60 fps). Auto exposure will pump when the wallpaper changes and ruin the Apply shot.
- Slight angle to the screen (20–30°) kills reflections and moiré.
- Room: dark, one warm practical lamp behind or beside the Mac so the laptop has an edge. The screen is the key light on the desk.
- Wipe the screen. Fingerprints glow on camera.

**People**
- Film them on their own Mac, not yours. Get an on-camera "yes you can use this."
- Phone handheld, natural light, no setup. The contrast between the polished Mac shots and the raw reaction shots is what makes the reactions believable.

---

## Edit assembly notes

Crop a 16:9 4K screen recording to a vertical region (example: the Terminal line, centered) with ffmpeg:

```bash
# x,y = top-left of the 1080x1920 crop window inside the 3840x2160 recording
ffmpeg -i terminal.mov -vf "crop=1080:1920:1380:120" -c:v libx264 -crf 16 -r 30 terminal_v.mp4
```

Never scale a crop up more than 1.3×. If the region you need is too small at 4K, re-record with bigger UI (Terminal font size, or the app window smaller so tiles are larger).

Export: H.264, 1080×1920, 30 fps, 12–16 Mbps, AAC 256 kbps. Both platforms re-encode anyway; give them a clean source.

---

## Caption (post text)

Both platforms. Credits are required by the CC BY licenses of the clips shown.

> Live 4K wallpapers for your Mac. Free, open source, no account.
> One line in Terminal, about 10 seconds. Link in bio.
>
> Wallpapers shown: Crab Nebula and Pillars of Creation, NASA/ESA/CSA/STScI (CC BY 4.0); Carina Nebula, NASA/ESA/CSA/STScI (CC BY 4.0); Aurora Saguenay, 0x010C/Wikimedia Commons (CC BY-SA 4.0); Rialto Beach, Sea Cow/Wikimedia Commons (CC BY-SA 4.0); Midtown Manhattan, the Dronalist/Wikimedia Commons (CC BY 3.0).
> Music: [track] by [artist] via [source].
>
> #mac #macos #macbook #wallpaper #livewallpaper #opensource #macsetup #desksetup

Pin a comment with the raw GitHub link the moment it posts. Reply to the first ten comments within the hour; early engagement is weighted heavily on both platforms.

---

## Variants to test

Post the main cut, then within 48 hours post a second version with a different first 3.5 seconds. Same body. Whichever gets a higher 3-second hold rate becomes the one you push.

| Hook | S01 text | S02 |
|---|---|---|
| A (main) | Still paying for live wallpapers? | Blurred paywall |
| B (beauty first) | Your Mac can do this. | Skip S02, go straight to "This one's free." |
| C (dev bait) | I replaced a $30 app with 40 lines of bash. | Crop of `install.sh` scrolling, then "This one's free." |

Hook C will do best on dev TikTok and worst on general Instagram. Hook A is the safest across both. Hook B is the prettiest and will likely have the weakest hold rate because it has no tension.

---

## What will kill this video

- A speed-ramped install. The timer is the only proof you have. Don't touch it.
- Scripted "users." Cut the scene before you fake it.
- Apple Aerials on screen. Licensing problem and it isn't even your catalog.
- Screen recording with a blurred vertical background. Instantly reads as a cheap ad.
- Any transition that isn't a hard cut or a dip to black.
- Text that fades, slides, or bounces in. Cut it in on the frame. Let it sit.
- Lifted blacks or an orange/teal grade. Apple's look is neutral and dark.
- An end card with a 44-character URL as the only CTA.
