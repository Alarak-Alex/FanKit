#!/bin/bash
# Builds FanKit.app from the Swift package.
#
# The package produces plain executables. This script assembles them into a
# bundle: the app, the privileged helper, the Info.plist, and an icon if one is
# present. Signing is ad-hoc so the bundle launches on this machine.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="FanKit"
BUILD_DIR="$ROOT/.build/$CONFIG"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" \
         "$APP/Contents/Library/Helper" \
         "$APP/Contents/Resources"

cp "$BUILD_DIR/FanKit" "$APP/Contents/MacOS/$APP_NAME"
cp "$BUILD_DIR/FanKitHelper" "$APP/Contents/Library/Helper/FanKitHelper"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Localized strings live next to the binary so Bundle.main can find them.
for lproj in "$ROOT"/Resources/*.lproj; do
  [ -d "$lproj" ] || continue
  cp -R "$lproj" "$APP/Contents/Resources/"
done


if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

chmod +x "$APP/Contents/MacOS/$APP_NAME" "$APP/Contents/Library/Helper/FanKitHelper"

# Ad-hoc signing keeps the bundle coherent for local use. A Developer ID
# signature would be required to notarise it for distribution.
echo "==> Signing (ad hoc)"
codesign --force --deep --sign - "$APP" 2>/dev/null || \
  echo "warning: ad-hoc signing failed; the app may still launch locally"

echo "==> Done: $APP"
