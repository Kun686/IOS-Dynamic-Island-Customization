# 开发说明

工程基于 TrollSpeed（MIT），在它的悬浮进程里加入了灵动岛的绘制、音乐信息、通知读取和一套 SwiftUI 界面。
当前副本包含 0.6.0 的覆盖、歌词滚动、暂停收起、独立颜色、层级登记、校准描边和过渡演示能力，并在此基础上加入精确歌词桥接、通知头像异步解析和新的应用图标。安装后的显示效果仍需在目标设备上验收。

## 相对 TrollSpeed 的改动

| 文件 | 改动 |
|---|---|
| `Makefile` | 私有框架加 `MediaRemote` |
| `supports/entitlements.plist` | 加 `com.apple.bulletinboard.observer`（读取通知）、`com.apple.springboard.system-component-layout-monitoring`（读取系统岛此刻的位置） |
| `supports/hudapp-bridging-header.h` | 引入 UIKit，声明取应用图标的私有方法 |
| `sources/HUDRootViewController.mm` | 挂载岛的容器；隐藏网速标签并停掉它的定时器；横屏时收起岛 |
| `sources/HUDMainApplicationDelegate.mm` | 悬浮窗层级改为读配置 |
| `sources/MainApplicationDelegate.mm` | iOS 16 及以上直接进入 IslandKit 界面；快捷方式直接开关悬浮进程 |
| `Resources/Info.plist` | 显示名改为“灵动岛” |
| `sources/IK*.h/.m`、`MediaRemote.h` | 新增：岛的绘制、状态机、音乐信息、通知来源、配置 |
| `sources/IK*.swift` | 新增：SwiftUI 界面 |

Bundle ID 仍是 `ch.xxtou.hudapp`，安装会覆盖原版 TrollSpeed。
把 `HUDRootViewController.mm` 顶部的 `ISLANDKIT_DISABLE_SPEED_HUD` 改成 0 可以恢复网速悬浮窗用于对比调试。

## 模块

- `IKController`：状态机，优先级 通知 > 音乐 > 隐藏；过渡动画和它的演示；从封面取主色；岛的几何位置。
  同一个文件里的 `IKSystemIslandMonitor` 负责读取系统岛此刻的实际位置。
- `IKIslandView`：黑色胶囊、旋转封面、音柱、进度环；`IKLineView` 是其中的一行文字（填色、过长时滚动）。
- `IKMusicCenter`：通过 MediaRemote 读系统“正在播放”信息，也缓存 TrollFools 插件提供的逐句歌词时间轴。
- `IKNotificationSource`：通过 BulletinBoard 的 BBObserver 读其他应用的新通知，并从通信上下文、代理 URL、通知附件和应用资源中异步尝试取发送者头像。
- `IKPrefs`：读配置；开孔位置；悬浮层级；诊断日志。

## 歌词来源和精确桥接

系统的 MediaRemote 接口没有标准歌词时间轴字段。没有桥接数据时，部分音乐 App 打开“蓝牙歌词”或“车载歌词”后，
会把当前这一句写进标题、歌手或专辑字段，应用会兼容显示，但只能按字段变化估计顺序和时长。

要让歌词顺序和填色进度跟播放器一致，可以用 TrollFools 向 QQ 音乐、网易云音乐等播放器注入插件。插件负责读取播放器内部歌词和播放时钟，
把下面的属性列表原子写入 `/var/mobile/Library/IslandKit/lyrics.plist`，然后发送 Darwin 通知 `com.islandkit.lyrics/changed`。

```plist
{
    active = 1;
    title = "歌曲名";
    artist = "歌手";
    duration = 238.4;
    position = 42.75;
    rate = 1.0;
    playing = 1;
    updatedAt = 1795650000.25;
    lines = (
        { text = "第一句歌词"; start = 40.0; end = 44.2; },
        { text = "第二句歌词"; start = 44.2; end = 48.7; }
    );
}
```

`duration`、`position`、`start`、`end` 和单句 `duration` 使用秒，`updatedAt` 使用 Unix 时间戳秒，`rate` 可选且表示播放速率，缺省为 1。时间轴的 `end` 可以省略，应用会使用下一句的 `start`，最后一句使用 4 秒兜底，也兼容明显的毫秒值。
插件在暂停、继续播放、拖动进度或切歌时更新 `position`、`playing` 和 `updatedAt`。写入 `active = 0` 会关闭桥接并回到 MediaRemote。
插件可以一次写完整时间轴，应用会在内存中按播放位置选择当前句，不要求每句都重新写文件。

