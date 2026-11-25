#!/bin/sh

set -eu

# This script is used to build the TrollSpeed app and create a tipa file with Xcode.

# Read the version from the existing control file
VERSION=$(./get-version.sh) || exit 1

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
cd TrollSpeed.xcarchive/Products/Applications || exit
codesign --remove-signature TrollSpeed.app
cd - || exit
cd TrollSpeed.xcarchive/Products || exit
mv Applications Payload
ldid -Sentitlements.plist Payload/TrollSpeed.app
chmod 0644 Payload/TrollSpeed.app/Info.plist
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
mv TrollSpeed.xcarchive/Products/TrollSpeed.tipa "packages/$PACKAGE_NAME.tipa"
