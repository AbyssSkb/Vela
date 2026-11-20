# 参与贡献

[English](CONTRIBUTING.md)

可以测试不同的设备组合、复现问题、改进翻译或修复缺陷。Issue 和 PR 都可以使用英文或中文。

## 反馈问题

先搜索已有 Issue，再用问题报告表单反馈。提供足够的信息，让使用相同设备的人能复现。 [提交 Issue](https://github.com/AbyssSkb/Vela/issues/new/choose)

- 写明两端的 Vela 版本、设备型号和操作系统。
- 说明你做了什么、预期结果和实际结果。
- 如果涉及连接或后台接收，附上发送方向、网络或 VPN，以及两端应用当时是打开、在后台还是刚从睡眠中唤醒。Android 还需注明厂商和相关电池设置。
- 从日志和截图里移除设备码、二维码、凭据、IP 地址、个人路径和内容。安全漏洞请用私密渠道报告。 [安全报告](SECURITY.zh-CN.md)

## 开发环境

使用和 CI 一致的 Flutter **3.47.9**（Dart **3.13.7**）以及 Rust **1.98.1**。可以从 SDK 归档安装 Flutter，用 rustup 安装 Rust。 [Flutter SDK 归档](https://docs.flutter.dev/install/archive) · [rustup](https://rustup.rs/)

| 目标平台 | 构建要求 |
| --- | --- |
| Android | Android SDK、NDK、JDK 17，已连接的设备或模拟器 |
| macOS | macOS 12 或更新版本、Xcode 和命令行工具、CocoaPods |
| Windows x64 | Visual Studio 桌面 C++ 工具和 CMake |
| Linux x64 | Clang、CMake、Ninja、GTK 3、libsecret、libnotify 和 Ayatana AppIndicator 开发包 |

在仓库根目录下载依赖并列出设备。

```sh
flutter pub get --enforce-lockfile
flutter devices
```

用列表里的设备 ID 运行 `flutter run -d DEVICE_ID`。Windows、Linux 和 macOS 目标在对应操作系统上构建。Flutter 构建过程中，Cargokit 会构建 Rust 库。 [代码架构与测试入口](docs/architecture.zh-CN.md)

### iPhone 和 iPad 预览

iOS 工程面向 iOS 和 iPadOS 15 或更新版本的前台配对和传输。在装有 iOS 模拟器工具的 Mac 上运行 `flutter build ios --simulator --debug --no-codesign`，即可为模拟器构建。要在自己的设备上试用，在 Xcode 打开 `ios/Runner.xcworkspace`，选择 Personal Team 并使用唯一的应用标识。免费签名的描述文件七天后到期。模拟器工作流无需签名账号即可验证 iPad 启动。[Apple 开发者账号](https://developer.apple.com/help/account/basics/about-your-developer-account)

### macOS 本地签名

临时签名的开发包在重建后可能再次弹出钥匙串提示。需要固定本地签名身份时，在 `macos/Runner/Configs/LocalSigning.xcconfig` 中加上下面的配置，并填写证书指纹。

```xcconfig
VELA_CODE_SIGN_IDENTITY = certificate SHA-1 fingerprint
VELA_CODE_SIGN_STYLE = Manual
```

开发构建中的应用和分享扩展都会使用这个身份。Git 会忽略这个配置文件。私钥保存在钥匙串中。

## 修改代码

协议、平台支持和大型功能的改动先在 Issue 中讨论。每个 PR 处理一项逻辑变更。行为变化要有针对性的回归测试，并保护用户数据、配对确认、取消和撤销信任的行为。 [英文 PR 模板](.github/pull_request_template.md) · [中文 PR 模板](.github/pull_request_template.zh-CN.md)

- 自维护的文档有英文和简体中文版。默认文件名使用英文，翻译文件加 `.zh-CN`，修改时同步两个版本。
- 在 `lib/l10n/app_en.arb` 和 `lib/l10n/app_zh.arb` 修改界面文字，然后运行 `flutter gen-l10n`。
- Rust 桥接变更先改 Rust API，再用 `flutter_rust_bridge_codegen` **2.13.0** 和 `flutter_rust_bridge.yaml` 重新生成。生成文件位于 `lib/src/rust/` 和 `rust/src/frb_generated.rs`。
- 依赖变更和对应锁文件一起提交。本地配置、签名密钥、设备身份、中继凭据和接收文件留在提交之外。

## 验证

先运行 `git diff --check` 和覆盖改动的检查。下面的命令使用已安装的工具，无需构建原生应用。

```sh
dart --disable-dart-dev tool/check_core_contracts.dart
dart format --output=none --set-exit-if-changed lib test test_driver tool
cargo fmt --manifest-path rust/Cargo.toml --check
python3 -m unittest discover -s tool/release -p 'test_*.py'
python3 -m unittest discover -s packaging/linux -p 'test_*.py'
```

完整的 Flutter 分析、Flutter 和 Rust 测试、安装包构建都可以在 GitHub 上运行。Flutter 测试使用 Rust 和平台接口的测试替身。系统分享、休眠、后台接收、更新或网络相关的变更，应记录实际跑过的设备检查和结果。`test_driver/` 中的双实例调试驱动可能会修改系统剪贴板。 [CI](https://github.com/AbyssSkb/Vela/actions/workflows/ci.yml) · [安装包](https://github.com/AbyssSkb/Vela/actions/workflows/build.yml) · [外部中继测试](.github/workflows/relay-tests.yml)

## 发布相关变更

涉及发布或安装的变更，使用已签名的安装包验证更新。检查身份和文件保留、忙碌时的安装门禁，以及对篡改包的拒绝。 [发布流程](docs/releasing.zh-CN.md)

贡献采用项目的 [MIT 许可证](LICENSE)。
