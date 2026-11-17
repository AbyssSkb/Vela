# 从哪里理解 Vela

Vela 的一条主线是：选择内容 → 选择可信设备 → 对端确认 → 传输 → 保存与记录。Flutter 负责用户交互与编排，Rust 负责通信、信任会话和文件传输，原生代码负责系统能力。

## 先读这些文件

| 你要理解什么 | 入口 | 它拥有的状态 |
|---|---|---|
| 应用入口、页面和用户确认 | `lib/main.dart` | 页面状态、当前传输任务、用户确认 |
| 节点启动、身份和关闭 | `lib/app_runtime.dart` | 当前节点、设备存储、启动代次、资源接管与释放 |
| 在线状态的展示与同步 | `lib/presence_controller.dart` | 快照订阅、设备会话身份、探测、重试和定时器 |
| 可信设备的持久化与同步 | `lib/paired_devices.dart` | 设备快照、写入队列、信任同步重试 |
| 设备数据及保存 | `lib/peer_state.dart`、`lib/peer_store.dart` | 不可变设备数据、SQLite 完整快照 |
| 配对取消和同时发起的仲裁 | `lib/pairing_session.dart` | 每次配对的取消信号、网络 handle、方向仲裁 |
| 分享来源、临时文件和重试 | `lib/pending_share.dart`、`lib/prepared_transfer.dart`、`lib/send_session.dart` | 来源、内容快照、临时文件、单次重试机会 |
| 内容类型和错误结果 | `lib/content_kind.dart`、`lib/transfer_failure.dart` | 协议/历史类型转换、稳定错误码解析 |
| 接收文件的系统访问 | `lib/received_storage.dart` | 本地路径与文档 URI 的访问规则、通道解码 |
| 更新检查、下载和安装编排 | `lib/app_update.dart` | 更新状态、版本与签名验证、下载缓存、安装前忙碌门禁 |
| Windows/Linux 桌面基础能力 | `lib/desktop_platform.dart`、`lib/peer_store.dart` | 后台设置恢复、图片剪贴板入口、生产 SQLite FFI 后端 |
| Rust 对 Flutter 的接口 | `rust/src/api/node.rs` | 节点、请求、配对与传输任务的公开类型 |
| 连接建立和请求分派 | `rust/src/api/node/runtime.rs` | Iroh endpoint、监听任务、入站请求队列 |
| 单次传输 | `rust/src/api/node/transfer.rs`、`outgoing_transfer.rs`、`incoming_request.rs` | 任务的取消、连接、进度和单次执行权 |
| 配对和信任会话 | `rust/src/api/node/pairing.rs`、`rust/src/trust.rs` | 配对尝试、可信会话和撤销规则 |
| 在线监测与恢复 | `rust/src/presence.rs`、`rust/src/proof_clock.rs` | 在线证据、连接候选、网络代次与跨睡眠计时 |
| 文件夹的安全文件操作 | `rust/src/api/folder.rs`、`folder_windows.rs` | 归档限制、拒绝链接、独占创建与不覆盖还原 |
| Android 系统能力 | `VelaApplication.kt`、`AppChannels.kt`、`MainActivity.kt` | 共享 FlutterEngine、固定通道、Activity 交互 |
| macOS 窗口与菜单 | `MainFlutterWindow.swift`、`AppDelegate.swift` | 窗口、通道注册、菜单显示优先级 |
| macOS 接收目录与分享暂存 | `Runner/ReceiveDirectoryAccess.swift`、`Shared/ShareInbox.swift` | 目录授权、分享清单和暂存目录；分享扩展复用清单规则 |
| 桌面托盘、通知与登录启动 | `windows/runner/desktop_integration.cpp`、`linux/runner/desktop_integration.cc` | 窗口可见性、托盘与通知、系统事件、正常退出握手 |
| 原生更新安装 | `macos/Runner/AppUpdater.swift`、`windows/runner/updater.cpp`、`linux/runner/updater.cc` | 平台更新接口、安装器与退出/重启配合 |
| 远端构建与发布 | `.github/workflows/`、`tool/release/`、`packaging/` | 目标构建、安装包、签名更新源与草稿发布 |
| 调试驱动入口 | `lib/debug_driver.dart` | debug 模式下双实例测试的命令分派 |

