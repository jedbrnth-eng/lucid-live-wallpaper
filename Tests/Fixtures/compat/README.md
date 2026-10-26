# Saved-data fixtures

Saved files as written by a 1.2.0 development build that still had the (since removed) Wallpaper Engine sync.
They contain items and assignments Lucid no longer understands (source `wallpaperEngine`, kind `web`).
`ModelCompatTests.swift` checks Lucid drops just those entries and keeps everything else.

`1.1.1-*.json` and `1.2.0-*.json` were written by the real model code of those versions (`git show v1.1.1:Sources/Lucid/Core/Models.swift`,
and the 1.2.0 models at commit ed0e740), compiled with a small writer program, so they are byte-for-byte what those versions save.
Paths in them are made up (`/Users/example/...`, `/tmp/...`).
