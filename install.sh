#!/bin/bash
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

# Lucid installer. Downloads the latest release, puts Lucid.app in /Applications and opens it.
# Source: https://github.com/jedbrnth-eng/lucid-live-wallpaper
set -euo pipefail

REPO="jedbrnth-eng/lucid-live-wallpaper"
URL="https://github.com/$REPO/releases/latest/download/Lucid.zip"
SUM_URL="$URL.sha256"
# HTTPS only, also across redirects (GitHub sends release downloads to its CDN).
CURL=(curl -fL --proto '=https' --proto-redir '=https' --tlsv1.2)

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Lucid is a Mac app. This installer only runs on macOS."
[ "$(uname -m)" = "arm64" ] || die "Lucid needs an Apple Silicon Mac (M1 or newer)."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 14 ] || die "Lucid needs macOS 14 (Sonoma) or newer. You have $(sw_vers -productVersion)."

DEST="/Applications"
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "Downloading Lucid..."
"${CURL[@]}" --progress-bar -o "$TMP/Lucid.zip" "$URL" || die "Download failed. Check your internet connection, or see the README to build from source."

# Releases from 1.3.0 on publish Lucid.zip.sha256 next to the zip. If it's there, the download must match it.
if "${CURL[@]}" -s -o "$TMP/Lucid.zip.sha256" "$SUM_URL" 2>/dev/null; then
  WANT="$(awk 'NR==1 {print $1}' "$TMP/Lucid.zip.sha256")"
  GOT="$(shasum -a 256 "$TMP/Lucid.zip" | awk '{print $1}')"
  [[ "$WANT" =~ ^[0-9a-f]{64}$ ]] || die "The checksum file looks wrong. Nothing was installed. Please open an issue."
  [ "$WANT" = "$GOT" ] || die "Checksum mismatch: the download is damaged or was changed. Nothing was installed."
  say "Checksum OK ($GOT)"
else
  say "No checksum published for this release (older than 1.3.0); continuing without it."
fi

say "Installing to $DEST..."
ditto -x -k "$TMP/Lucid.zip" "$TMP/out"
[ -d "$TMP/out/Lucid.app" ] || die "The download didn't contain Lucid.app. Please open an issue."

if pgrep -x Lucid >/dev/null 2>&1; then
  osascript -e 'tell application "Lucid" to quit' >/dev/null 2>&1 || true
  sleep 2
fi
rm -rf "$DEST/Lucid.app"
ditto "$TMP/out/Lucid.app" "$DEST/Lucid.app"
xattr -dr com.apple.quarantine "$DEST/Lucid.app" 2>/dev/null || true

say "Done. Opening Lucid..."
open "$DEST/Lucid.app"
echo
echo "Lucid is in $DEST. Look for it in Launchpad, and for the sparkles icon in your menu bar."
echo "To remove it later: rm -rf \"$DEST/Lucid.app\" \"\$HOME/Library/Application Support/Lucid\""
