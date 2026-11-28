#!/bin/sh
# 用产品里的 IK 源码（不改动）加测试桩，编一个只在模拟器里跑的验证 App。
# 产物在 .build/sim-harness/（已被 .gitignore 忽略）。
#   IK_SRC   换一份源码目录（例如旧版本，用来对比）；IK_OLD=1 时跳过只有新版本才有的设置页
#   IK_OUT   换一个输出目录
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${IK_SRC:-$HERE/../..}"
OUT="${IK_OUT:-$HERE/../../.build/sim-harness}"
EXTRA_C="${IK_OLD:+-DIK_OLD=1}"
EXTRA_S="${IK_OLD:+-DIK_OLD}"
rm -rf "$OUT" && mkdir -p "$OUT/IKHarness.app"
TARGET=arm64-apple-ios16.0-simulator
CFLAGS="-target $TARGET -fobjc-arc -fmodules -O0 -g -I$SRC/sources -I$SRC/headers -I$SRC/supports -I$HERE -include $SRC/supports/hudapp-prefix.pch -Wno-deprecated-declarations $EXTRA_C"
for f in "$SRC/sources/IKIslandView.m" "$SRC/sources/IKPrefs.m" "$SRC/sources/IKLocalAvatar.m" "$SRC/sources/IKLyricsTimeline.m" "$SRC/sources/IKController.m" "$HERE/HarnessStubs.m"; do
  xcrun -sdk iphonesimulator clang $CFLAGS -c "$f" -o "$OUT/$(basename "$f").o"
done
xcrun -sdk iphonesimulator swiftc -target $TARGET -parse-as-library -Onone $EXTRA_S -module-name IKHarness \
  -import-objc-header "$HERE/harness-bridge.h" -I "$SRC/sources" -I "$SRC/headers" -I "$SRC/supports" -I "$HERE" \
  "$SRC/sources/IKStore.swift" "$SRC/sources/IKComponents.swift" "$SRC/sources/IKViews.swift" "$HERE/Harness.swift" \
  "$OUT"/*.o -framework ImageIO -o "$OUT/IKHarness.app/IKHarness"
cp "$HERE/Info.plist" "$OUT/IKHarness.app/Info.plist"
codesign -s - --force "$OUT/IKHarness.app" >/dev/null 2>&1
echo "built $OUT/IKHarness.app"
