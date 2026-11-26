#!/bin/sh

set -eu

# This script is used to build the TrollSpeed app and create a tipa file with Xcode.

# Read the version from the existing control file. Use sh so a fresh checkout
# still works when the executable bit was not preserved.
VERSION=$(sh ./get-version.sh) || exit 1

echo "Using version: $VERSION"

# Set GITHUB_WORKSPACE to home directory if not set
if [ -z "${GITHUB_WORKSPACE:-}" ]; then
    GITHUB_WORKSPACE="$HOME"
fi

# Set THEOS to the correct path
THEOS="$GITHUB_WORKSPACE/theos-roothide"
if [ ! -d "$THEOS" ]; then
    THEOS="$GITHUB_WORKSPACE/theos"
fi

# Build using Xcode. Keep the complete output so archive failures are not
# hidden by an optional formatter that may not be installed.
BUILD_DIR=".build"
BUILD_LOG="$BUILD_DIR/xcodebuild.log"
mkdir -p "$BUILD_DIR"

rm -rf TrollSpeed.xcarchive

BUILD_STATUS=0
if xcodebuild clean build archive \
-scheme TrollSpeed \
-project TrollSpeed.xcodeproj \
-configuration Release \
-sdk iphoneos \
-destination 'generic/platform=iOS' \
-archivePath TrollSpeed \
-derivedDataPath "$BUILD_DIR/DerivedData" \
CODE_SIGNING_ALLOWED=NO \
IPHONEOS_DEPLOYMENT_TARGET=16.0 \
THEOS="$THEOS" >"$BUILD_LOG" 2>&1; then
    :
else
    BUILD_STATUS=$?
fi
cat "$BUILD_LOG"
if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "Error: xcodebuild failed with status $BUILD_STATUS" >&2
    exit "$BUILD_STATUS"
fi

chmod 0644 Resources/Info.plist
cp supports/entitlements.plist TrollSpeed.xcarchive/Products
cd TrollSpeed.xcarchive/Products
codesign --remove-signature Applications/TrollSpeed.app 2>/dev/null || true
mv Applications Payload
ldid -Sentitlements.plist Payload/TrollSpeed.app
if ! ldid -e Payload/TrollSpeed.app/TrollSpeed | grep -q "com.apple.springboard.accessibility-window-hosting"; then
    echo "Error: entitlements are missing from the signed binary" >&2
    exit 1
fi
chmod 0644 Payload/TrollSpeed.app/Info.plist
rm -f TrollSpeed.tipa
zip -qr TrollSpeed.tipa Payload
cd - || exit
mkdir -p packages
PACKAGE_NAME="TrollSpeed+AppIntents16_$VERSION"
if [ -n "${IK_SUFFIX:-}" ]; then
    case "$IK_SUFFIX" in
        *[!A-Za-z0-9._-]*) echo "Error: IK_SUFFIX contains unsupported characters" >&2; exit 1 ;;
    esac
    PACKAGE_NAME="$PACKAGE_NAME-$IK_SUFFIX"
fi
OUTPUT="packages/$PACKAGE_NAME.tipa"
mv TrollSpeed.xcarchive/Products/TrollSpeed.tipa "$OUTPUT"
echo "Packaged: $OUTPUT"
