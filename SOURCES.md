# Wallpaper content sources for a personal 4K macOS wallpaper app

Researched 2026-10-02. "Live" means a keyless call was made during this research. Key-gated APIs (Pexels, Pixabay, Unsplash, Coverr) were **not** called with keys. For those, the facts come only from official docs.

## Summary

| Source | 4K static | 4K video | Auth | Guarantee 4K via | Verdict |
|---|---|---|---|---|---|
| Apple Aerials | – | Yes (HEVC 3840×2160) | None | `url-4K-SDR(-240FPS)` key | **MEETS** (video). License is a grey area; use the Mac's own copy, don't redistribute |
| Wikimedia Commons | Yes | Some (~19.5k files) | None | `filew:>3839 fileh:>2159` + `imageinfo.width/height` | **MEETS**. Per-file licences, so attribution is often required |
| Pexels | Yes | Yes | Free key | photo `width/height` + `src.original`; video `size=large` + `video_files[].width/height` | **PARTIAL**. API terms ban "wallpaper app" use |
| Pixabay | Only with approved full API access | Yes (often) | Free key | `imageWidth` + `imageURL` (approval needed); `videos.large.width` | **PARTIAL**. Photos stop at 1280 px without approval |
| Unsplash | Yes | No video | Free key | `width/height` + `urls.raw`/`urls.full` | **FAILS** for this use. Guidelines ban wallpaper apps, and hotlinking plus download tracking are mandatory |
| NASA Images | Some | Some | None | `links[rel=canonical].width/height`; asset `metadata.json` | **MEETS** (curated subset). Public domain in general |
| Coverr | – | Not verified | Free key (account) | not verified | **PARTIAL**. Only a 50 req/h demo tier, logo attribution required |
| Mixkit | – | Yes (site has a "4K Videos" section) | No public API found | manual | **PARTIAL**. Manual download only; check Free vs Restricted licence per clip |
| Backdrop library | – | – | Subscriber app | – | **FAILS**. Proprietary/community catalog; not usable outside Backdrop |

## Per-source findings

### 1. Apple Aerials (sylvan.apple.com)
- **4K:** The public `resources-16.tar` contains `entries.json` with 114 assets that have `url-4K-SDR` and `url-4K-HDR` keys pointing to `…_SDR_4K_HEVC.mov` files.[1] A live `HEAD` request for one of them returned `200`, `video/quicktime`, ~347 MB, with no auth.[1] The Mac's local `idleassetsd` entries.json (138 assets, `url-4K-SDR-240FPS`) is the newer catalog. Treat any key containing `4K` as ≥3840×2160 and confirm with ffprobe.
- **Auth/limits:** None. No documented rate limit.
- **License:** I found no public licence for the Aerial videos. They come with macOS, and the macOS SLA grants use "for personal, non-commercial use" of the Apple Software on Macs you own.[2] Showing them as your own wallpaper on your own Mac is consistent with that. Redistributing them, or bundling them in a shared app, is not. That reading is my inference.
- **Verdict: MEETS 4K bar (video only).** Low risk for personal use. Prefer files macOS has already downloaded, and never re-host them.

### 2. Wikimedia Commons
- **4K:** Live API calls with `filew:>3839 fileh:>2159` returned 48,825,851 hits for `filetype:bitmap` and 19,563 for `filetype:video`.[3] Use `prop=imageinfo&iiprop=url|size|extmetadata` to get `width`, `height`, `url` (original file) and `extmetadata.LicenseShortName` / `Artist`.[3] Sample result: 5898×3443, CC BY-SA 4.0.[3]
- **Auth/limits:** None. There is no hard read limit, but requests should be sent in series, and the client needs an informative User-Agent or it risks an IP block.[5]
- **License:** The licence differs per file. Reusers must follow it, which usually means attribution and sometimes share-alike for modifications. Public-domain files still benefit from attribution.[4] Commons explicitly allows you to "Download or hotlink the file".[4]
- **Verdict: MEETS.** Store and display `Artist` + `LicenseShortName` for every file. Filter to CC0/PD/CC BY(-SA).

