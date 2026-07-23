#!/bin/bash
# Package AgentStick.app into a signed and optionally notarized DMG.
#
# Usage:
#   scripts/make-dmg.sh
#   scripts/make-dmg.sh build/AgentStick-<version>.app
#   scripts/make-dmg.sh build/AgentStick-<version>.app build/AgentStick-<version>.dmg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
BUILD_DIR="$ROOT_DIR/build"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_PATH="${1:-$BUILD_DIR/AgentStick-${VERSION}.app}"
OUTPUT="${2:-$BUILD_DIR/AgentStick-${VERSION}.dmg}"
STAGING_DIR="$BUILD_DIR/.dmg-staging"
VOLUME_NAME="AgentStick"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Application bundle not found: $APP_PATH"
    exit 1
fi

APP_EXECUTABLE="$APP_PATH/Contents/MacOS/AgentStickApp"
SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [ ! -x "$APP_EXECUTABLE" ]; then
    echo "Error: Application executable not found: $APP_EXECUTABLE"
    exit 1
fi
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "Error: Bundled Sparkle.framework not found: $SPARKLE_FRAMEWORK"
    exit 1
fi
if ! otool -l "$APP_EXECUTABLE" | grep -Fq '@loader_path/../Frameworks'; then
    echo "Adding bundled Frameworks runtime search path..."
    install_name_tool -add_rpath "@loader_path/../Frameworks" "$APP_EXECUTABLE"
fi
if ! otool -l "$APP_EXECUTABLE" | grep -Fq '@loader_path/../Frameworks'; then
    echo "Error: bundled Frameworks runtime search path is missing."
    exit 1
fi

CODESIGN_IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    CODESIGN_IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')"
fi

echo "Signing app before DMG packaging..."
xattr -cr "$APP_PATH" 2>/dev/null || true
if [ "$CODESIGN_IDENTITY" != "-" ]; then
    echo "Using: $CODESIGN_IDENTITY"
    codesign --deep --force --options runtime --sign "$CODESIGN_IDENTITY" "$APP_PATH"
else
    echo "Using ad-hoc signature."
    codesign --deep --force --sign - "$APP_PATH"
fi

echo "Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -rf "$STAGING_DIR" "$OUTPUT"
mkdir -p "$STAGING_DIR"
ditto --norsrc --noextattr "$APP_PATH" "$STAGING_DIR/AgentStick.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating DMG..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT"
rm -rf "$STAGING_DIR"

if xcrun notarytool history --keychain-profile "AC_PASSWORD" >/dev/null 2>&1; then
    echo "Submitting DMG for notarization..."
    xcrun notarytool submit "$OUTPUT" --keychain-profile "AC_PASSWORD" --wait
    xcrun stapler staple "$OUTPUT"
else
    echo "Skipping notarization: keychain profile AC_PASSWORD was not found."
fi

echo "DMG complete: $OUTPUT"
