#!/bin/zsh
# Builds build/Hanging Charm.app. Pass --install to copy it to /Applications
# and (re)launch it.
set -euo pipefail
ROOT="${0:A:h:h}"
APP="$ROOT/build/Hanging Charm.app"

rm -rf "$ROOT/build"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Charms"

xcrun swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/HangingCharm"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp "$ROOT"/Resources/Charms/*.png "$APP/Contents/Resources/Charms/"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  if pkill -x HangingCharm 2>/dev/null; then sleep 0.6; fi
  rm -rf "/Applications/Hanging Charm.app"
  ditto "$APP" "/Applications/Hanging Charm.app"
  open "/Applications/Hanging Charm.app"
  echo "Installed and launched /Applications/Hanging Charm.app"
fi
