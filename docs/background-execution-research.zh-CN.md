# 后台接收技术说明

[English](background-execution-research.md)

后台收件需要 Vela 节点在运行，并能和对端建立连接。排查时分开看应用退到后台、系统进入休眠、系统回收进程、用户退出，以及重启后恢复。每种情况都用一次实际收件来验证。 [后台接收使用指南](user-guide.zh-CN.md#后台接收)

## 当前实现

| 平台 | Vela 怎么保持可用 |
| --- | --- |
| Android | 开启后台接收后，`ReceivingService` 启动前台服务，保留常驻通知并持有 partial wake lock。系统重建 Sticky 服务时读取已保存的设置。设备启动后收到 `BOOT_COMPLETED` 时，`BootReceiver` 也会按该设置尝试启动服务。 |
| macOS | 窗口关闭后保留进程和菜单栏入口。可选的「后台保持可用」阻止空闲系统睡眠。macOS 13 起可以配置登录启动，由系统管理登录项。网络变化和唤醒事件会通知 Flutter 恢复节点和在线状态。 |
| Windows / Linux | 后台接收开启且托盘可用时，关闭窗口后应用继续在托盘运行。窗口、通知和退出由桌面集成层协调。 |

Android 的接收服务可启动共享 FlutterEngine，即使前台没有 Activity。macOS 的可用性设置和登录启动各自检查状态。 [ReceivingService.kt](../android/app/src/main/kotlin/com/example/vela/ReceivingService.kt) · [BootReceiver.kt](../android/app/src/main/kotlin/com/example/vela/BootReceiver.kt) · [AppDelegate.swift](../macos/Runner/AppDelegate.swift) · [MainFlutterWindow.swift](../macos/Runner/MainFlutterWindow.swift)

## Android 的系统限制

- **前台服务。** 当前声明的类型是 `specialUse`。`START_STICKY` 允许系统在回收进程后尝试重建服务，回调可能携带空 Intent。应用从后台主动启动新服务则受 Android 12 起的启动限制。评估 `connectedDevice` 或其他服务类型时，先核对 Vela 的真实用途和所需权限。 [Service API](https://developer.android.com/reference/android/app/Service#START_STICKY) · [后台启动限制](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start) · [服务类型](https://developer.android.com/develop/background-work/services/fgs/service-types)
- **用户停止。** Android 的「活跃应用」停止操作会结束进程。应用详情中的「强制停止」还会进入 stopped 状态，等待用户再次与应用交互。分别测试系统回收、用户停止和用户重新打开。 [停止前台服务](https://developer.android.com/develop/background-work/services/fgs/handle-user-stopping) · [Android 15 stopped 状态](https://developer.android.com/about/versions/15/behavior-changes-all#stopped-state)
- **电源状态。** Doze 会影响网络、wake lock 和调度。电池优化豁免仅放宽部分限制。Low Power Standby 独立于 Doze，即使有前台服务，也可能在非交互状态暂停网络。记录 LPS 开关与包豁免，另记电池优化豁免和厂商后台限制。 [Doze 和 App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby) · [PowerManager](https://developer.android.com/reference/android/os/PowerManager) · [后台优化](https://developer.android.com/topic/performance/background-optimization)
- **调度和推送。** 应用以 Android 15 或更高版本为目标时，`dataSync` 和 `mediaProcessing` 前台服务各有每 24 小时累计 6 小时的后台时限。`dataSync` 还受到开机启动限制。WorkManager 适合可以延后的任务。FCM 高优先级消息适合有用户可见通知的及时事件，引入后需要另行评估基础设施、覆盖范围和系统限制。 [前台服务超时](https://developer.android.com/develop/background-work/services/fgs/timeout) · [Android 15 行为变化](https://developer.android.com/about/versions/15/behavior-changes-15#fgs-boot-completed) · [FCM 优先级](https://firebase.google.com/docs/cloud-messaging/android-message-priority)

## macOS 的系统限制

App Nap 会影响不可见应用的计时与资源调度。菜单栏存在时也应测试实际收件。另行记录显示器关闭、空闲系统睡眠、手动睡眠和合盖。防空闲睡眠的 activity 针对空闲睡眠。使用 `SMAppService.mainApp` 的登录项在用户下次登录时生效，由系统设置控制。 [App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html) · [睡眠与电源断言](https://developer.apple.com/library/archive/qa/qa1340/_index.html) · [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)

## 怎样验证

| 场景 | 记录和验证 |
| --- | --- |
| 后台、短时和长时锁屏 | 发送文字和文件，核对请求通知、接受操作、内容和延迟。 |
| Android Doze / Low Power Standby | 在隔离设备分别测试两种限制。记录系统状态、豁免、实际收件和退出限制后的恢复。 |
| Android 进程回收与重启 | 检查是否重建服务和节点、是否保留身份，以及能否收到下一次请求。记录任务划走、强制停止和重新打开的行为。 |
| macOS App Nap、合盖与唤醒 | 分别记录窗口可见、菜单栏、系统睡眠和唤醒情况。用 `pmset -g assertions` 检查空闲睡眠断言。 |
| Windows/Linux 托盘与睡眠 | 关闭窗口后从托盘恢复，测试通知确认，并检查睡眠或退出登录后的重连。 |
| 资源开销 | 在相同网络和电量条件下比较后台设置开关前后的耗电、CPU、网络和收件延迟。 |

2026-11-10 的 Android 35 模拟器记录显示，Sticky 服务在系统进程终止后重建了引擎与节点，并收到了文字和文件。该记录对应当时的模拟器环境。新的候选版本应记录实际结果。修改电池、休眠或登录设置时使用隔离设备，并在测试后恢复。 [发布验收清单](launch-checklist.zh-CN.md)
