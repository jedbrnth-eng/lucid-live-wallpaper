#!/bin/bash
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

# Runs the dev check (-lucidCheck) the way a developer or an agent would, and fails if it puts any window on screen,
# changes a desktop picture or calls the Keychain. Watched from outside the app:
#   windows   tools/headless/window-watch.m polls the window server every 50 ms for on-screen windows of the check
#   Keychain  tools/headless/keychain-tripwire.c is loaded into the check (DYLD_INSERT_LIBRARIES) and answers every
#             Keychain call with "not found" and logs it, so even a broken check never reads it or makes macOS ask
# Usage: ./build.sh && ./headless-check.sh     (LUCID_CHECK_VIDEO=<file> adds the video checks)
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Lucid.app/Contents/MacOS/Lucid"
[ -x "$APP" ] || { echo "Build first: ./build.sh"; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lucid-headless.XXXXXX")"
clang -O1 -dynamiclib -framework Security -framework CoreFoundation tools/headless/keychain-tripwire.c -o "$WORK/tripwire.dylib"
clang -O1 -fobjc-arc -framework AppKit -framework CoreGraphics tools/headless/window-watch.m -o "$WORK/window-watch"
mkdir -p "$WORK/support"
LOG="$WORK/keychain.log"; : > "$LOG"

LUCID_SUPPORT_DIR="$WORK/support" LUCID_TRIPWIRE_LOG="$LOG" DYLD_INSERT_LIBRARIES="$WORK/tripwire.dylib" \
  "$APP" -lucidCheck YES > "$WORK/check.out" 2>&1 &
PID=$!
watch_rc=0; "$WORK/window-watch" "$PID" 300 > "$WORK/windows.txt" || watch_rc=$?
grep -q "timed_out=yes" "$WORK/windows.txt" && kill -9 "$PID" 2>/dev/null
check_rc=0; wait "$PID" || check_rc=$?

fail=0
cat "$WORK/windows.txt"
[ "$watch_rc" -eq 0 ] || { echo "FAIL  windows: the check put a window on screen, changed a desktop picture or hung (see above)"; fail=1; }
if ! grep -q "^loaded pid=$PID\$" "$LOG"; then
  echo "FAIL  Keychain tripwire was not loaded into the check (pid $PID), so Keychain use can't be ruled out"; fail=1
elif grep -q "^Sec" "$LOG"; then
  echo "FAIL  Keychain: the check made $(grep -c '^Sec' "$LOG") Keychain call(s):"; grep "^Sec" "$LOG" | sort | uniq -c; fail=1
else
  echo "PASS  Keychain: tripwire loaded, 0 calls"
fi
[ "$check_rc" -eq 0 ] || { echo "FAIL  the check exited with $check_rc"; tail -20 "$WORK/check.out"; fail=1; }
[ -s "$WORK/support/check.json" ] || { echo "FAIL  no check.json (the check did not finish)"; fail=1; }
[ "$watch_rc" -eq 0 ] && echo "PASS  windows: none on screen, desktop pictures unchanged"
echo "Results in $WORK (check.json, windows.txt, keychain.log)"
exit $fail
