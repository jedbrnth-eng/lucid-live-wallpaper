# DRAFT Homebrew cask for Lucid. Not published anywhere yet.
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper
#
# Before use: replace the sha256 with the value from Lucid.zip.sha256 attached to the v<version> release
# (`shasum -a 256 Lucid.zip`), then `brew audit --cask --new ./lucid.rb` and `brew install --cask ./lucid.rb`.
# See packaging/README.md for why this belongs in a personal tap, not homebrew/cask, while Lucid is unnotarized.
cask "lucid" do
  version "1.3.0"
  sha256 "REPLACE_WITH_SHA256_OF_Lucid.zip"

  url "https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/download/v#{version}/Lucid.zip"
  name "Lucid"
  desc "Live 4K video wallpapers"
  homepage "https://github.com/jedbrnth-eng/lucid-live-wallpaper"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "Lucid.app"

  uninstall quit: "com.jedbrn.lucid"

  zap trash: [
    "~/Library/Application Support/Lucid",
    "~/Library/Preferences/com.jedbrn.lucid.plist",
  ]
end
