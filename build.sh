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

# Headless hosts may not have the simulator service actool uses even for iphoneos.
# In that case package explicit device-sized PNG icons from the same master.
set --
if [ "${IK_PNG_ICONS:-0}" = 1 ]; then
    set -- "EXCLUDED_SOURCE_FILE_NAMES=Assets.xcassets" "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS=NO"
fi

BUILD_STATUS=0
if xcodebuild archive \
-scheme TrollSpeed \
-project TrollSpeed.xcodeproj \
-configuration Release \
-sdk iphoneos \
-destination 'generic/platform=iOS' \
-archivePath TrollSpeed \
-derivedDataPath "$BUILD_DIR/DerivedData" \
CODE_SIGNING_ALLOWED=NO \
IPHONEOS_DEPLOYMENT_TARGET=16.0 \
THEOS="$THEOS" "$@" >"$BUILD_LOG" 2>&1; then
    :
else
    BUILD_STATUS=$?
fi
cat "$BUILD_LOG"
if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "Error: xcodebuild failed with status $BUILD_STATUS" >&2
    exit "$BUILD_STATUS"
fi

if [ "${IK_PNG_ICONS:-0}" = 1 ]; then
    APP_PATH=TrollSpeed.xcarchive/Products/Applications/TrollSpeed.app
    python3 - "$APP_PATH" <<'PYICONS'
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1])
icons = {"Island60@2x": 120, "Island60@3x": 180, "Island76": 76,
         "Island76@2x": 152, "Island83.5@2x": 167}
for name, size in icons.items():
    subprocess.run(["sips", "-z", str(size), str(size), "Resources/icon.png", "--out",
                    str(app / (name + ".png"))], check=True, stdout=subprocess.DEVNULL)
path = app / "Info.plist"
info = plistlib.loads(path.read_bytes())
info.pop("CFBundleIconName", None)
for key, names in [("CFBundleIcons", ["Island60"]), ("CFBundleIcons~ipad", ["Island76", "Island83.5"])]:
    info[key] = {"CFBundlePrimaryIcon": {"CFBundleIconFiles": names}}
path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
PYICONS
fi
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
# 安装包按“灵动岛美化_版本号”命名，版本号取 App 自己的 CFBundleShortVersionString
APP_VERSION=$(plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist) || exit 1
PACKAGE_NAME="灵动岛美化_$APP_VERSION"
if [ -n "${IK_SUFFIX:-}" ]; then
    case "$IK_SUFFIX" in
        *[!A-Za-z0-9._-]*) echo "Error: IK_SUFFIX contains unsupported characters" >&2; exit 1 ;;
    esac
    PACKAGE_NAME="$PACKAGE_NAME-$IK_SUFFIX"
fi
OUTPUT="packages/$PACKAGE_NAME.tipa"
mv TrollSpeed.xcarchive/Products/TrollSpeed.tipa "$OUTPUT"
echo "Packaged: $OUTPUT"
