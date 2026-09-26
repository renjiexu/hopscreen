#!/bin/bash
# Builds build/Hopscreen.app (ad-hoc signed unless SIGN_IDENTITY is set).
#   scripts/build.sh            build only
#   scripts/build.sh --install  build, copy to /Applications and launch
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
APP=build/Hopscreen.app

rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 Sources/*.swift -o "$APP/Contents/MacOS/Hopscreen" \
  -framework AppKit -framework IOKit -framework Carbon -framework ServiceManagement
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns ]]; then
  swift scripts/make-icon.swift
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $APP ($VERSION)"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Hopscreen || true
  rm -rf /Applications/Hopscreen.app
  cp -R "$APP" /Applications/
  open /Applications/Hopscreen.app
  echo "Installed /Applications/Hopscreen.app"
fi