如果播放器插件更容易拿到原始 LRC，也可以把 `lines` 换成 `lrc` 或 `lyrics` 字符串，例如 `"[00:40.00]第一句歌词\n[00:44.20]第二句歌词"`。
应用会解析每个时间标签、按开始时间排序，并用下一句的时间作为当前句的结束时间。

这份工程实现的是接入协议和悬浮窗侧读取逻辑，不包含 QQ 音乐或网易云音乐的注入插件。插件需要单独开发、签名并通过 TrollFools 注入目标播放器。

单行模式显示当前歌词。双行模式第一行显示歌名，第二行显示当前歌词。

- 歌名和歌词是两个独立的 `IKLineView`，颜色各自配置（`titleColorMode` / `lyricColorMode`）。
  换句的上滑动画和填色只加在歌词那一行，歌名只有自己的文字变了才淡入一次。
- 文字比胶囊宽时不截断：有时间信息的歌词跟着进度向左滚动（填色时让填色前沿停在可见宽度的 55% 处）；
  没有时间信息的歌名来回缓慢滚动。暂停时停在当前位置。通知的两行仍然是截断加省略号。

## 和系统岛的层级关系

悬浮窗通过 `SBSAccessibilityWindowHostingController` 交给 SpringBoard 承载。SpringBoard 会为每个登记的窗口
单独建一个场景，场景的层级就是登记时传的 level，各场景按层级从低到高叠放
（`UIScenePresentationBinder` 按 `settings.level` 排序）。iOS 16.6（iPhone 14 Pro Max）的 SpringBoard 里：

| 内容 | 场景层级 |
|---|---|
| 系统岛的内容（`SBSystemApertureViewController`，专辑图、波形等） | 10000002 |
| 悬浮窗，层级“标准” | 10000010 |
| 开孔处的黑色遮罩和隐私指示灯（`SBSystemApertureCurtainViewController`，大小等于开孔） | 11000002 |
| 悬浮窗，层级“更高” / “最高” | 100000000 / 2147483000 |

所以：

- “标准”层级已经在系统岛的内容之上。覆盖模式下，系统岛显示的东西只要落在胶囊范围内就会被挡住。
- “更高”“最高”只是多盖住开孔处那块黑色遮罩。遮罩和开孔本来就是黑的，所以看不出区别，
  反而会挡住隐私指示灯。一般用“标准”。
- 胶囊收起时缩进开孔内部（四周各留 3pt）并隐去内容：那块地方要么是物理开孔，要么被遮罩盖着，不会露出来。
  收起动画放完后整个胶囊设为透明。这一步按时间触发，不挂在 UIKit 动画的完成回调上：
  0.5.0 里封面用 `layer.speed = 0` 暂停旋转，动画块里给这个被暂停的图层加的布局动画永远走不完，
  完成回调不来，结果“暂停 8 秒后胶囊缩小了却一直留在系统岛上”。现在封面改为记下角度后移除旋转动画。
- 系统岛不在悬浮窗上面，所以它不会“挡住”胶囊；下挂模式里“从岛里长出来”的效果靠的是起点藏在开孔里。

层级改动后悬浮进程会先注销再按新层级登记窗口（SpringBoard 对重复登记不更新层级），不需要重启。
注销用的 `unregisterWindowWithContextID:` 在本机留有符号的 iOS 14.2、16.6、18.7 的 SpringBoardServices 里都有；
万一运行的系统里没有，设置界面会检测到，改层级后自动把悬浮进程重启一遍，说明文字也会相应改成“会自动重启”。
即时切换这条路径还没有在真机上跑过，见下面的验收清单。

## 开孔位置和覆盖范围

开孔的位置和大小：

| 屏宽 | 机型 | 开孔 | 距顶 | 来源 |
|---|---|---|---|---|
| 393 | 14 Pro、15、15 Pro | 125 × 36.67 | 11.33 | iOS 16.6 的 `SBUISystemApertureLayoutMetrics` |
| 430 | 14 Pro Max、15 Plus、15 Pro Max | 125.33 × 36.67 | 11.33 | 同上 |
| 402 / 440 / 420 | 16 Pro 及之后的机型 | 125 或 125.33 × 36.67 | 14 / 14 / 20 | iOS 26.5 模拟器里 `_exclusionArea` 的返回值，未在真机核实 |

