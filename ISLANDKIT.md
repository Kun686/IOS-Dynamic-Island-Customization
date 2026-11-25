# 开发说明

工程基于 TrollSpeed（MIT），在它的悬浮进程里加入了灵动岛的绘制、音乐信息、通知读取和一套 SwiftUI 界面。
当前副本已完成 Xcode Release archive 和巨魔权限 TIPA 封装，安装后的显示效果仍需在目标设备上验收。

## 相对 TrollSpeed 的改动

| 文件 | 改动 |
|---|---|
| `Makefile` | 私有框架加 `MediaRemote` |
| `supports/entitlements.plist` | 加 `com.apple.bulletinboard.observer`（读取通知） |
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

- `IKController`：状态机，优先级 通知 > 音乐 > 隐藏；过渡动画；从封面取主色。
- `IKIslandView`：黑色胶囊、旋转封面、音柱、歌词填色、进度环。
- `IKMusicCenter`：通过 MediaRemote 读系统“正在播放”信息。
- `IKNotificationSource`：通过 BulletinBoard 的 BBObserver 读其他应用的新通知，并从通信上下文的 `imageName`、应用资源包、附件和本地图片资源中解析发送者头像。
- `IKPrefs`：读配置；自动识别开孔位置和悬浮层级；诊断日志。

## 歌词从哪来

系统的“正在播放”接口没有专门的歌词字段。部分音乐 App 打开“蓝牙歌词/车载歌词”后，
会把当前这句歌词写进标题、歌手或专辑字段。`IKController` 的做法是：同一首歌（时长不变）期间，
哪个字段在变，哪个就是歌词。因此：

- 只能拿到“当前这一句”，拿不到下一句，也拿不到每句的时长；填色时长按最近几句的间隔估计。
- 播放器不上报歌词时，只显示歌名和歌手。

单行模式显示当前歌词。双行模式第一行显示歌名，第二行显示当前歌词。歌词颜色和填色动画作用于当前歌词行。

## 日志（都在 `/var/mobile/Library/IslandKit/`）

- `island.log`：识别到的屏幕和开孔尺寸、悬浮窗层级、每首歌识别出的歌词字段。只记数值和长度。
- `notif.log`：通知来源的连接状态、收到的通知（应用标识和文字长度）、头像是从哪里取到的、
  每个应用第一次出现时通知对象的属性名和类型（没有内容）。

## 配置文件

`/var/mobile/Library/Preferences/com.islandkit.prefs.plist`，改完后发 Darwin 通知 `com.islandkit.prefs/changed` 即时重载。

`enabled` `notif` `lyric` `spin` `pauseStops` `progressRing`（布尔），`lyricLines`（1/2），
`lyricEffect`（0 无 / 1 填色 / 2 淡入），`lyricFontSize`，`spinSeconds` `notifDuration`（秒），
`notifApps`（bundle ID 数组），`accent` `lyricColor` `ringColor` `notifTitleColor` `notifMessageColor`（十六进制颜色），
`lyricColorMode` `ringColorMode`（0 强调色 / 1 封面 / 2 自定义），`placement`（0 岛下方 / 1 覆盖岛），
`transitionStyle`（0–4），`windowLevelBoost`（0–2，设置后即时重新注册窗口），
`islandTop` `cutoutWidth` `cutoutHeight` `belowTop`（可选，覆盖自动识别的结果）。

## 已知限制

- 系统横幅压不掉，需要用户在系统设置里关掉对应应用的横幅。
- 锁屏时不显示（TrollSpeed 在锁屏时隐藏整个悬浮窗）。
- 覆盖模式下，自定义胶囊可见区域优先接收触摸，长按会在歌词和紧凑态之间切换并给出触觉反馈；胶囊隐藏时开孔区域交还给系统灵动岛。
- 系统展开内容、来电等系统界面由 SpringBoard 决定，覆盖层会让开系统岛区域。
- 只支持竖屏。

## 设置界面

iOS 16 及以上启动 App 后直接进入 IslandKit 设置界面，歌词、封面与进度、通知、动画、外观和关于页面分别独立。动画页面点选样式会播放一次出现、停留和收起预览。开发者信息为亦辰，微信 `-6-6-6666`。
