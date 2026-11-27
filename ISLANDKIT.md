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
- `IKLyricEvidence`、`IKContainerScan`：歌词数据探针共用的关键词、脱敏、字段变化记录和导出文本；设置 App 对播放器容器的文件形状检查。
- `players/IKLyricProbe`：只编进 `IslandKit-PlaybackDiagnostics.dylib` 的探针，在播放器进程里读类的元数据和播放信息的设置时刻。

## 歌词来源和精确桥接

播放器有两种不同精度的数据。只有车载单句时，读取标题、歌手或专辑中新变化的字段，按最近换句间隔估计填色。播放器何时发布这一句决定最早能显示的时间。整首带时间标签的歌词可以按播放位置选句、拖动和续播。

QQ 音乐、网易云音乐各有一个适配器。0.6.4 可以使用宿主播放字典里的标准歌词、自定义歌词字段及一层嵌套字段。支持带时间标签的文本、字节、JSON 和带时间的行数组，显式毫秒字段或 `timeUnit=ms` 会换算成秒。时间轴文件里的 `sourceKey` 和导出报告的 `key` 对应实际选中的字段。带时间的播放信息可以在没有 AssetURL 时独立生效。匹配的播放项也可提供定时音频歌词，本地媒体可以提供相邻或内嵌歌词。手动绑定支持 UTF-8、UTF-16 和 GBK 系列的明文歌词，上限为 512 KB。两款播放器普通流媒体曲目的专有原生时间轴尚未取得实测样本。

播放器将 `recording.plist`、`lyrics.plist`、可用时的 `clock.plist` 原子写入自己容器的 `Library/IslandKit/`。两端用明确的外部曲目标识、队列位置、时长及进度识别换歌。时长一致且进度连续，或队列提供足够证据时，每句变化的 persistentID 会标记为不稳定。绑定可按基线歌名、歌手和时长找回。队列换歌时若第一份标题沿用上一首，接下来五秒内收到的有效标题可纠正双行歌名。已识别的歌词字段优先，两字段首次同时变化时优先歌手。零时长或持续缺少时长的节目按标题切换，后来收到正时长可恢复曲目处理。单句快照十秒失效，播放项时钟八秒失效。

时间轴快照包括 `bundleID`、可用的 `externalID` 和 `persistentID`、基线曲名、歌手、时长和 `lines`。本地绑定优先。开始、结束以秒计，兼容显式毫秒字段。有匹配的 AVPlayerItem 时采用其时间和速率，否则使用系统播放进度。小于两秒的句间停顿保留已唱完的上一句；显式空行、长间奏及末句结束后显示曲目信息。

`island.log` 的 `recording app=` 每首歌记录首次观察时两个标识和队列位置是否存在。`lyric field=` 只记变化后的字段编号（0 无、1 标题、2 歌手、3 专辑）。`lyrics timeline` 记录来源、可用的字段名和句数。标准歌词、自定义字段、定时音频、同名文件、内嵌歌词和手动导入分别记为 `metadata`、`publishedField`、`timedAudio`、`sidecar`、`audio`、`import`。

`playback-diagnostics.plist` 是播放器的最近一次采样。一般每五秒采样一次，时间轴结果变化时立即更新。九十秒内的快照可以进入悬浮日志。每个播放器还在自己的 `Library/IslandKit/playback-report.plist` 中原子保存最近 24 种形状，重复采样更新同一条。`歌词 → 导出播放诊断` 可在停播后读取这份历史。独立诊断库的结果标为 `observedOnly`。

- `custom` 最多记录 40 个符合标识符形式的未知键和类型，含 lyric、lrc、qrc 或 yrc 的键优先。`nested` 最多记录 8 个嵌套歌词字段。`objects` 最多记录 8 个实际进入歌词字段的自定义对象类型，数组取首个元素的类型。`omitted` 给出未知键中未逐项列出的数量。
- `avAccess`、`avJump` 是观察到的 AVPlayerItem 事件计数。`timeline` 包含时间轴来源、命中字段和句数，`clock` 表示该适配器本次没有写出带时间的歌词。
- 本地媒体旁的同名文件会记录脱敏路径、扩展名、字节数及前 512 字节的类型判断。有导出样本时，设置页还允许用户选择一个文件夹，只在该目录下查看最多三层、256 个条目、32 个匹配文件。跳过隐藏项、包内容和符号链接。报告中的 `limited=1` 表示触及上限。离开设置页前导出即可保存这次样本检查。报告只包含形状，不含歌词值、真实文件名、目录名或原始字节。

单行模式显示当前歌词。双行模式第一行显示歌名，第二行显示当前歌词。