### 3. Pexels (photos + videos)
- **4K:** Photo `width`/`height` give "the real width of the photo in pixels", and `src.original` is the full file. Search supports `size=large` (24 MP).[6] For video, `size=large` means 4K, and each `video_files[]` entry has `width`, `height`, `fps`, `link` and `quality`.[6] Choose the entry with `width>=3840`.
- **Auth/limits:** A free API key is required. Without one, a live call returned `401`. The default limit is 200 requests/hour and 20,000/month.[6] Rate-limit increases are "currently paused".[8]
- **License:** The licence is free and needs no attribution. It does forbid redistributing content "on other stock photo or wallpaper platforms".[7] The API guidelines require a prominent Pexels link and photographer credit, and say: "You may not copy or replicate core functionality of Pexels (including making Pexels content available as a wallpaper app)."[6]
- **Verdict: PARTIAL.** The content meets 4K, but the API terms target wallpaper apps by name. A private, single-user tool is a grey area. Safest: use it manually or sparingly, with credit in the UI, and never ship it publicly.

### 4. Pixabay (photos + videos)
- **4K photos:** `largeImageURL` is a "scaled image with a maximum width/height of 1280px". `fullHDURL` (1920 px), `imageURL` (original) and `imageWidth`/`imageHeight` are "only available if your account has been approved for full API access".[9] Without approval, the API cannot deliver 4K stills. `min_width`/`min_height` filters exist.[9]
- **4K video:** `videos.large` "usually has a dimension of 3840x2160". If it is missing, the API returns an empty URL and size 0.[9] The docs' own example `large` is 1920×1080, so check `videos.large.width>=3840`.[9]
- **Auth/limits:** A free key is required. Without one, a live call returned `400 Invalid or missing API key`. The limit is 100 requests/60 s, and results must be cached for 24 h. "Systematic mass downloads are not allowed", and permanent hotlinking is forbidden, so download files first.[9]
- **License:** Free, no attribution required.[10] Standalone redistribution is prohibited, "as a print, wallpaper, poster…".[11] The API asks you to show users where content comes from.[9]
- **Verdict: PARTIAL.** Video meets the bar when filtered. Stills fail at 1280 px unless full API access is approved.

### 5. Unsplash
- **4K:** Responses include `width`/`height` (e.g. 5245×3497). `urls.full` is the maximum size, and `urls.raw` is a base URL you can add `w=`/`dpr=` parameters to.[12] There is no video.
- **Auth/limits:** A free key is required. Without one, a live call returned an OAuth error. Demo apps get 50 requests/hour; production gets 1,000/hour after approval.[12]
- **API terms:** You must use the hotlinked `photo.urls`. You must call `links.download_location` when the user does something "similar to a download (… set as a header …)". You must credit the photographer and Unsplash with UTM links. And: "You cannot replicate the core user experience of Unsplash (unofficial clients, wallpaper applications, etc.)".[13] Hotlinking is required, not optional.[12]
- **License:** Free and no attribution needed, but it bars "compil[ing] photos from Unsplash to replicate a similar or competing service".[14] (The current licence page was bot-walled, so this comes from the archived copy.)
- **Verdict: FAILS for this use.** Wallpaper apps are explicitly banned, and the hotlink requirement conflicts with offline caching. Hand-downloading individual photos through the website under the licence is fine.

### 6. NASA Image and Video Library
- **4K:** A live `search?media_type=image` call returned the `rel:"canonical"` (`~orig`) link with `width`/`height`. In a 100-item "earth" sample, 33 of the 92 canonical links with dimensions were ≥4K.[15] For video, the asset manifest lists `~orig.mp4`/`~large.mp4`,[16] and `metadata.json` exposes `QuickTime:ImageWidth`/`ImageHeight`. Live check: "4K Earth Views" is 3840×2160, 52 min long.[18]
- **Auth/limits:** None for images-api.nasa.gov (live calls worked keyless). I found no documented rate limit.
- **License:** NASA content "generally [is] not subject to copyright in the United States". It must not imply endorsement, NASA "should be acknowledged as the source", and third-party copyrighted items are marked and excluded from this permission.[17]
- **Verdict: MEETS** for a curated space/Earth subset. Check dimensions and skip files marked as copyrighted.

### 7. Coverr (video)
- **API:** Requires an API key from a free Coverr account.[24] The Demo tier allows 50 requests/hour; the 2,000/hour Production tier needs a paid Pro/Ultimate plan.[23] API users must show a clickable Coverr logo.[22]
- **License:** Free, no attribution. It forbids building a "similar or competing service" and AI training.[21]
- **4K:** Not verified. The videos schema docs page returned 404 and I made no keyed call.
- **Verdict: PARTIAL / unverified.** A possible supplement only.

