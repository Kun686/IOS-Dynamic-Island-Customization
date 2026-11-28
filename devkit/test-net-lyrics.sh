#!/bin/sh
# 联网匹配逐句歌词。产物都在 .build/net-lyrics/。
#   devkit/test-net-lyrics.sh        离线：夹具解析、候选打分、LRC 与 offset、查询流程、悬浮窗接入（网络层是假的）
#   devkit/test-net-lyrics.sh live   真实联网冒烟：只发歌名和歌手到 QQ 音乐、网易云的公开接口
set -eu
cd "$(dirname "$0")/.."
out=.build/net-lyrics
mkdir -p "$out/modules"
cc() { xcrun --sdk macosx clang -fobjc-arc -fmodules -fmodules-cache-path="$out/modules" -Isources -Wall -Wno-unused-parameter "$@"; }

cc devkit/test-net-lyrics.m sources/IKNetLyrics.m sources/IKLyricsTimeline.m -framework Foundation -o "$out/test-net-lyrics"
if [ "${1:-}" = live ]; then
    exec "$out/test-net-lyrics" --live
fi
"$out/test-net-lyrics" "$PWD/devkit/fixtures/net-lyrics"

cc -Idevkit/host-stubs -Wno-incomplete-implementation -Wno-objc-property-implementation -Wno-unused-property-ivar \
    devkit/test-net-lyrics-center.m sources/IKNetLyrics.m sources/IKLyricsTimeline.m sources/IKPlaybackDiagnostic.m \
    -framework Foundation -o "$out/test-net-lyrics-center"
"$out/test-net-lyrics-center" "$PWD/devkit/fixtures/net-lyrics" "$PWD/$out"