- 歌名和歌词是两个独立的 `IKLineView`，颜色各自配置（`titleColorMode` / `lyricColorMode`）。
  换句的上滑动画和填色只加在歌词那一行，歌名只有自己的文字变了才淡入一次。
- 文字比胶囊宽时不截断：有时间信息的歌词跟着进度向左滚动（填色时让填色前沿停在可见宽度的 55% 处）；
  没有时间信息的歌名来回缓慢滚动。暂停时停在当前位置。通知的两行仍然是截断加省略号。

## 内部歌词数据探针（0.6.5）

路线是给两款播放器各写注入插件，直接拿播放器内部带时间轴的歌词。动手之前先要知道歌词数据在哪个类、哪个文件里，以及“慢一句”是播放器发得晚还是系统传得晚。探针只回答这三个问题：只取证，不取词。不解密文件，不调用播放器自己的方法，不读任何对象的值，不联网。

### 播放器里的探针

`IslandKit-PlaybackDiagnostics.dylib` 从 0.6.5 起带探针，两个适配器不带。库的构造函数只在 bundle ID 是 `com.tencent.QQMusic` 或 `com.netease.cloudmusic` 的进程里启动探针，一个进程只启动一次。

类清单在启动 6 秒后采一次，第一次发布“正在播放”后 3 秒再采一次。

- 范围是路径在 `.app` 目录里的镜像，也就是主程序和包内框架。系统库和 IslandKit 自己的库不算。
- 类名含 lyric、lrc、qrc、yrc、krc（不分大小写）的类入选。只是因为 `QRCode` 才含 qrc 的不算。
- 每个类记录：类名、父类、所在镜像相对包的路径、实例方法和类方法的名字及签名编码、属性名和属性串、成员变量名和类型编码。
- 只用 `objc_copyClassNamesForImage`、`class_copyMethodList`、`class_copyPropertyList`、`class_copyIvarList` 这类读取函数。不给任何类或对象发消息，所以连 `+initialize` 也不会被触发。测试里用带 `+initialize` 的夹具类验证了这一点。
- 上限：600 个类带成员，再有 1500 个只列类名，更多的只计入 `dropped`。每个类每种成员最多 300 条。名字留 160 个字符，类型编码留 200 个，截断的以 `~` 结尾。成员明细总共约 640 KB，用完后其余的类只列名字，并标 `budgetLimited=1`。
- 名字含 View、Cell、Button、Label、Layer 的类（ViewModel 除外）排在后面，先把额度给更像数据和逻辑的类。
- 第二次采样里新出现的类标 `late`，通常来自放歌时才加载的框架。
- 采样前写 `lyric-probe-sampling.plist`，采完删除。同一个播放器版本连续两次没采完（例如采样时进程被杀）就不再尝试，导出里会有一行 `class sampling unfinished`。

字段变化的时刻取自 `-[MPNowPlayingInfoCenter setNowPlayingInfo:]`。探针把这个方法包了一层：先读系统运行时间，调用原来的实现，再比较标题、歌手、专辑和上一次是否相同。

- 有变化就记一条：系统运行时间、字典里的进度和速率、时长、哪些字段变了、三个字段各自的文字长度。
- 文字只留在内存里做比较，不写盘。记录里全是数字。
- 保留最近 200 条，最多每 1.5 秒写一次盘。

结果写在播放器容器的 `Library/IslandKit/`：`lyric-probe-classes.plist` 和 `lyric-probe-events.plist`。

### 悬浮端的时刻

`IKMusicCenter` 收到系统的“正在播放”变化时，用同一套规则（`IKLyricEventLog`）记一条，时间取开始读取这次变化的那一刻。文件是 `/var/mobile/Library/IslandKit/lyric-hud-events-<小写 bundle ID>.plist`。两边读的是同一个系统运行时间，可以直接相减。

### 容器里的文件形状

点“导出播放诊断”时，设置 App 在后台线程检查两款播放器数据容器里的 `Documents`、`Library`、`tmp`。这一步不需要注入。

- 文件名含关键词，或者它上面任意一级目录名含关键词，就算匹配。
- 每行是同一目录下脱敏后同名的一组文件：相对路径、真实扩展名、文件数、大小范围、文件头类型。文件头类型沿用 `IKLyricFileShape`，读前 512 字节判断是 `timed-text`、`text`、`binary` 还是别的，不保存内容。每行最多读 8 个文件。
- 名字含关键词的目录单独列一行，以 `directory` 结尾。
- 脱敏规则按路径的每一段执行：

