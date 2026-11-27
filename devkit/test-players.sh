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
    xcrun --sdk macosx clang -fobjc-arc -fmodules -fmodules-cache-path="$out/modules" -Isources \
        "-DIK_PLAYER_FORMAT=\"$format\"" "-DIK_PLAYER_BUNDLE=\"$bundle\"" \
        devkit/test-player.m players/IKPlayerLyrics.m sources/IKLyricsTimeline.m \
        -framework Foundation -framework AVFoundation -framework MediaPlayer -framework CoreMedia -o "$out/test-$name"
    "$out/test-$name" "$PWD/$out/$name"
}
test_player qq com.tencent.QQMusic qrc
test_player netease com.netease.cloudmusic yrc