- 能装巨魔的灵动岛机型（iOS 16.0–16.6.1 的 14 Pro 系列、iOS 17.0 的 14 Pro 和 15 系列）屏宽只有 393 和 430，直接查表。
- 其他尺寸先问 `-[UIScreen _exclusionArea]`，问不到才用表里的备用值；这些机型出厂就是 iOS 18 以上，目前装不了巨魔。
- `island.log` 里会记下最终用的矩形和来源（`table` / `system` / `fallback`）。

覆盖模式下胶囊的大小：

- 开孔处比开孔略大一圈：`coverExtraWidth`、`coverExtraHeight`（默认各 3，两侧平分），`coverOffsetY` 修正上下位置。
  这三项只影响覆盖模式，下挂模式收起的位置始终按识别到的开孔算。
  设置里“显示校准描边”打开时（`calibrateUntil` 之前），悬浮进程在没有歌曲和通知时用红线画出这个范围。
- 每个状态先按自己的排版定宽度：歌词和通知态 min(屏宽 − 40, 360)，听歌时来通知 300（右边放小封面），
  紧凑态在开孔两侧各伸出 `coverCompactSide`（默认 66，只能在 plist 里改）。
- 再保证不小于“盖住系统岛所需的宽度”（`coverWidthNeededForHeight:`），上限是屏宽 − 12：
  - 系统岛此刻的实际位置来自 SpringBoard 的 `SBSSystemApertureLayoutMonitor`
    （系统自己的辅助功能界面 `AXUIDisplayManager` 也是这样跟踪系统岛的，需要上面那条权限）。
    读得到时，所需宽度 = 系统岛最远一端到屏幕中线距离的两倍 + 圆角补偿 + `coverExtraWidth`。
  - 读不到时（系统里没有这个类，或者连接被拒绝），按最宽的情况算：系统岛紧凑态的上限是
    屏宽 − 73.33（`maximumCompactSize`，430 宽机型上是 356.67）。这时紧凑态也是一整条宽的。
  - 圆角补偿：歌词、通知态的圆角是 36，比系统岛的 18.33 大，只比系统岛宽一点点的话，
    系统岛圆头的肩部会从胶囊的圆角外面露出来。默认参数下要多宽出约 21；紧凑态圆角和系统岛接近，不用补。
  - 加宽后右边放不下小封面时，小封面不显示。
- 系统岛展开时（有一块比开孔高出 14 以上：长按、来电、面容解锁动画等）胶囊让开，两种显示位置都是这样；
  等系统岛收回去再出现。读不到系统岛位置时做不到这一点。

`island.log` 里 `system island monitor:` 一行说明监视有没有启动，`system island frames:` 是每次收到的位置。

## 没有真机时的验证

`devkit/sim-harness/` 是一个只在模拟器里跑的验证 App：把 `IKIslandView`、`IKController`、`IKPrefs` 和三个 `IK*.swift`
原样编进去，用测试桩喂“正在播放”信息，按时间线截图。能看排版、填色、滚动、过渡动画、暂停后是否真的隐藏、设置页；
看不了悬浮窗和系统岛的层级关系。用法见那里的 README。

## 真机验收清单

下面几项模拟器验证不了，装到真机后需要逐项看一遍：

1. 暂停播放 8 秒后，胶囊缩回系统岛并完全消失，系统岛上和四周不留任何东西（下挂、覆盖两种模式各看一次）。
2. 覆盖模式下放歌（音乐 App 退到后台，让系统岛显示它自己的专辑图和波形）：歌词态、点一下后的紧凑态、
   来通知时，系统岛都不从胶囊四周露出来。长按胶囊让系统岛展开时，胶囊应当消失，系统岛收回后再出现。
   胶囊和系统岛上下没对齐就打开“显示校准描边”调覆盖范围。
   `island.log` 里应当有 `system island monitor: started` 和随后的 `system island frames:`；
   如果只有 `started` 而一直没有 `frames`，说明连接被系统拒绝了，这时紧凑态会是一整条宽的。
