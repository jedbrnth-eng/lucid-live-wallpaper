#!/bin/bash
# Records the Lucid one-line install in a clean Terminal window, with nothing personal on screen.
# Run this on your Mac:   bash marketing/record_install.sh
# Output: ~/Desktop/lucid-install.mov (screen recording) and ~/Desktop/lucid-install.log (timings)
#
# What it does, in order:
#   1. Opens a NEW Terminal window running a bare zsh (no rc files, no history, prompt is just "$ ").
#      Your username, hostname, folders and shell theme never appear.
#   2. Sizes that window to a clean 16:10 rectangle and records exactly that region for 25 seconds
#      with macOS's built-in screencapture (no third-party app, nothing else on screen is captured).
#   3. Runs the real install line. Yes, it re-downloads Lucid.zip: that download IS the install, and
#      it's the only honest footage of "one line, ten seconds". It replaces /Applications/Lucid.app in
#      place and keeps all your settings, downloads and favorites (they live in ~/Library/Application
#      Support/Lucid, which the installer does not touch). Lucid is quit and relaunched by the installer.
#   4. Writes start/end epoch times to the log so the stopwatch can be burned in accurately in post.
#
# Before running: close anything you don't want behind the Terminal window (the region recorded is
# only the Terminal window itself, but keep the desktop clean anyway), and make sure Screen Recording
# permission is granted to Terminal in System Settings > Privacy & Security.
set -euo pipefail

OUT="$HOME/Desktop/lucid-install.mov"
LOG="$HOME/Desktop/lucid-install.log"
SECS=25
X=120; Y=120; W=1280; H=800          # window region, points

# A tiny script the clean shell will run, from a temp file so nothing personal is typed on screen.
DEMO="$(mktemp -t lucid-demo).sh"
cat > "$DEMO" <<'INNER'
printf '\033]0;Terminal\007'          # neutral window title
export PROMPT='$ ' PS1='$ '
unset HISTFILE
clear
sleep 2.5                             # let the recording settle on an empty prompt
printf '$ '
CMD='curl -fsSL https://raw.githubusercontent.com/jedbrnth-eng/lucid-live-wallpaper/main/install.sh | bash'
# "type" the command so the viewer sees it appear, then run it
for ((i=0;i<${#CMD};i++)); do printf '%s' "${CMD:$i:1}"; sleep 0.012; done
sleep 0.6; printf '\n'
date +%s.%N > "$HOME/Desktop/lucid-install.log"
curl -fsSL https://raw.githubusercontent.com/jedbrnth-eng/lucid-live-wallpaper/main/install.sh | bash
date +%s.%N >> "$HOME/Desktop/lucid-install.log"
printf '$ '
sleep 6
INNER
chmod +x "$DEMO"

# Open a new Terminal window with a bare shell, size it, and bring it to the front.
osascript <<APPLESCRIPT
tell application "Terminal"
  activate
  set w to do script "exec /bin/zsh -f -c 'source $DEMO'"
  delay 0.5
  set bounds of front window to {$X, $Y, $((X+W)), $((Y+H))}
  set font size of front window to 18
end tell
APPLESCRIPT

sleep 1
echo "Recording $SECS seconds to $OUT ..."
screencapture -V "$SECS" -R "$X,$Y,$W,$H" -x "$OUT"
echo "Done. Video: $OUT   Timings: $LOG"
echo "Send both files back and the stopwatch gets burned in from the log."
rm -f "$DEMO"
