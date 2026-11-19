<p align="center">
  <img src="assets/branding/vela-icon.png" width="96" height="96" alt="Vela 图标">
</p>

<h1 align="center">Vela</h1>

<p align="center"><strong>在你的设备之间轻松分享。</strong></p>

<p align="center">
  <a href="README.md">English</a> · 简体中文<br>
  <a href="#下载">下载</a> · <a href="#故障排查">故障排查</a> · <a href="CONTRIBUTING.md">参与贡献</a>
</p>

Vela 让你在自己的设备之间分享内容，设备来自不同生态也能互相收发。可以在 Vela 里发送，也可以用系统分享菜单，或在桌面端把文件拖进 Vela。

## 下载

Vela 提供 Android、macOS、Windows 和 Linux 安装包。打开发布页，选一个带版本号的发布，再下载适合你设备的安装包。每个版本都附有安装说明和 SHA-256 校验文件。 [下载 Vela](https://github.com/AbyssSkb/Vela/releases)

## 在设备之间分享

- **配对设备。** 在一台设备上出示设备码，在另一台输入。Android 也可以扫码。通过可信渠道核对设备码后，在出示设备码的一端确认配对。配对一次就能反复分享，无需注册账号。
- **发送内容。** 可以发文件、文件夹、文字和剪贴板内容。发送前可以查看内容和目标设备，传输时可以查看进度或取消。
- **接收。** 接收端默认逐次确认，也可以在设置中开启自动接收。打开「接收记录」可以找到收到的文件、文字和链接。文件保存位置可以在设置中更改。

要在后台收件，可以在 Android 上开启接收服务，在 macOS 上让 Vela 留在菜单栏，或在 Windows 和 Linux 上让它留在系统托盘。 [后台接收说明（英文）](docs/user-guide.md#receive-in-the-background)

## 连接与隐私

只要两端的 Vela 正在运行且可以连接，同网、跨网都可以发送。Vela 负责建立连接，直连和中继的流量都在设备之间加密。配对记录和接收记录保存在本机，设备身份密钥保存在系统的安全存储中。

## 故障排查

| 遇到的问题 | 可以怎么做 |
| --- | --- |
| Vela 无法启动 | 在错误页重试，或打开「诊断」。 |
| 无法配对 | 在两台设备上打开 Vela，核对设备码，在出示设备码的一端确认请求。 |
| 设备暂时无法连接 | 确认接收端的 Vela 正在运行、两端能联网，再刷新设备状态。 |
| 后台收不到请求 | 在设置的「接收」中查看后台状态和处理提示，确认设备没有进入睡眠。 |
| 找不到收到的文件 | 在「接收记录」中搜索文件名，或检查设置中的保存位置。 |

## 从源码运行

按 [贡献指南](CONTRIBUTING.md) 安装 Flutter 和 Rust，然后准备目标平台的构建工具。

| 平台 | 构建工具 |
| --- | --- |
| Android | Android SDK、NDK、JDK 17、已连接的设备或模拟器 |
| macOS | macOS 12 及以上、Xcode 及命令行工具、CocoaPods |
| Windows x64 | Visual Studio 桌面 C++ 工具和 CMake |
| Linux x64 | Clang、CMake、Ninja、GTK 3、libsecret、libnotify 和 Ayatana AppIndicator 开发包 |

安装依赖并列出可运行的设备。

```sh
flutter pub get --enforce-lockfile
flutter devices
```

把列表中的设备 ID 填入 `flutter run -d DEVICE_ID`。Flutter 会通过 Cargokit 构建 Rust 库。

## 参与贡献

欢迎反馈不同设备之间的使用体验，也欢迎提交修复和翻译。开发流程见 [贡献指南](CONTRIBUTING.md)、[代码结构](docs/architecture.md)和[发布流程](docs/releasing.md)。

## 许可证

[MIT](LICENSE)。[Cargokit](rust_builder/cargokit/LICENSE) 等第三方组件沿用各自的许可证。
