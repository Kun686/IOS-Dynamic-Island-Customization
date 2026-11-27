#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/packages/IslandKit-0.6.2"
mkdir -p "$out" "$root/.build/player-modules"
build_player() {
    name=$1
    bundle=$2
    format=$3
    xcrun --sdk iphoneos clang -miphoneos-version-min=16.0 -arch arm64e -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
        -arch arm64 -dynamiclib -fobjc-arc -fmodules -fmodules-cache-path="$root/.build/player-modules" -O2 \
        "-DIK_PLAYER_BUNDLE=\"$bundle\"" "-DIK_PLAYER_FORMAT=\"$format\"" -I"$root/sources" \
        "$root/players/IKPlayerLyrics.m" "$root/sources/IKLyricsTimeline.m" \
        -framework Foundation -framework MediaPlayer -framework AVFoundation -framework CoreMedia \
        -install_name "@rpath/$name.dylib" -o "$out/$name.dylib"
    codesign --force -s - "$out/$name.dylib"
    xcrun lipo -archs "$out/$name.dylib"
}
build_player IslandKit-QQMusic com.tencent.QQMusic qrc
build_player IslandKit-NetEase com.netease.cloudmusic yrc
