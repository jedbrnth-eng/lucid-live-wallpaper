# GitHub release fixtures

`releases-latest.json`: the real response of `GET https://api.github.com/repos/jedbrnth-eng/lucid-live-wallpaper/releases/latest`
recorded on 2026-10-26 (then v1.1.1), trimmed to the fields Lucid reads plus a few neighbours (author/uploader objects removed).
`UpdateCheckTests.swift` parses it offline.