Android 文件位于 `android/app/src/main/kotlin/com/example/vela/`；macOS 主应用文件位于 `macos/Runner/`。`lib/src/rust/`、`rust/src/frb_generated.rs` 和 `lib/l10n/generated/` 是生成代码，从对应源文件修改后重新生成。

## 五条流程

**启动：**`main` 初始化 Rust bridge，`AppRuntime.start` 加载身份、设备快照并启动节点，同步信任和设备信息，成功后接管节点与存储。页面接入入站请求，`PresenceController.attach` 接入在线快照。关闭时先使旧结果失效，排空设备事务，再关闭旧节点；启动中途被关闭的资源由启动流程自行释放。

**配对：**用户发起或收到配对请求，进入配对状态并隔离旧会话；双方确认握手后，通过 `PairedDevices` 持久化设备并同步信任，最后结束配对状态。握手成功和设备已持久化是两个步骤。`OutgoingPairingSession` 成组持有仲裁、取消和网络 handle；`IncomingPairingSession` 持有入站取消信号。`pairingTransitions` 串行化同一设备的进入/退出操作，不是另一份配对状态。

| 阶段 | 操作 | 结束规则 |
|---|---|---|
| 隔离旧会话 | `beginPairing` | 此时尚未授予新信任 |
| 可取消的网络握手 | `beginOutgoingPairing` / 接受入站请求 | 取消可以早于网络 handle 创建 |
| 提交设备 | `PairedDevices.pair` | 持久化成功后同步新信任 |
| 结束隔离 | `endPairing` | 同一设备的所有当前配对结束后执行 |

**发送与接收：**来源先转成 `PendingShare` 或准备好的 `PreparedTransfer`；每次通信创建一个 `TransferJob`。任务同时提供发送、取消和进度；接收请求也显式使用一个任务。`SendSession` 持有一次发送的内容和来源释放操作，成功后释放两者；失败后 `SendRetry` 只能领取一次，放弃时释放临时内容。旧提示关闭不能释放新重试的内容。Android 收到的文件先落在应用目录，再经 `ReceivedStorage` 保存到用户位置；结果中的 `reference` 可能是文档 URI，后续存在、打开、删除和导出均交给该模块。

**在线与后台：**Rust 接受经过验证的响应，更新带有效期的在线证据，`PresenceController` 根据快照和有效期维护展示状态。`readSnapshot` 只读取已有证据，`probePeers` 主动探测；系统网络变化通过 `networkChanged` 协调，恢复必须先使旧证据失效。Rust 的 `send_tracked_probe` 发送探测，`on_network_changed` 推进网络代次，`request_probe` 只请求探测；统计开关不控制这些业务动作。Android 的 Service 可以启动无 Activity 的同一个 FlutterEngine，仍运行普通 Dart `main`；通道由 Application 安装一次，Activity 只补充权限和选择器等交互能力。

**更新：**`AppUpdateController` 在配置完整的发行版本中检查更新。macOS 通过自定义 Sparkle driver 接入共同的更新状态；Windows/Linux/Android 验证签名清单、流式下载并核对长度和 SHA-256，再调用原生安装流程。Windows 运行已验证安装器，Linux 通过独立 helper 替换整个 AppImage，Android 调用系统安装器。当前传输、文件夹处理或配对会阻止安装，安装前排空节点与持久化事务。打包脚本先生成完整草稿 Release，发布版本资源后再刷新 `updates` 更新源。

## 跨语言约定

- `TransferKind` 表达网络传输类型，`HistoryKind` 表达历史展示类型；转换集中在 `content_kind.dart`。持久化和线上字符串保持原格式，`batch` 的每个接收文件记录为 `file`，文件夹归档由文件类型和 `.vela-folder.zip` 后缀共同识别。
- Rust 的 `failure_code.rs` 发出 `[vela:cancelled]`、`[vela:declined]`、`[vela:save_failed]`、`[vela:pairing_declined]`；Dart 在 `transfer_failure.dart` 解析。前缀是接口约定，后续说明文字可修改。保留现有 bridge 的 `anyhow` 返回方式，无需为此修改生成代码。
- 在线报文在 `rust/src/protocol.rs` 编解码。业务循环处理消息类型，不重复解释字节偏移。
- macOS 菜单分别接收 `setNodeStatus`、`setTransferring` 和入站通知事实；传输结束不会覆盖节点失败状态。
- Windows/Linux 复用 `vela/background` 的可见性、网络/唤醒和退出事件；Linux 图片剪贴板通过 `vela/clipboard`，不依赖原有插件的空写入实现。原生更新通道为 `vela/update`。