### 8. Mixkit (video, Envato)
- **License:** Clips under the Free License may be downloaded, copied and modified without attribution.[19] Clips under the Restricted License are for personal projects only, which still covers a personal wallpaper.[20]
- **API:** I found no public API. Download manually.
- **Verdict: PARTIAL.** Good hand-curated 4K loops, but no programmatic access.

*Videvo:* licence pages returned 403/404 during research, so it was not assessed.

## Backdrop (Cindori) library
Backdrop's catalog is "thousands of animated wallpapers created and shared by the [Backdrop] community". Without a purchase, the trial is limited to three watermarked Backdrops. Paying "unlocks unlimited access to the entire Backdrop community platform".[25] Cindori's guide says Backdrop's review is not "a universal copyright guarantee" and that uploaders need redistribution rights.[27] Submissions go into "the public Backdrop collection".[28] I found no general Terms of Use that grant rights to the library. The only published EULA covers the software and says all copyrights in it belong to Cindori AB.[26]

**Bottom line:** the library is a subscriber feature of Cindori's service, and neither Cindori nor the individual uploaders have granted any rights outside it. Do not extract, cache or reuse Backdrop videos (including the ones it injects into the Aerials `entries.json`) in the new app. Only clips Jed made himself can carry over.

## Recommended stack
Apple Aerials (from local macOS) + NASA + Wikimedia Commons (licence-filtered, attributed) as keyless 4K sources. Use Pixabay video (`videos.large.width>=3840`) only if Jed accepts getting a free key. Pull Mixkit clips in by hand. Avoid automated Unsplash or Pexels ingestion.

## Sources

[1] https://sylvan.apple.com/Aerials/resources-16.tar — Apple Aerials resources-16.tar (entries.json)
[2] https://www.apple.com/legal/sla/docs/macOSSequoia.pdf — macOS Sequoia SLA
[3] https://commons.wikimedia.org/w/api.php — Wikimedia Commons API (live call)
[4] https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia — Commons: Reusing content outside Wikimedia
[5] https://www.mediawiki.org/wiki/API:Etiquette — MediaWiki API Etiquette
[6] https://www.pexels.com/api/documentation — Pexels API documentation
[7] https://www.pexels.com/license — Pexels License
[8] https://help.pexels.com/hc/en-us/articles/900005852323-How-do-I-get-unlimited-requests — Pexels: unlimited requests
[9] https://pixabay.com/api/docs — Pixabay API docs
[10] https://pixabay.com/service/license-summary — Pixabay Content License summary
[11] https://pixabay.com/service/terms — Pixabay Terms
[12] https://unsplash.com/documentation — Unsplash API documentation
[13] https://help.unsplash.com/en/articles/2511245-unsplash-api-guidelines — Unsplash API Guidelines
[14] https://web.archive.org/web/20201009115655/https:/unsplash.com/license — Unsplash License (archived)
[15] https://images-api.nasa.gov/search — NASA Images API (live call)
[16] https://images.nasa.gov/docs/images.nasa.gov_api_docs.pdf — NASA Images API docs
[17] https://www.nasa.gov/nasa-brand-center/images-and-media — NASA Images and Media Usage Guidelines
[18] https://images-assets.nasa.gov/video/jsc2021m000138_4K_Earth_Views_Extended_Cut_for_Earth_Day_%202021_210422-4KMP4/metadata.json — NASA 4K Earth Views metadata.json
[19] https://mixkit.co/license/modal/videoFree — Mixkit Stock Video Free License
[20] https://mixkit.co/license/modal/videoRestricted — Mixkit Stock Video Restricted License
[21] https://coverr.co/license — Coverr License
[22] https://api.coverr.co/docs — Coverr API: Before you start
[23] https://api.coverr.co/docs/start — Coverr API: access & quotas
[24] https://api.coverr.co/docs/auth — Coverr API: Authentication
[25] https://cindori.com/backdrop — Backdrop product page
[26] https://cindori.com/support/order/legal/license-agreement — Cindori EULA
[27] https://cindori.com/how-to/backdrop-community-wallpaper-platform-guide — Cindori: Backdrop community platform guide
[28] https://cindori.com/support/backdrop/general/publishing-wallpapers — Cindori: Publishing wallpapers
