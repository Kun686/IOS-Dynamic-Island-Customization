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
    -Wno-incomplete-implementation devkit/test-music-center.m sources/IKLyricsTimeline.m sources/IKPlaybackDiagnostic.m \
    sources/IKLyricEvidence.m sources/IKContainerScan.m -framework Foundation -o "$out/test-music-center"
"$out/test-music-center" "$PWD/$out"

# The probe runs inside a stand-in bundle: the test executable plus a framework that is loaded after launch.
app="$PWD/$out/probe-app"
mkdir -p "$app/Frameworks/FixtureLyrics.framework"
xcrun --sdk macosx clang -fobjc-arc -fmodules -fmodules-cache-path="$out/modules" -dynamiclib devkit/test-lyric-fixture.m \
    -framework Foundation -o "$app/Frameworks/FixtureLyrics.framework/FixtureLyrics"
xcrun --sdk macosx clang -fobjc-arc -fmodules -fmodules-cache-path="$out/modules" -Isources -Iplayers \
    devkit/test-lyric-probe.m players/IKLyricProbe.m sources/IKLyricEvidence.m sources/IKContainerScan.m sources/IKPlaybackDiagnostic.m \
    -framework Foundation -framework MediaPlayer -o "$app/test-lyric-probe"
"$app/test-lyric-probe" "$PWD/$out"