3. 悬浮窗层级在“标准 / 更高 / 最高”之间切换后，岛立即（或自动重启后）照常显示；三档看上去应该没有区别。
   切到“更高”或“最高”时，开孔里的隐私指示灯（录音、定位时的小圆点）会被盖住，可以用来确认层级确实换了。
4. 长歌词：开头能看到第一个字，结尾能看到最后一个字，滚动跟着填色走；暂停时停住。
5. `/var/mobile/Library/IslandKit/island.log` 里的 `geometry` 一行应该是 `source=table`，
   `windowLevel applied=` 一行是当前层级对应的数值。

## 日志（都在 `/var/mobile/Library/IslandKit/`）

- `island.log`：识别到的屏幕和开孔尺寸、悬浮窗层级、每首歌识别出的歌词字段。只记数值和长度。
- `notif.log`：通知来源的连接状态、收到的通知（应用标识和文字长度）、头像是从哪里取到的、代理头像的解析结果，
  每个应用第一次出现时通知对象的属性名和类型（没有内容）。不会记录完整 URL、通知正文或图片内容。

## 配置文件

`/var/mobile/Library/Preferences/com.islandkit.prefs.plist`，改完后发 Darwin 通知 `com.islandkit.prefs/changed` 即时重载。

`enabled` `notif` `lyric` `spin` `pauseStops` `progressRing`（布尔），`lyricLines`（1/2），
`lyricEffect`（0 无 / 1 填色 / 2 淡入），`lyricFontSize`，`spinSeconds` `notifDuration`（秒），
`notifApps`（bundle ID 数组），`accent` `lyricColor` `titleColor` `ringColor` `notifTitleColor` `notifMessageColor`（十六进制颜色），
`lyricColorMode` `titleColorMode` `ringColorMode`（0 强调色 / 1 封面 / 2 自定义 / 3 白色，3 只用于歌名），
`placement`（0 岛下方 / 1 覆盖岛），`transitionStyle`（0–4），`windowLevelBoost`（0–2，立即生效），
`coverExtraWidth` `coverExtraHeight` `coverOffsetY`（覆盖范围微调），`coverCompactSide`（可选，设置界面不管），
`calibrateUntil`（Unix 时间，校准描边显示到什么时候），
`islandTop` `cutoutWidth` `cutoutHeight` `belowTop`（可选，覆盖自动识别的结果）。

发 Darwin 通知 `com.islandkit.demo/transition`，悬浮进程会用当前的 `transitionStyle` 把“出现 → 停留 → 收起”演示一遍
（没有在放歌时用示例歌词）。设置界面点过渡动画的某一项时就是这么做的。

## 已知限制

- 系统横幅压不掉，需要用户在系统设置里关掉对应应用的横幅。
- 锁屏时不显示（TrollSpeed 在锁屏时隐藏整个悬浮窗）。
- 悬浮进程只监听触摸而不拦截，点岛的同时下面的应用也会收到点击。
- 微信等应用的头像由系统通知提供的代理 URL 决定。代理服务拒绝访问或只提供系统内部对象时，应用只能显示应用图标，`notif.log` 会记录异步解析结果。
- 精确歌词需要目标音乐 App 的独立 TrollFools 插件。当前工程只实现时间轴文件协议和读取端，不包含第三方播放器注入代码。
- 系统岛展开时（长按、来电等）胶囊会让开，不去盖它。读不到系统岛位置的系统上做不到，
  展开的系统岛会被胶囊挡住一部分。
- 覆盖模式下系统岛变宽时，胶囊是在收到位置变化后再用弹簧动画跟上的，中间可能有一瞬间露出系统岛的两头。
- 歌曲暂停 8 秒后胶囊收起，覆盖模式下系统岛自己的内容会重新露出来。
- 只支持竖屏。

## 设置界面

iOS 16 及以上启动 App 后直接进入 IslandKit 设置界面，歌词、封面与进度、通知、动画、外观和关于页面分别独立。
“外观与动画”里点任意一种过渡动画会选中它，并在页面里和屏幕顶部的岛上各演示一遍；
选“覆盖系统岛”后多出“覆盖范围”一栏，可以打开校准描边对着真机调大小。开发者信息为亦辰，微信 `-6-6-6666`。
