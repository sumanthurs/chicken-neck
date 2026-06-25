#!/usr/bin/env bash
# Builds Chicken Neck into a runnable, ad-hoc signed .app bundle.
#
# Usage:
#   ./build.sh [debug|release]
#
# Signing:
#   The app is ad-hoc signed (free, local use). Camera access works with just
#   NSCameraUsageDescription + the macOS TCC prompt, so no special entitlement
#   is needed. For distribution, set SIGN_IDENTITY to a Developer ID.
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="ChickenNeck"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SWIFT_FLAGS=(-c "$CONFIG" --disable-sandbox)

BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"
echo "› Compiling ($CONFIG)…"
swift build "${SWIFT_FLAGS[@]}"

APP_BUNDLE="$BIN_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
echo "› Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    echo "› Code signing with: $SIGN_IDENTITY"
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "› Code signing (ad-hoc)"
    codesign --force --sign - "$APP_BUNDLE"
fi

echo "✓ Built $APP_BUNDLE"
echo "  Run it with:  open \"$APP_BUNDLE\""
