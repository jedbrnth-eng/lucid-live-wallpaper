#!/bin/bash
# Build "Lucid.app" from Lucid.swift (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Lucid.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx14.0 \
  -framework SwiftUI -framework AppKit -framework AVKit -framework AVFoundation \
  -framework IOKit -framework ServiceManagement -framework Security \
  Lucid.swift -o "$APP/Contents/MacOS/Lucid"
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ ! -f catalog.json ] || cp catalog.json "$APP/Contents/Resources/catalog.json"
codesign --force --deep --sign - "$APP" >/dev/null
echo "Built: $APP"