| 内容 | 替换成 |
|---|---|
| 纯数字 | `<num>` |
| 8 位以上且含数字的十六进制串，或 16 位以上的十六进制串 | `<hex>` |
| UUID | `<uuid>` |
| 20 位以上且含 4 个以上数字的字母数字串 | `<id>` |
| 含非 ASCII 字符的段，带空格的文件名 | `<text>` |
| 超过 64 个字符的段 | `<long>` |
| 英文词里夹着的 5 位以上数字 | 只把数字换成 `<num>` |
| 同一目录、同一扩展名下超过 4 个不同的英文文件名 | 合并成 `<name>` |

  其余英文目录名和文件名原样保留，例如 `Application Support`、`com.tencent.QQMusic`、`LyricCache`。
- 上限：目录深 10 层（`Documents` 算第 1 层）、6 万个目录项、240 行、读 600 次文件头、6 秒。触到哪个上限，`limited=` 里就写哪个，同时 `complete=0`。
- 名字含关键词的目录和它下面的目录优先读，避免一个无关的大缓存先把上限用完。
- 不跟随符号链接，跳过 `Library/IslandKit`。

### 导出的文本

三部分都接在“歌词 → 导出播放诊断”原有内容的后面，每款播放器一组：

```
lyric probe app=com.tencent.QQMusic version=… captured=… samples=[launch uptime=… images=… classNames=… matched=…; playback …] appImages=… detailed=… namesOnly=… dropped=… budgetLimited=0 invalid=0
image QQMusic classNames=… matched=…
class SomeLyricModel : NSObject image=QQMusic instanceMethods=12 classMethods=1 properties=4 ivars=4 late
  - lineAtTime: @24@0:8d16
  + sharedModel @16@0:8
  @ lines T@"NSArray",&,N,V_lines
  . _lines @"NSArray"
class names only: …
lyric events app=com.tencent.QQMusic side=player captured=… kept=… total=…
  t=81234.512 pos=63.20 rate=1.00 dur=215.0 changed=artist len=12
lyric events app=com.tencent.QQMusic side=hud captured=… kept=… total=…
  t=81234.530 pos=63.20 rate=1.00 dur=215.0 changed=artist len=12
lyric latency app=com.tencent.QQMusic paired=57 player=60 hud=58 min=… median=… p90=… max=… (seconds, HUD seen minus player set)
container scan app=com.tencent.QQMusic directories=… entries=… matched=… rows=… unlisted=… symlinks=… unreadable=… tooDeep=… complete=1 limited=none seconds=…
  Library/…/Lyric/ directory
  Library/…/Lyric/<num>.qrc ext=qrc files=132 bytes=1204..8830 header=binary sampled=8
```

- 成员行的前缀：`-` 实例方法，`+` 类方法，`@` 属性，`.` 成员变量。
- `t` 是系统运行时间（秒），`pos` 是当时播放信息里的进度，`len` 是变化后的文字长度。`first` 是这次运行记下的第一条，`newDuration` 表示时长也变了，一般是换歌。
- `lyric latency` 把悬浮端看到的每次变化，和它之前 10 秒内播放器设置的第一条还没配过、且有同一字段长度相同的变化配成一对，给出时间差的最小值、中位数、九成位和最大值。
- 中位数只有几十毫秒而岛上仍慢一句，说明是播放器发得晚。这时拿 player 一侧的 `pos` 和这句在歌词文件里的起始时间比。中位数接近一句的长度，说明是系统传得晚。
- `paired=0` 时看 `reason`：`no-player-events` 是探针没运行或没放歌，`no-hud-events` 是悬浮窗没开，`different-boot` 是两份记录不属于同一次开机，`no-overlap` 是两边没有对得上的变化。
- 连续几句长度相同、悬浮端又漏掉一次时，个别配对会偏大。以逐条记录为准。
- 没有探针结果时写 `classes=absent` 和 `side=player absent`。读回来的文件按不可信输入处理，不符合符号形状的条目丢弃并计入 `invalid`。

### 这一版没有做的

- 没有在真机的 QQ 音乐、网易云音乐里运行过。类清单的实际规模、两款播放器是否允许注入后正常启动，都要等真机结果。
- 只看数据容器里的三个目录。App Group 共享容器没有看。
- 只知道类和方法叫什么，不知道哪个对象属于正在播放的歌。这要等拿到清单后再定下一步挂哪个方法。

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

- 覆盖模式下，“自动”档使用最高层级，确保系统岛内容和开孔处的遮罩都不会压住胶囊。下挂模式下，“自动”档使用标准层级。
- “更高”“最高”会连开孔处的隐私指示灯一起盖住。覆盖模式一般保持“自动”，下挂模式一般保持“自动”。
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
3. 悬浮窗层级在“自动 / 更高 / 最高”之间切换后，岛立即（或自动重启后）照常显示。
   覆盖模式的“自动”应直接盖住系统岛；切到“更高”或“最高”时，开孔里的隐私指示灯（录音、定位时的小圆点）会被盖住，可以用来确认层级确实换了。
