#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/packages/IslandKit-0.6.3"
mkdir -p "$out" "$root/.build/player-modules"
build_player() {
    name=$1
    shift
    xcrun --sdk iphoneos clang -miphoneos-version-min=16.0 -arch arm64e -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
        -arch arm64 -dynamiclib -fobjc-arc -fmodules -fmodules-cache-path="$root/.build/player-modules" -O2 \
        -I"$root/sources" "$root/players/IKPlaybackDiagnostics.m" "$@" \
        -framework Foundation -framework MediaPlayer -framework AVFoundation -framework CoreMedia \
        -install_name "@rpath/$name.dylib" -o "$out/$name.dylib"
    codesign --force -s - "$out/$name.dylib"
    xcrun lipo -archs "$out/$name.dylib"
}
for name in QQMusic NetEase; do
    case "$name" in
        QQMusic) bundle=com.tencent.QQMusic; format=qrc ;;
        NetEase) bundle=com.netease.cloudmusic; format=yrc ;;
    esac
    build_player "IslandKit-$name" "-DIK_PLAYER_BUNDLE=\"$bundle\"" "-DIK_PLAYER_FORMAT=\"$format\"" \
        "$root/players/IKPlayerLyrics.m" "$root/sources/IKLyricsTimeline.m"
done
build_player IslandKit-PlaybackDiagnostics -DIK_DIAGNOSTICS_ONLY=1
