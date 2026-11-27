# 灵动岛美化（IOS Dynamic Island Customization）

给带灵动岛的 iPhone 用的美化工具，**免越狱，用巨魔（TrollStore）安装**。

- **应用通知进岛**：选中的应用来通知时，从灵动岛弹出，聊天类通知优先显示发送者头像。
- **歌词**：显示播放器上报的当前歌词，支持逐行填色、淡入等动效；歌名和歌词的颜色分别可调；过长的歌词跟着进度滚动。
- **播放器歌词联动**　QQ 音乐和网易云音乐适配器可转发播放器公开的当前句。导入同一录音的带时间歌词后，拖动或续播会跳到对应句。两款播放器的流媒体原生时间轴仍待实际曲目验证。
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

旧版有 iPhone 14 Pro Max / iOS 16.6.1 的测试记录。0.6.3 的播放器兼容性和微信头像仍待真机验收。

## 安装

从源码编译：需要 macOS、[Theos](https://theos.dev)、iOS 16.5 SDK 和 Swift 工具链。

```
FINALPACKAGE=1 make package
```

或者用 Xcode 和 `ldid`（快捷指令的 App Intents 只有这种方式会带上）：

```
IK_SUFFIX=IslandKit-0.6.3 sh build.sh
sh players/build.sh
```

主包为 `packages/TrollSpeed+AppIntents16_2.0-15-IslandKit-0.6.3.tipa`，播放器适配器和独立诊断库在 `packages/IslandKit-0.6.3/`。构建机缺少可用模拟器服务时，可用 `IK_PNG_ICONS=1 IK_SUFFIX=IslandKit-0.6.3 sh build.sh` 从同一母图生成 iPhone 和 iPad 所需的 PNG 图标。

把 `packages/` 里生成的 `.tipa` 传到手机，用巨魔安装。
安装会覆盖手机上已有的 TrollSpeed（两者使用同一个 Bundle ID）。

## 使用

1. 打开 App，打开右上角的运行开关。
2. 在“应用通知”里勾选要进岛的应用。想只看岛上的显示，到 系统设置 → 通知 把这些应用的“横幅”关掉。
3. QQ 音乐对应 `IslandKit-QQMusic.dylib`，网易云音乐对应 `IslandKit-NetEase.dylib`。播放器加载对应插件后，播放歌曲并打开灵动岛的“歌词”页，查看当前歌曲的数据来源。
4. 如果显示“播放器单句（无时间标签）”或“当前曲目未提供时间轴”，点“为当前歌曲选择歌词文件”，选同一录音版本的 LRC、明文 QRC 或 YRC。文件绑定到打开选择器时的歌曲。可以在该曲下移除绑定。
5. 要排查慢一句，在出现问题的歌曲上记下播放器版本、录音版本和播放秒数，再保留 `island.log` 里的 `player diagnostic`、`recording app=` 和可能出现的 `lyrics timeline`。两个适配器内置这项诊断；单独排查时也可使用 `IslandKit-PlaybackDiagnostics.dylib`。

## 已知限制

- 无法关闭系统横幅，也无法隐藏系统自己的灵动岛。
- 锁屏时不显示；只支持竖屏。
- 自动时间轴取决于播放器和曲目是否提供带时间标签的元数据、定时音频歌词或本地同名歌词文件。专有播放引擎可能只上报一行车载歌词，这种情况下自动模式仍可能晚一句。
- 微信通知的头像依赖系统通知提供的 `intents-remote-image-proxy`。应用会异步尝试解码代理内容，系统没有提供可读图片时会退回应用图标。

更多实现细节见 [ISLANDKIT.md](ISLANDKIT.md)。

## 开发者

亦辰 · 微信 `-6-6-6666`

## 致谢与许可证

悬浮窗部分基于 [Lessica/TrollSpeed](https://github.com/Lessica/TrollSpeed)，MIT 许可证，见 [LICENSE](LICENSE)。
`sources/KIF`、`sources/SPLarkController`、`sources/SnapshotSafeView` 等第三方代码遵循各自的许可证。
