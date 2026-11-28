#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
out=.build/island-layout
mkdir -p "$out/modules"
sdk=$(xcrun --sdk macosx --show-sdk-path)
frameworks="$sdk/System/iOSSupport/System/Library/Frameworks"
xcrun --sdk macosx clang -target "$(uname -m)-apple-ios16.0-macabi" -isysroot "$sdk" \
    -iframework "$frameworks" -F "$frameworks" -L "$sdk/System/iOSSupport/usr/lib" \
    -fobjc-arc -fmodules -fmodules-cache-path="$out/modules" -Isources \
    devkit/test-island-layout.m sources/IKIslandView.m -framework Foundation -framework CoreGraphics \
    -framework UIKit -framework QuartzCore -o "$out/test-layout"
"$out/test-layout"
