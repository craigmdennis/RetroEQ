#!/bin/bash
# Builds build/RetroEQ.app. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/RetroEQ.app
swift build -c release
BIN="$(swift build -c release --show-bin-path)/RetroEQ"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RetroEQ"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon (generated once, then cached in build/).
if [ ! -f build/AppIcon.icns ]; then
  ICONSET=build/AppIcon.iconset
  mkdir -p "$ICONSET"
  swift Scripts/make-icon.swift build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Signing. SIGN_IDENTITY overrides; otherwise prefer a Developer ID Application
# certificate for TEAM_ID, then an Apple Development certificate for TEAM_ID.
TEAM_ID="${TEAM_ID:-C56P94M635}"
find_identity() {
  local kind="$1"
  security find-identity -v -p codesigning | grep -v CSSMERR | { grep "$kind" || true; } | awk '{print $2}' | while read -r hash; do
    ou=$(security find-certificate -a -Z -p | awk -v h="$hash" '/SHA-1 hash:/{f=($3==h)} f' \
      | sed -n '/BEGIN/,/END/p' | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')
    if [ "$ou" = "$TEAM_ID" ]; then echo "$hash"; break; fi
  done
}
IDENTITY="${SIGN_IDENTITY:-$(find_identity 'Developer ID Application')}"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --timestamp --entitlements Resources/RetroEQ.entitlements --sign "$IDENTITY" "$APP"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    ditto -c -k --keepParent "$APP" build/RetroEQ.zip
    xcrun notarytool submit build/RetroEQ.zip --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
  fi
else
  IDENTITY="$(find_identity 'Apple Development')"
  codesign --force --sign "${IDENTITY:--}" "$APP"
fi
echo "Signed with: ${IDENTITY:-ad-hoc} (team $TEAM_ID)"

if [ "${1:-}" = "--install" ]; then
  pkill -x RetroEQ 2>/dev/null && sleep 0.5 || true
  rm -rf /Applications/RetroEQ.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/RetroEQ.app"
fi
echo "Built $APP"
