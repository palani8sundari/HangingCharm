#!/bin/zsh
# Renders Art/*.html into Resources/ (charm PNGs at 4x, and AppIcon.icns).
# Needs Google Chrome. Only rerun this when you change the artwork.
set -euo pipefail
ROOT="${0:A:h:h}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT="$ROOT/Resources/Charms"
mkdir -p "$OUT"

shoot() { # url width height out
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size="$2,$3" --screenshot="$4" "$1" >/dev/null 2>&1
}

typeset -A HEIGHTS=(nazar 106 hamsa 142 nimbu 90 ghanta 118 bommai 164 panchang 148 daruma 116)
for id h in ${(kv)HEIGHTS}; do
  shoot "file://$ROOT/Art/charms.html#$id" 480 $((h * 4)) "$OUT/$id.png"
  echo "charm  $id.png  480x$((h * 4))"
done

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
shoot "file://$ROOT/Art/icon.html" 1024 1024 "$ICONSET/icon_512x512@2x.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "icon   AppIcon.icns"
