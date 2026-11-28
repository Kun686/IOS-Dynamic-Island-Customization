#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
out=.build/player-tests
mkdir -p "$out/modules"
test_player() {
    name=$1
    bundle=$2
    format=$3
    mkdir -p "$out/$name"
    xcrun --sdk macosx clang -fobjc-arc -fmodules -fmodules-cache-path="$out/modules" -Isources -Iplayers \
        "-DIK_PLAYER_FORMAT=\"$format\"" "-DIK_PLAYER_BUNDLE=\"$bundle\"" \
        devkit/test-player.m players/IKPlayerLyrics.m players/IKPlaybackDiagnostics.m sources/IKLyricsTimeline.m sources/IKPlaybackDiagnostic.m \
        -framework Foundation -framework AVFoundation -framework MediaPlayer -framework CoreMedia -o "$out/test-$name"
    "$out/test-$name" "$PWD/$out/$name"
}
test_player qq com.tencent.QQMusic qrc
test_player netease com.netease.cloudmusic yrc

xcrun --sdk macosx clang -fobjc-arc -fmodules -fmodules-cache-path="$out/modules" -Isources -Idevkit/host-stubs \
    -Wno-incomplete-implementation devkit/test-music-center.m sources/IKLyricsTimeline.m sources/IKPlaybackDiagnostic.m sources/IKLocalAvatar.m sources/IKNetLyrics.m \
    -framework Foundation -framework CoreGraphics -framework ImageIO -o "$out/test-music-center"
"$out/test-music-center" "$PWD/$out"

sdk=$(xcrun --sdk macosx --show-sdk-path)
frameworks="$sdk/System/iOSSupport/System/Library/Frameworks"
xcrun --sdk macosx clang -target "$(uname -m)-apple-ios16.0-macabi" -isysroot "$sdk" \
    -iframework "$frameworks" -F "$frameworks" -L "$sdk/System/iOSSupport/usr/lib" \
    -fobjc-arc -fmodules -fmodules-cache-path="$out/modules" -Isources -Iplayers \
    devkit/test-player-activation.m sources/IKPlaybackDiagnostic.m -framework UIKit -framework Foundation \
    -framework MediaPlayer -framework AVFoundation -o "$out/test-activation"
"$out/test-activation"
