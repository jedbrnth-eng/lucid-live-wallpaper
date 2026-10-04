#!/bin/bash
# Headless self-test: runs the real app with -selftest, waits for its JSON report.
cd "$(dirname "$0")"
S="$HOME/Library/Application Support/Lucid"
rm -f "$S/selftest.json"
"build/Lucid.app/Contents/MacOS/Lucid" -selftest YES >/tmp/jw-selftest.log 2>&1 &
PID=$!
for i in $(seq 1 90); do [ -f "$S/selftest.json" ] && break; sleep 1; done
sleep 1; kill $PID 2>/dev/null
if [ -f "$S/selftest.json" ]; then cat "$S/selftest.json"; else echo "NO REPORT"; tail -20 /tmp/jw-selftest.log; fi
