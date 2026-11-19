<p align="center">
  <img src="docs/assets/vela-mark.png" width="96" height="96" alt="">
</p>

<h1 align="center">Vela</h1>

<p align="center"><strong>在你的设备之间轻松分享。</strong></p>

<p align="center">
  <a href="#下载">下载</a> · <a href="docs/user-guide.zh-CN.md">使用指南</a> · <a href="README.md">English</a>
</p>

Vela 是一款开源的个人设备分享工具。手机上的照片、电脑上的文件夹、刚复制的链接，都可以发到自己的另一台设备。配对后就能来回发，跨系统、跨网络也用同样的操作，无需注册账号。

## 下载

选一个带版本号的发布，下载适合你设备的安装包。发布页附有安装说明和 SHA-256 校验文件。 [下载 Vela](https://github.com/AbyssSkb/Vela/releases)

| 平台 | 安装包 |
| --- | --- |
| Android | ARM64 APK |
| macOS | Apple 芯片或 Intel 芯片 DMG |
| Windows | x64 安装程序 |
| Linux | x64 AppImage |

[安装指南](docs/user-guide.zh-CN.md#下载安装)

## 配对与收发

1. 在两台设备上打开 Vela。一台选择「出示设备码」，另一台选择「添加设备」。输入设备码，或在 Android 上扫码，然后点「连接」。通过可信渠道核对发起方的设备码，再在出示设备码的一端确认配对。
2. 选择要发送的内容和接收设备。可以在 Vela 里发、用 Android 或 macOS 的系统分享菜单，也可以把文件拖进桌面端的 Vela。
3. 接收端确认传输后，可在「接收记录」找到收到的内容。希望自动接收已配对设备的传输时，可以在设置里开启「自动接收」。

需要在使用其他应用时收件，可以在 Android 上开启后台接收，或让桌面端的 Vela 留在菜单栏或托盘。 [后台接收设置](docs/user-guide.zh-CN.md#后台接收)

## 设备怎样连接

同网和跨网时选的是同一台已配对设备。两端的 Vela 都在运行且可以连接时，应用会尽量直连，需要时使用中继。两种路径上的内容都在设备之间加密。

配对信息和接收记录保存在本机。移除设备会撤销本机对它的信任。Vela 默认使用 Iroh 的公共中继，也可以在设置里配置自己的中继。

## 故障排查

可以按遇到的问题查找配对、连接、后台接收和更新的处理步骤。 [故障排查指南](docs/user-guide.zh-CN.md#故障排查)

## 参与贡献

欢迎分享不同设备上的使用结果、改进翻译或提交修复。 [贡献指南与构建说明](CONTRIBUTING.zh-CN.md)

## 许可证

[MIT](LICENSE)。[Cargokit](rust_builder/cargokit/LICENSE) 采用自己的许可证。