## 修改时需要守住的规则

- 设备集合变化先收缩信任，再持久化，发布新快照后再授予新增信任；写失败恢复旧信任。旧异步结果不能用于重新配对后的新会话。
- 一个节点同时只允许一个传输任务。任务单次使用，取消可以发生在异步执行开始之前；旧任务的取消和进度不能影响新任务。
- 连接存在、在线证据有效、对方仍信任本机是不同事实。统计记录不负责更新这些事实。
- 用户原文件和应用临时文件具有不同所有权；重试仍要使用原内容快照。macOS 分享暂存和访问凭据、Android content URI 的物化与授权都需要显式清理。
- `displayPath` 用于展示；桌面端的 `directoryPath` 才是可用于文件 IO 的目录。Android 文档 URI 不等于本地文件路径。
- 更新公钥与设备身份密钥用途不同。发行密钥不能每次构建重建；安装包、数据目录和设备身份不能因更新被清空。失败的签名验证不得触发安装。

## 数据放在哪里

| 数据 | 保存位置与所有者 |
|---|---|
| 设备身份密钥、中继认证信息 | `AppRuntime` 使用系统安全存储 |
| 可信设备、名称、类型和别名 | `PeerStore` 的 `peer_state_v2.sqlite3`，按 profile 保存完整快照 |
| 历史记录与普通设置 | `SharedPreferences`；历史由 `TransferHistoryStore` 维护 |
| 接收文件 | 用户选择的保存位置；Android 的 URI 操作由原生层处理 |
| 分享和剪贴板临时内容 | 来源准备阶段创建，由发送内容的所有权信息及平台暂存凭据决定清理 |

## 用哪些测试确认修改

| 修改范围 | 优先阅读与运行 |
|---|---|
| 设备持久化、撤销信任、配对竞态 | `test/paired_devices_test.dart`、`test/pairing_*_test.dart`、`test/startup_*_test.dart` |
| 节点与在线状态所有权 | `test/app_runtime_test.dart`、`test/presence_controller_test.dart` |
| 来源解码、临时文件和重试 | `test/pending_share_test.dart`、`test/prepared_transfer_test.dart`、`test/home_responsive_layout_test.dart` |
| 接收和剪贴板行为 | `test/link_receive_test.dart` |
| 存储通道及 URI 访问 | `test/received_storage_test.dart` |
| Windows/Linux 保存目录与后台设置 | `test/received_storage_desktop_test.dart`、`test/background_settings_test.dart`、`test/peer_store_test.dart` |
| 更新清单、下载、忙碌与安装门禁 | `test/app_update_test.dart` |
| 更新源和打包规则 | `tool/release/test_release.py`、`packaging/linux/test_package.py` |
| Rust 传输、取消和协议验证 | `rust/src/api/node_tests.rs` |
| 在线证据、候选竞速与恢复 | `rust/src/presence*_tests.rs`、`rust/src/proof_clock_tests.rs` |
| Android 通道、后台与系统分享 | 原生单测以及 `test_driver/android_*.dart`、`notification_actions.dart` |
| macOS 菜单、后台与分享数据 | `macos/RunnerTests/RunnerTests.swift` 和 `test_driver/mac_*.dart` |

共享 Dart 测试替身在 `test/support/fakes.dart`。常规验证命令见 CONTRIBUTING；完整 Flutter/Rust 编译和安装包构建优先运行 GitHub 工作流，真实后台、升级和跨设备测试需要运行应用。

磁盘空间受限时，可直接用已有 Dart SDK 执行 `dart --disable-dart-dev tool/check_core_contracts.dart`。它以内存替身检查内容类型、错误码和发送重试的清理规则，不创建测试文件或构建缓存；它不覆盖 Flutter、Rust 编译或平台行为。
