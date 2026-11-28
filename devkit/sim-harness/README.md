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
# 演示连点、紧凑态和通知互相打断时，按帧检查内容边界（有切掉的帧会在日志里写 clipped at 并退出）
python3 drive.py $UDID /tmp/ik interrupt '{"IK_SCENARIO":"hud","IK_placement":1,"IK_TL":"interrupt"}' 0.25 0.55 1.2 2.3 4.8
# 音乐 ↔ 通知直接变形、紧凑 ↔ 歌词时进度环跟着胶囊（最后一张截图要晚于 11 秒，日志里才有 morph 那一行）：
# coverFail 是胶囊没盖住模拟系统岛的帧数（下挂模式本来就不盖，不看这个数），ringFail 是环和胶囊尺寸、圆角对不上的帧数
python3 drive.py $UDID /tmp/ik morph '{"IK_SCENARIO":"hud","IK_placement":1,"IK_TL":"morph"}' 2.3 2.42 4.15 5.3 6.5 8.55 11.3
# 悬挂歌词 + 通知收一下再弹出 + 录屏红点（日志最后一行 hang frames=… coverFail=…，覆盖模式应为 0）
python3 drive.py $UDID /tmp/ik hang '{"IK_SCENARIO":"hud","IK_placement":1,"IK_TL":"hang","IK_musicStyle":2}' 1.6 2.4 2.55 3.0 5.5 9.0 14.8
# 录屏：开始横幅 → 红点和时长 → 放歌时音柱旁的小红点 → 结束横幅（用 setScreenCaptured: 模拟 UIScreen.captured）
python3 drive.py $UDID /tmp/ik record '{"IK_SCENARIO":"hud","IK_placement":1,"IK_TL":"record"}' 1.4 6.5 8.5 10.0 14.8
# 文字位置：日志里 firstRowCenterOffset 是第一行文字中心相对胶囊中线的偏移（居中应为 0，自定义应约等于 lyricOffsetX）
python3 drive.py $UDID /tmp/ik align '{"IK_SCENARIO":"hud","IK_placement":1,"IK_TL":"align","IK_lyricAlignment":1}' 2.2
# 设置页
python3 drive.py $UDID /tmp/ik lyric '{"IK_SCENARIO":"lyric","IK_titleColorMode":2,"IK_titleColor":"#4AC8F3"}'
python3 drive.py $UDID /tmp/ik appearance '{"IK_SCENARIO":"appearance","IK_placement":1}'

# 把截图顶部拼成一张图来看
xcrun swiftc -O contact.swift -o /tmp/ik/contact && /tmp/ik/contact /tmp/ik/sheet.png 420 2 0.5 /tmp/ik/below-*.png
```

`IK_` 开头的环境变量会覆盖对应的配置项（`placement`、`transitionStyle`、`lyricLines`、`lyricEffect`、
`titleColorMode`、`lyricColorMode`、`coverExtraWidth`、`coverExtraHeight`、`coverOffsetY`、`coverCompactSide`、`calibrateUntil`、`titleColor`、
`lyricAlignment`、`lyricOffsetX`、`lyricOffsetY`、`musicStyle`）。

不想把模拟器建在用户目录里时，用 `xcrun simctl --set <目录> create …` 在工程的 `.build/` 下建设备，并设置 `IK_SIM_SET=<目录>`，`drive.py` 会带上 `--set`。
`drive.py` 的日志是追加写入的，重跑前换一个输出目录。
每次启动时日志里有一行 `geometry`：屏幕尺寸、系统私有接口给的开孔矩形、最终采用的开孔。

对比旧版本的行为（例如 0.5.0 里暂停后胶囊收起却不隐藏）：

```sh
IK_SRC=/path/to/IslandKit-TS-0.5.0-fixed/IslandKit-TS IK_OLD=1 IK_OUT=/tmp/ik/old sh build.sh
```
