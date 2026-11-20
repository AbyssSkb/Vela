# 后台接收技术说明

[English](background-execution-research.md)

后台收件需要 Vela 节点在运行，并能和对端建立连接。排查时分开看应用退到后台、系统进入休眠、系统回收进程、用户退出，以及重启后恢复。每种情况都用一次实际收件来验证。 [后台接收使用指南](user-guide.zh-CN.md#后台接收)

## 当前实现

| 平台 | Vela 怎么保持可用 |
| --- | --- |
| Android | 开启后台接收后，`ReceivingService` 运行前台服务并持有部分唤醒锁。系统重建服务时读取已保存的设置。重启后首次解锁，`BootReceiver` 收到 `BOOT_COMPLETED` 后按同一设置启动服务。 |
| macOS | 窗口关闭后保留进程和菜单栏入口。可选的「后台保持可用」阻止空闲系统睡眠。macOS 13 起可以配置登录启动，由系统管理登录项。网络变化和唤醒事件会通知 Flutter 恢复节点和在线状态。 |
| Windows / Linux | 后台接收开启且托盘可用时，关闭窗口后应用继续在托盘运行。窗口、通知和退出由桌面集成层协调。 |

Android 的接收服务可启动共享 FlutterEngine，即使前台没有 Activity。macOS 的可用性设置和登录启动各自检查状态。 [ReceivingService.kt](../android/app/src/main/kotlin/com/example/vela/ReceivingService.kt) · [BootReceiver.kt](../android/app/src/main/kotlin/com/example/vela/BootReceiver.kt) · [AppDelegate.swift](../macos/Runner/AppDelegate.swift) · [MainFlutterWindow.swift](../macos/Runner/MainFlutterWindow.swift)

## Android 的系统限制

- **前台服务。** 当前声明的类型是 `specialUse`。`START_STICKY` 允许系统在回收进程后尝试重建服务，回调可能携带空 Intent。应用从后台主动启动新服务则受 Android 12 起的启动限制。评估 `connectedDevice` 或其他服务类型时，先核对 Vela 的真实用途和所需权限。 [Service API](https://developer.android.com/reference/android/app/Service#START_STICKY) · [后台启动限制](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start) · [服务类型](https://developer.android.com/develop/background-work/services/fgs/service-types)
- **重启和主动停止。** 首次解锁后，Vela 可以加载受凭据保护的身份与配对数据。之后再次锁屏时，数据仍可访问。对于以 API 33 或以上为目标的应用，Android 13 起的「受限」电池模式可能延迟开机广播。用户主动停止 Vela 后，接收可以停止。 [Direct Boot](https://developer.android.com/privacy-and-security/direct-boot) · [开机启动限制](https://developer.android.com/about/versions/15/behavior-changes-15#fgs-boot-completed) · [后台电池受限](https://developer.android.com/about/versions/13/behavior-changes-13#battery-resource-utilization) · [主动停止应用](https://developer.android.com/develop/background-work/services/fgs/handle-user-stopping)
- **熄屏和电池优化。** 部分唤醒锁可以在屏幕关闭时保持 CPU 运行。Doze 仍可限制网络。用户开启后台接收后，可在 Vela 点「允许锁屏接收」，由系统确认是否豁免电池优化。豁免允许 Doze 期间继续使用网络和部分唤醒锁。低功耗待机是独立的系统策略，可以另外限制网络。 [Doze 与豁免](https://developer.android.com/training/monitoring-device-state/doze-standby) · [系统确认入口](https://developer.android.com/reference/android/provider/Settings#ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS) · [低功耗待机](https://developer.android.com/reference/android/os/PowerManager#isLowPowerStandbyEnabled())
- **网络恢复和通知。** 默认网络解禁后，Vela 复用已有的网络恢复逻辑。需要手动接受文件时，系统的通知权限和锁屏通知设置还决定请求能否在锁屏上看到。 [Android 网络回调](https://developer.android.com/reference/android/net/ConnectivityManager.NetworkCallback#onBlockedStatusChanged(android.net.Network,%20boolean)) · [通知权限](https://developer.android.com/develop/ui/views/notifications/notification-permission) · [锁屏显示](https://developer.android.com/develop/ui/views/notifications/build-notification#lockscreenNotification)
- **调度和推送。** 应用以 Android 15 或更高版本为目标时，`dataSync` 和 `mediaProcessing` 前台服务各有每 24 小时累计 6 小时的后台时限。`dataSync` 还受到开机启动限制。WorkManager 适合可以延后的任务。FCM 高优先级消息适合有用户可见通知的及时事件，引入后需要另行评估基础设施、覆盖范围和系统限制。 [前台服务超时](https://developer.android.com/develop/background-work/services/fgs/timeout) · [Android 15 行为变化](https://developer.android.com/about/versions/15/behavior-changes-15#fgs-boot-completed) · [FCM 优先级](https://firebase.google.com/docs/cloud-messaging/android-message-priority)

### 一加 13（ColorOS 中国版）

先用标准电源模式测试。ColorOS 15 起的省电模式可以限制后台运行。进入 Vela 的应用详情，在耗电管理里检查后台运行和自启动。不同固件的名称可能变化。澎湃 OS 和 One UI 的入口见[使用说明](user-guide.zh-CN.md#后台接收)。 [OPPO 省电模式](https://support.oppo.com/cn/answer/?aid=SI2105920) · [OPPO 耗电管理设置示例](https://consumer.huawei.com/cn/support/content/zh-cn15848664/)

## macOS 的系统限制

App Nap 会影响不可见应用的计时与资源调度。菜单栏存在时也应测试实际收件。另行记录显示器关闭、空闲系统睡眠、手动睡眠和合盖。防空闲睡眠的 activity 针对空闲睡眠。使用 `SMAppService.mainApp` 的登录项在用户下次登录时生效，由系统设置控制。 [App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html) · [睡眠与电源断言](https://developer.apple.com/library/archive/qa/qa1340/_index.html) · [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)

## 怎样验证

| 场景 | 记录和验证 |
| --- | --- |
| 后台、短时和长时锁屏 | 发送文字和文件，核对请求通知、接受操作、内容和延迟。 |
| Android Doze / Low Power Standby | 在隔离设备分别测试两种限制。记录系统状态、豁免、实际收件和退出限制后的恢复。 |
| Android 重启 | 开启后台接收后重启，首次解锁后保持 Vela 未打开，从已经配对的设备发送文件并核对最终保存内容。关闭后台接收后重试，确认重启不会启动服务。 |
| Android 进程回收 | 检查系统回收进程后是否重建服务和节点。另记用户主动结束应用及重新打开的结果。 |
| macOS App Nap、合盖与唤醒 | 分别记录窗口可见、菜单栏、系统睡眠和唤醒情况。用 `pmset -g assertions` 检查空闲睡眠断言。 |
| Windows/Linux 托盘与睡眠 | 关闭窗口后从托盘恢复，测试通知确认，并检查睡眠或退出登录后的重连。 |
| 资源开销 | 在相同网络和电量条件下比较后台设置开关前后的耗电、CPU、网络和收件延迟。 |

2026-11-10 的 Android 35 模拟器记录显示，Sticky 服务在系统进程终止后重建了引擎与节点，并收到了文字和文件。该记录对应当时的模拟器环境。新的候选版本应记录实际结果。修改电池、休眠或登录设置时使用隔离设备，并在测试后恢复。 [发布验收清单](launch-checklist.zh-CN.md)
