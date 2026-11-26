# 模拟器里的验证 App

没有真机时用来检查岛的排版和动画。它把 `sources/` 里的 `IKIslandView.m`、`IKController.m`、`IKPrefs.m`
和三个 `IK*.swift` 原样编进一个普通的模拟器 App，用测试桩代替读系统“正在播放”信息和通知的部分
（`HarnessStubs.m`），再按写死的时间线喂数据（`Harness.swift` 里的 `runTimeline`）。

它验证不了的：悬浮窗和系统岛的层级关系、悬浮窗层级的切换、真实播放器上报歌词的方式。这些只能在真机上看。
另外模拟器里它是普通 App，系统岛和状态栏画在它上面，和真机上悬浮窗盖住状态栏不一样。

## 用法

```sh
sh build.sh                                  # 产物在 .build/sim-harness/IKHarness.app
xcrun simctl boot "iPhone 17 Pro Max"
UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
xcrun simctl install $UDID ../../.build/sim-harness/IKHarness.app

# 岛：下挂模式，完整时间线（出现、短歌词、长歌词、暂停后收起、演示、紧凑态、通知）
python3 drive.py $UDID /tmp/ik below '{"IK_SCENARIO":"hud","IK_placement":0}' 1.4 3.2 6.9 8.6 11.2 13.3 15.6 17.3 20.1 21.7
# 覆盖模式，并画一个模拟的系统岛紧凑态（灰底，左蓝右橙），看胶囊有没有把它盖住
python3 drive.py $UDID /tmp/ik cover '{"IK_SCENARIO":"hud","IK_placement":1,"IK_SYSCOMPACT":1}' 1.6 3.4 8.8 13.6 20.3 22.0
# 暂停后收起（宽限缩短到 0.3 秒）：日志里最后几行应当是 alpha=0.00
python3 drive.py $UDID /tmp/ik pause '{"IK_SCENARIO":"hud","IK_TL":"pause"}' 4.6
# 覆盖模式跟着系统岛的实际大小加宽、系统岛展开时让开（用 setSystemFrames 模拟 SpringBoard 的通知）
python3 drive.py $UDID /tmp/ik adaptive '{"IK_SCENARIO":"hud","IK_placement":1,"IK_TL":"adaptive"}' 1.9 2.9 3.9 4.9 5.9 6.9 8.1 9.3 10.3
# 长歌词从头滚到尾：日志里 row2 的 track 开头应是 0.0..，结尾的右边缘应等于行宽 w
python3 drive.py $UDID /tmp/ik scroll '{"IK_SCENARIO":"hud","IK_TL":"scroll"}' 5.5 7.8
# 很长的歌名来回滚动，暂停时停在原地，继续后接着滚
python3 drive.py $UDID /tmp/ik marquee '{"IK_SCENARIO":"hud","IK_TL":"marquee"}' 4.8 6.6 8.6
# 长歌词唱到一半暂停再继续
python3 drive.py $UDID /tmp/ik resume '{"IK_SCENARIO":"hud","IK_TL":"resume"}' 9.6 11.6 12.8 14.2
# 设置页
python3 drive.py $UDID /tmp/ik lyric '{"IK_SCENARIO":"lyric","IK_titleColorMode":2,"IK_titleColor":"#4AC8F3"}'
python3 drive.py $UDID /tmp/ik appearance '{"IK_SCENARIO":"appearance","IK_placement":1}'

# 把截图顶部拼成一张图来看
xcrun swiftc -O contact.swift -o /tmp/ik/contact && /tmp/ik/contact /tmp/ik/sheet.png 420 2 0.5 /tmp/ik/below-*.png
```

`IK_` 开头的环境变量会覆盖对应的配置项（`placement`、`transitionStyle`、`lyricLines`、`lyricEffect`、
`titleColorMode`、`lyricColorMode`、`coverExtraWidth`、`coverExtraHeight`、`coverOffsetY`、`coverCompactSide`、`calibrateUntil`、`titleColor`）。
每次启动时日志里有一行 `geometry`：屏幕尺寸、系统私有接口给的开孔矩形、最终采用的开孔。

对比旧版本的行为（例如 0.5.0 里暂停后胶囊收起却不隐藏）：

```sh
IK_SRC=/path/to/IslandKit-TS-0.5.0-fixed/IslandKit-TS IK_OLD=1 IK_OUT=/tmp/ik/old sh build.sh
```
