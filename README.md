# 灵动岛美化（IOS Dynamic Island Customization）

给带灵动岛的 iPhone 用的美化工具，**免越狱，用巨魔（TrollStore）安装**。

- **应用通知进岛**：选中的应用来通知时，以完整卡片从灵动岛弹出，聊天类通知优先显示发送者头像，标题和正文颜色可分别设置。
- **歌词**：显示播放器上报的当前歌词，支持逐行填色、淡入等动效，颜色和字号可调。
- **封面转动**：专辑封面像唱片一样旋转。
- **播放进度环**：进度沿胶囊边缘走一圈，颜色可跟随封面。
- **过渡动画**：回弹下落、柔和滑入、淡入、缩放弹出、果冻，五种可选。

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

把 `packages/` 里生成的 `.tipa` 传到手机，用巨魔安装。
安装会覆盖手机上已有的 TrollSpeed（两者使用同一个 Bundle ID）。

## 使用

1. 打开 App，打开右上角的运行开关。
2. 在“应用通知”里勾选要进岛的应用。想只看岛上的显示，到 系统设置 → 通知 把这些应用的“横幅”关掉。
3. 歌词需要音乐 App 把当前歌词上报给系统：在音乐 App 的设置里打开“蓝牙歌词”或“车载歌词”。

## 已知限制

- 无法关闭系统横幅，也无法隐藏系统自己的灵动岛。
- 锁屏时不显示；只支持竖屏。
- 歌词取决于音乐 App 是否上报，只能拿到当前这一句。

更多实现细节见 [ISLANDKIT.md](ISLANDKIT.md)。

## 开发者

亦辰 · 微信 `-6-6-6666`

## 致谢与许可证

悬浮窗部分基于 [Lessica/TrollSpeed](https://github.com/Lessica/TrollSpeed)，MIT 许可证，见 [LICENSE](LICENSE)。
`sources/KIF`、`sources/SPLarkController`、`sources/SnapshotSafeView` 等第三方代码遵循各自的许可证。
