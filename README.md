# 灵动岛美化（IOS Dynamic Island Customization）

给带灵动岛的 iPhone 用的美化工具，**免越狱，用巨魔（TrollStore）安装**。

- **应用通知进岛**：选中的应用来通知时，从灵动岛弹出，聊天类通知优先显示发送者头像。
- **歌词**：显示播放器上报的当前歌词，支持逐行填色、淡入等动效；歌名和歌词的颜色分别可调；过长的歌词跟着进度滚动。
- **精确歌词联动**：支持由 TrollFools 注入的 QQ 音乐、网易云音乐等插件写入逐句时间轴，按真实播放位置同步歌词。
- **封面转动**：专辑封面像唱片一样旋转。
- **播放进度环**：进度沿胶囊边缘走一圈，颜色可跟随封面。
- **过渡动画**：回弹下落、柔和滑入、淡入、缩放弹出、果冻，五种可选，点一下就能看到演示。
- **覆盖系统岛**：可以盖在系统岛上，跟着系统岛的实际大小自动加宽；系统岛展开时让开。上下位置可在设置里对着真机校准。
- **自定义图标**：应用使用项目内重新绘制的灵动岛图标。

> 项目还在早期，功能以真机表现为准。

## 要求

- 带灵动岛的 iPhone，iOS 16.0 – 16.6.1 或 17.0（巨魔支持的版本）
- 已安装巨魔（TrollStore）
- 界面需要 iOS 16 及以上

目前只在 iPhone 14 Pro Max / iOS 16.6.1 上测试过。

## 安装

从源码编译：需要 macOS、[Theos](https://theos.dev)、iOS 16.5 SDK 和 Swift 工具链。

```
FINALPACKAGE=1 make package
```

或者用 Xcode 和 `ldid`（快捷指令的 App Intents 只有这种方式会带上）：

```
IK_SUFFIX=IslandKit-0.6.1-lyrics sh build.sh
```

产物是 `packages/TrollSpeed+AppIntents16_<版本>-IslandKit-0.6.1-lyrics.tipa`，`<版本>` 取自 `layout/DEBIAN/control`。

把 `packages/` 里生成的 `.tipa` 传到手机，用巨魔安装。
安装会覆盖手机上已有的 TrollSpeed（两者使用同一个 Bundle ID）。

## 使用

1. 打开 App，打开右上角的运行开关。
2. 在“应用通知”里勾选要进岛的应用。想只看岛上的显示，到 系统设置 → 通知 把这些应用的“横幅”关掉。
3. 歌词可以使用音乐 App 的“蓝牙歌词”或“车载歌词”上报。要精确同步整首歌词，使用 TrollFools 注入插件，把时间轴原子写入目标播放器容器里的 `Library/IslandKit/lyrics.plist`，格式见 [ISLANDKIT.md](ISLANDKIT.md)。悬浮进程会按当前播放应用读取，也兼容旧的全局路径。

## 已知限制

- 无法关闭系统横幅，也无法隐藏系统自己的灵动岛。
- 锁屏时不显示；只支持竖屏。
- 没有歌词桥接插件时，歌词取决于音乐 App 是否上报，系统接口通常只能拿到当前这一句，顺序和时长无法保证。精确歌词桥接需要目标音乐 App 的独立 TrollFools 插件。
- 微信通知的头像依赖系统通知提供的 `intents-remote-image-proxy`。应用会异步尝试解码代理内容，系统没有提供可读图片时会退回应用图标。

更多实现细节见 [ISLANDKIT.md](ISLANDKIT.md)。

## 开发者

亦辰 · 微信 `-6-6-6666`

## 致谢与许可证

悬浮窗部分基于 [Lessica/TrollSpeed](https://github.com/Lessica/TrollSpeed)，MIT 许可证，见 [LICENSE](LICENSE)。
`sources/KIF`、`sources/SPLarkController`、`sources/SnapshotSafeView` 等第三方代码遵循各自的许可证。
