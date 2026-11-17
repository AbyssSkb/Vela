# Vela 后台运行研究

调查日期：2026-11-10。本文基于当前源码与系统官方文档；系统限制与不同厂商的行为需要以实际设备测试为准。本次没有修改应用代码或设备设置。

本文保留调查时的源码快照，后续实现可能已经变化；当前功能请参阅项目 README 和源码。

## 目标与结论

Vela 的后台接收依赖一个仍在执行、能使用网络的节点。要分别处理四件事：进程继续运行、休眠期间网络和 CPU 可用、进程被系统回收后恢复、用户登录或重启后再次启动。前台服务解决其中的一部分，不能单独保证长期实时在线。应用也不能保证设备关机、无网络或被用户强制停止后继续接收。

建议先测量后台真实行为，再决定是否引入耗电或影响系统行为的机制。Android 优先验证已有前台服务、Doze、电池限制及系统回收恢复；macOS 优先验证隐藏窗口、App Nap、空闲休眠和唤醒恢复。记录状态事件及实际收件结果，不能仅以进程或通知存在作为成功标准。

## 当前实现

### Android

- [`ReceivingService.kt`](../android/app/src/main/kotlin/com/example/vela/ReceivingService.kt) 启动带持续通知的前台服务，返回 `START_STICKY`；系统以空 Intent 重启时，仅在保存的后台接收设置开启时继续。服务启动无 Activity 的 Flutter 引擎；后台引擎的创建在 [`VelaApplication.kt`](../android/app/src/main/kotlin/com/example/vela/VelaApplication.kt)。
- [`AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml) 声明 `specialUse` 前台服务及描述，`stopWithTask=false`；所查看的 manifest 未声明开机广播接收器和唤醒锁权限。当前不应推断手机重启后会自动启动后台接收。
- [`MainActivity.kt`](../android/app/src/main/kotlin/com/example/vela/MainActivity.kt) 查询电池优化豁免、后台受限和通知状态；[`background_settings.dart`](../lib/background_settings.dart) 展示检查项。`batteryExempt` 不表示 Low Power Standby 已豁免。
- 上次交接记录：Android 35 模拟器 Release 应用在 `kill -9` 后由 Sticky 服务重建引擎和节点，并完成通知接收文字和文件；这是一次受控验证，不代表真机、深度待机或用户强制停止的结果。

### macOS

[`AppDelegate.swift`](../macos/Runner/AppDelegate.swift) 的最后窗口关闭不退出应用，并提供菜单栏入口和主动退出；[`MainFlutterWindow.swift`](../macos/Runner/MainFlutterWindow.swift) 监听系统唤醒和网络路径变化，通知 Flutter。 [`main.dart`](../lib/main.dart) 在唤醒时触发节点和在线状态的恢复流程。所查看的 Runner 源码没有发现 `SMAppService` 注册或防空闲休眠断言；这不代表系统其他设置没有影响。整机深度休眠及唤醒后的端到端恢复仍待实测。

## Android：可用机制与限制

### 前台服务和系统回收

用户明确开启后台接收时，持续通知对应持续等待对端的用户可见任务。`START_STICKY` 表示服务进程被系统杀死后系统会稍后尝试重建；下一次调用可能带空 Intent。Android 12 起的后台新启动前台服务限制不妨碍系统重启已有 Sticky 前台服务，但仍限制应用主动从后台新启动。官方没有给出重建时限。[Service API](https://developer.android.com/reference/android/app/Service#START_STICKY)；[后台启动限制](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)。

用户在 Android 13 的“活跃应用”任务管理器按停止，会停止整个进程且没有回调；此前调度的任务和闹钟仍可能运行。这与应用详情里的**强制停止**不同：强制停止进入 stopped 状态，需用户直接或间接交互解除；Android 15 还会取消 pending intents。不要以定时器或循环重启绕开用户停止意图。[用户停止前台服务](https://developer.android.com/develop/background-work/services/fgs/handle-user-stopping)；[Android 15 stopped 状态](https://developer.android.com/about/versions/15/behavior-changes-all#stopped-state)。

### Doze、Low Power Standby 和厂商限制

Doze 可暂停网络、忽略 wake lock，并延迟普通闹钟及 WorkManager 调度。电池优化豁免是**部分豁免**：允许应用在 Doze / App Standby 使用网络和持有 partial wake lock，但其他限制仍可能适用。保持 wake lock 会消耗电量，应先测出 CPU 休眠是否真的导致接收失败，再评估是否需要、何时持有和释放。Google Play 对直接请求豁免也有使用条件，不能仅因希望常驻就认定适用。[Doze 官方指南](https://developer.android.com/training/monitoring-device-state/doze-standby)。

Low Power Standby 是另一项限制：开启后，设备处于非交互状态且不在维护窗口时，即使应用有前台服务，网络也可能被禁用，wake lock 被忽略。API 33 的 `isLowPowerStandbyEnabled()` 查询功能开关；API 34 的 `isExemptFromLowPowerStandby()` 查询调用包是否豁免或该功能是否关闭。`isIgnoringBatteryOptimizations()` 不能单独证明 LPS 豁免；诊断应分别记录这些状态，并结合实际网络结果。[PowerManager](https://developer.android.com/reference/android/os/PowerManager#isLowPowerStandbyEnabled())。

后台受限与厂商策略也可能影响前台服务、任务和自启动；限制细节由设备厂商决定。AOSP 的 restricted 状态可能移除服务的前台状态并禁止后台启动，不能假定所有 ROM 一致。[后台优化](https://developer.android.com/topic/performance/background-optimization)。

### 服务类型、开机启动与推送

现用类型是 `specialUse`。官方对 `connectedDevice` 的描述覆盖与外部设备经网络交互，本地网络设备传输是明确例子，并要求声明对应前台服务权限且满足至少一项前提。Vela 也有跨网络路径，是否适合该类型、发布时如何声明应按实际产品行为评估，不能只为了规避限制而改类型。[前台服务类型](https://developer.android.com/develop/background-work/services/fgs/service-types)；[数据传输方案](https://developer.android.com/develop/background-work/background-tasks/data-transfer-options)。

面向 Android 15 或以上的应用，其 `dataSync` 前台服务在后台有每 24 小时累计 6 小时限制，并禁止从 `BOOT_COMPLETED` 启动该类型；这个 6 小时限制目前适用于 `dataSync` 和 `mediaProcessing`，不能泛化到所有类型。开机广播能否用于当前类型还需结合实际目标版本、用户意图、ROM 及凭据解锁时序测试。开机自启是独立功能选择，不等于系统回收后的 Sticky 重建。[前台服务超时](https://developer.android.com/develop/background-work/services/fgs/timeout)；[Android 15 行为变化](https://developer.android.com/about/versions/15/behavior-changes-15#fgs-boot-completed)。

FCM 高优先级消息可尝试唤醒设备做有限处理，适合需要用户可见通知的及时事件；反复发送无通知的静默消息会面临降级，不适合在线状态心跳。引入它还需要发送端服务和 Google 服务，改变 Vela 的依赖，且不保证所有设备、网络和强制停止场景均能送达。WorkManager 面向可延后任务，不能用作秒级接收保障；Android 16 起从前台服务发起的任务也受相应配额限制。[FCM 优先级](https://firebase.google.com/docs/cloud-messaging/android-message-priority)；[前台服务变更](https://developer.android.com/develop/background-work/services/fgs/changes)。

## macOS：可用机制与限制

- **窗口关闭与进程退出**：目前关闭最后窗口可继续运行。用户主动退出应保持明确退出语义；若未来引入辅助进程，应让用户能够停止其后台活动。[Apple 后台进程指南](https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac)。
- **App Nap**：Apple 的归档文档描述后台不可见应用可能受到计时器、CPU 和 I/O 节流。它与整机睡眠不同，菜单栏图标本身不能证明心跳不受节流；先测 App Nap 状态和实际收发，再考虑针对明确活动使用 `ProcessInfo` activity，结束时释放。[App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)；[工作优先级](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheAppLevel.html)。
- **登录启动**：macOS 13 起可评估可选的 `SMAppService.mainApp` 登录项。注册受用户批准与系统设置控制；主应用将在后续登录时启动，不是退出或崩溃后的常驻重启保证。[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)；[register](https://developer.apple.com/documentation/servicemanagement/smappservice/register()).
- **系统睡眠**：有明确用户需求时可考虑仅在实际传输期间持有防空闲系统休眠 activity / assertion，结束即释放，避免为监听永久阻止系统休眠。Apple 的归档说明区分空闲睡眠与合盖、手动睡眠等强制睡眠：断言不能保证阻止强制睡眠。显示器休眠和系统休眠也应分别处理。[Apple 睡眠通知与断言](https://developer.apple.com/library/archive/qa/qa1340/_index.html)。

## 建议的无破坏性测试矩阵

测试优先使用隔离模拟器和临时 Rust 对端；真机测试应避免改变用户代理、中继和网络配置。记录机型、系统版本、target SDK、后台接收和电池设置、进程及服务状态、事件时间、发送与接收结果、电量变化；不记录认证秘密。每项分别记录失败次数和延迟分布，少量样本不能证明最坏上界。

| 场景 | 操作与验证 |
| --- | --- |
| Android 后台和锁屏 | 开启接收后退后台、关闭屏幕；从对端发送文字和文件，检查通知、接受、内容与延迟。分别测试短时和长时锁屏。 |
| Android Doze | 在隔离设备进入强制 Doze，分别测优化默认与用户授权的豁免；核对网络和接收、恢复，结束后还原模拟电池与 idle 状态。不要只看前台通知。 |
| Android Low Power Standby | 记录开关、包豁免和交互状态，区分支持 API 版本；在支持的隔离环境分别测实际收件与退出后的恢复。不要用电池豁免值代替 LPS 状态。 |
| Android 系统回收 | 隔离环境杀进程，检查服务是否重建、身份是否保持、对端能否再次发送。分别测试无 Activity 与任务划走；与用户主动停止分开。 |
| Android 限制与重启 | 独立检查后台 restricted、通知关闭、系统重启和重新登录后行为；修改测试设置前保存原值，结束后恢复。强制停止只在隔离应用测试，验证用户重新打开后的恢复。 |
| macOS 后台与 App Nap | 隐藏窗口并维持菜单栏；对端周期发送，记录 App Nap 状态、在线事件和实际接收，与窗口可见时对照。 |
| macOS 休眠与唤醒 | 在隔离测试时段测试空闲睡眠、手动睡眠及唤醒，核对网络重连、节点恢复和收到新文件；不将显示器关闭等同系统睡眠。检查 `pmset -g assertions` 是否有预期外的睡眠断言。 |
| 长时间资源成本 | 在相同网络和电量条件下比较前台接收开关关闭/开启的电池、CPU 和网络占用；明确保持低延迟所需的代价。 |

执行系统电源状态注入时使用专用模拟器或事先确认环境，并在结束后还原；不要在用户正在使用的 Mac 上擅自睡眠、退出应用或修改登录项。