4. 长歌词：开头能看到第一个字，结尾能看到最后一个字，滚动跟着填色走；暂停时停住。
5. `/var/mobile/Library/IslandKit/island.log` 里的 `geometry` 一行应该是 `source=table`，
   `windowLevel applied=` 一行是当前层级对应的数值。

## 日志（都在 `/var/mobile/Library/IslandKit/`）

- `island.log`：识别到的屏幕和开孔尺寸、悬浮窗层级、每首歌识别出的歌词字段。只记数值和长度。
- `notif.log`：通知来源的连接状态、收到的通知（应用标识和文字长度）、头像是从哪里取到的、代理头像的解析结果，
  每个应用第一次出现时通知对象的属性名和类型（没有内容）。不会记录完整 URL、通知正文或图片内容。
- `lyric-hud-events-<小写 bundle ID>.plist`：悬浮端看到 QQ 音乐、网易云音乐的标题、歌手、专辑变化的时刻，最近 200 条，只有数字。

## 配置文件

`/var/mobile/Library/Preferences/com.islandkit.prefs.plist`，改完后发 Darwin 通知 `com.islandkit.prefs/changed` 即时重载。

`enabled` `notif` `lyric` `spin` `pauseStops` `progressRing`（布尔），`lyricLines`（1/2），
`lyricEffect`（0 无 / 1 填色 / 2 淡入），`lyricFontSize`，`spinSeconds` `notifDuration`（秒），
`notifApps`（bundle ID 数组），`accent` `lyricColor` `titleColor` `ringColor` `notifTitleColor` `notifMessageColor`（十六进制颜色），
`lyricColorMode` `titleColorMode` `ringColorMode`（0 强调色 / 1 封面 / 2 自定义 / 3 白色，3 只用于歌名），
`placement`（0 岛下方 / 1 覆盖岛），`transitionStyle`（0–4），`windowLevelBoost`（0 自动 / 1 更高 / 2 最高，立即生效；覆盖模式的自动档使用最高层级），
`coverExtraWidth` `coverExtraHeight` `coverOffsetY`（覆盖范围微调），`coverCompactSide`（可选，设置界面不管），
`calibrateUntil`（Unix 时间，校准描边显示到什么时候），
`islandTop` `cutoutWidth` `cutoutHeight` `belowTop`（可选，覆盖自动识别的结果）。

发 Darwin 通知 `com.islandkit.demo/transition`，悬浮进程会用当前的 `transitionStyle` 把“出现 → 停留 → 收起”演示一遍
（没有在放歌时用示例歌词）。设置界面点过渡动画的某一项时就是这么做的。

## 已知限制

- 系统横幅压不掉，需要用户在系统设置里关掉对应应用的横幅。
- 锁屏时不显示（TrollSpeed 在锁屏时隐藏整个悬浮窗）。
- 悬浮进程只监听触摸而不拦截，点岛的同时下面的应用也会收到点击。
- 微信发送者头像优先用通知携带的图片。遇到设备日志中出现的 INRemoteImageProxy，先请求图像，再在工作队列解析该代理。系统返回空、返回错误、超时、通知已被替换分别记到 `notif.log`。同一发送者、同一代理地址会合并正在等待的备用请求。最多两个工作线程等待系统服务，超时后名额由真实调用返回时释放。成功头像按发送者缓存在内存里，系统未交付图片时显示应用图标。
- 播放器只提供无时间戳单句时，未绑定本地时间轴的歌曲仍依赖车载歌词。插件支持公开媒体元数据和明文歌词，流媒体供应商的专有歌词格式仍需按版本验证。
- 系统岛展开时（长按、来电等）胶囊会让开，不去盖它。读不到系统岛位置的系统上做不到，
  展开的系统岛会被胶囊挡住一部分。
- 覆盖模式下系统岛变宽时，胶囊是在收到位置变化后再用弹簧动画跟上的，中间可能有一瞬间露出系统岛的两头。
- 歌曲暂停 8 秒后胶囊收起，覆盖模式下系统岛自己的内容会重新露出来。
- 只支持竖屏。

## 设置界面

iOS 16 及以上启动 App 后直接进入 IslandKit 设置界面，歌词、封面与进度、通知、动画、外观和关于页面分别独立。
“外观与动画”里点任意一种过渡动画会选中它，并在页面里和屏幕顶部的岛上各演示一遍；
选“覆盖系统岛”后多出“覆盖范围”一栏，可以打开校准描边对着真机调大小。开发者信息为亦辰，微信 `-6-6-6666`。
