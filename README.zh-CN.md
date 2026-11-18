<p align="center">
  <img src="assets/branding/vela-icon.png" width="96" height="96" alt="Vela 图标">
</p>

<h1 align="center">Vela</h1>

<p align="center"><strong>在你的设备之间分享文件和剪贴板。</strong></p>
<p align="center">配对设备，选择内容，发送。</p>

<p align="center">
  <a href="README.md">English</a> · 简体中文<br>
  <a href="#开始使用">开始使用</a> · <a href="docs/user-guide.md">使用指南（英文）</a> · <a href="CONTRIBUTING.md">参与贡献</a>
</p>

Vela 面向个人设备互联：配对一次，保持后台可用，再主动分享文件、文件夹、文字和剪贴板内容，无需注册账号。项目使用 Flutter、Rust 和 [Iroh](https://www.iroh.computer/)。

**首个公开预览版 [v0.1.0-beta.2](https://github.com/AbyssSkb/Vela/releases/tag/v0.1.0-beta.2) 已发布，支持 Android、macOS、Windows 和 Linux。** CI、安装包构建及 Windows/Linux 启动检查已通过；跨设备收发、后台行为和升级仍需针对本版进行真机验收。

## 可以做什么

- **发送文件和文件夹。** 多选文件，或将文件夹打包发送、在接收端手动还原。传输时显示进度和速度，支持中途取消。
- **分享剪贴板。** 主动发送文字、图片或单个文件，也可以直接输入文字或发送链接。
- **使用熟悉的分享入口。** 支持 Android 和 macOS 系统分享菜单，桌面端可将文件拖入 Vela。
- **管理可信设备。** 输入设备码配对，Android 支持扫码；设备可显示为列表或关系图，移除设备即可撤销本机信任。
- **在后台接收。** Android 可开启后台接收，Mac 使用菜单栏，Windows/Linux 使用系统托盘。默认逐次确认接收，也可在设置中启用自动接收。
- **更新应用。** 发行版本自动检查、下载并验证更新，由用户确认安装；传输或配对期间禁用安装。
- **查找收到的内容。** 搜索本地接收记录，打开文件和链接，自选保存目录。界面支持简体中文和英文。

## 开始使用

### 安装包

下载 **v0.1.0-beta.2**：[版本说明](https://github.com/AbyssSkb/Vela/releases/tag/v0.1.0-beta.2) · [SHA256 校验文件](https://github.com/AbyssSkb/Vela/releases/download/v0.1.0-beta.2/SHA256SUMS)。

| 平台 | 架构 | 下载 |
| --- | --- | --- |
| macOS | Apple Silicon（ARM64） | [DMG](https://github.com/AbyssSkb/Vela/releases/download/v0.1.0-beta.2/Vela-0.1.0-beta.2-macos-arm64.dmg) |
| macOS | Intel（x64） | [DMG](https://github.com/AbyssSkb/Vela/releases/download/v0.1.0-beta.2/Vela-0.1.0-beta.2-macos-x64.dmg) |
| Windows | x64 | [EXE 安装器](https://github.com/AbyssSkb/Vela/releases/download/v0.1.0-beta.2/Vela-0.1.0-beta.2-windows-x64-setup.exe) |
| Linux | x64 | [AppImage](https://github.com/AbyssSkb/Vela/releases/download/v0.1.0-beta.2/Vela-0.1.0-beta.2-linux-x64.AppImage) |
| Android | ARM64 | [APK](https://github.com/AbyssSkb/Vela/releases/download/v0.1.0-beta.2/Vela-0.1.0-beta.2-android-arm64.apk) |

[安装包工作流](https://github.com/AbyssSkb/Vela/actions/workflows/build.yml)另提供保留七天的开发快照，关闭自动更新；Android 预览 APK 使用调试密钥，不能直接覆盖升级到使用正式发布密钥的版本。零成本桌面构建暂不提供 Apple 公证或 Windows Authenticode 发行签名，安装时请按对应版本的说明核验并处理系统提示。发布配置见[发行说明](docs/releasing.md)。

### 从源码运行

开发工具链为 **Flutter 3.47.9 / Dart 3.13.7** 和 **Rust 1.98.1**。Flutter 可从 [SDK 归档](https://docs.flutter.dev/install/archive)安装，Rust 可通过 [rustup](https://rustup.rs/)安装。

| 平台 | 额外要求 |
| --- | --- |
| macOS | macOS 12 及以上、Xcode 及命令行工具、CocoaPods |
| Android | Android SDK、NDK、JDK 17、已连接的手机或模拟器 |
| Windows | Windows x64、Visual Studio 桌面 C++ 工具和 CMake |
| Linux | Linux x64、Clang/CMake/Ninja、GTK 3、libsecret、libnotify、Ayatana AppIndicator 开发包 |

在项目根目录执行：

```sh
flutter pub get --enforce-lockfile
flutter run -d macos
```

Windows/Linux 分别在对应系统执行 `flutter run -d windows` 或 `flutter run -d linux`。运行 Android 版时，先用 `flutter devices` 查看设备，再运行 `flutter run -d <设备 ID>`。Rust 库由项目内的 Cargokit 集成自动构建。

本地磁盘有限时，将完整构建和测试放到 GitHub，轻量检查见[贡献指南](CONTRIBUTING.md)。支持更新的发行版本需要配置发布密钥和更新公钥，具体见[发行说明](docs/releasing.md)。

### 完成第一次传输

1. 在两台设备上打开 Vela。在其中一台的空首页点击“出示本机二维码”，也可通过工具栏或菜单中的“我的设备”查看设备码。
2. 在另一台设备选择“添加设备”，输入设备码或用 Android 扫码。通过可信渠道核对设备码，并确认配对请求。
3. 选择文件、文件夹、文字或剪贴板分享入口，再按提示选择内容和接收设备。
4. 接收端确认后开始传输。文件默认保存到下载目录，可以在设置中更改。

两端应用都需要运行且网络可达。桌面端可用多选按钮，手机端可长按设备进入多选。接收文件和图片会尝试写入剪贴板，能否粘贴取决于目标应用；直接输入发送的文字不会自动覆盖接收端剪贴板，收到 HTTP(S) 链接后可在浏览器打开。Android 还支持通过系统照片选择器多选图片和视频，无需整个相册的读取权限。

删除设备会立即撤销本机信任并关闭相关连接；对方启用在线监测并再次连通时，会同步信任撤销。网络不可达时显示离线。删除接收记录时，可以选择是否同时删除对应文件。

### 后台接收

**Android：**在设置中开启后台接收后，系统会显示常驻通知；收到请求可在通知中接收或拒绝，传输时显示进度。应用持有 CPU 唤醒锁，并在重启、解锁后尝试恢复服务。后台接收页面提供通知、电池限制、自启动和节点状态检查。后台运行会增加耗电，厂商省电策略和强制停止仍可能中断服务；实时通知和状态栏胶囊的样式由系统决定。

**macOS：**关闭窗口后继续在菜单栏运行，选择退出才会结束进程。可开启“后台保持可用”以防止空闲睡眠，屏幕仍可关闭；这会增加耗电，合盖或手动睡眠仍可能中断连接。macOS 13 及以上支持另行开启“登录时启动”，并按系统要求允许登录项。

**Windows/Linux：**默认关闭窗口后继续在托盘运行，点击托盘图标或菜单恢复窗口，从托盘菜单退出才结束接收。设置中可关闭这一行为并配置登录启动；Linux 托盘和通知取决于桌面环境。系统睡眠后无法继续接收。

Android 的后台接收页会在发现已知限制时提供相应的系统设置入口。macOS 的登录启动需要批准时，可以从后台接收页直接打开系统登录项。

### 自动更新

配置完整的发行版本启动后会检查更新，并每隔 12 小时再检查，后台下载验证通过后在设置的“应用更新”入口显示就绪。传输或配对期间安装入口不可用；完成后可点击安装并确认，交由平台安装流程处理。Android 仍需系统安装确认，并可能需要允许 Vela 安装应用。安装说明和已知问题见对应 Release。

## 连接与隐私

Vela 使用 Iroh 尝试建立设备间直连，无法直连时可通过中继转发。默认使用 Iroh 的公共发现和中继服务，也可以在设置中配置自定义中继。

Iroh 对端点之间的通信加密，经中继转发的流量同样如此，详见 [Iroh 传输文档](https://docs.rs/iroh/1.4.1/iroh/#encryption)。Vela 将设备身份密钥保存在系统安全存储中，配对信息与接收记录保存在本机。

## 当前范围

- 当前预览目标为 Android、macOS、Windows 和 Linux；iOS 安排在桌面发行工作之后，浏览器端不在本阶段范围内。
- 剪贴板由用户主动发送，暂限单个文件；多个文件请使用文件选择。
- 文件夹以归档形式发送，接收后手动还原；不接受符号链接。当前限制为未压缩内容 16 GiB、10,000 个条目、64 层嵌套；文件批次最多 100 个文件。
- 后台可用性受系统权限、托盘和省电策略影响；系统睡眠、进程退出或 Android 强制停止可能中断接收，暂未实现推送唤醒。
- 旧配对协议升级后需重新配对；设备身份、已接收文件和历史记录保留。

## 参与贡献

可以从跨平台收发测试、后台和网络问题复现、翻译或小范围修复开始。请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，Issue 和 PR 均可使用中文或英文。

- [使用指南（英文）](docs/user-guide.md)：分享、后台接收、存储和排障。
- [代码结构](docs/architecture.md)：状态所有权、源文件入口和测试范围。
- [发行说明](docs/releasing.md)：远端构建、签名密钥、更新源和发布步骤。
- [首发清单](docs/launch-checklist.md)：发布阻塞项、演示素材和推广准备。

## 许可证

[MIT](LICENSE)。第三方组件保留各自许可证，包括项目内的 [Cargokit](rust_builder/cargokit/LICENSE)。
