# Background receiving

[简体中文](background-execution-research.zh-CN.md)

Background receiving requires a running Vela node that can connect to its peer. Test app backgrounding, system sleep, process reclamation, user-initiated quit, and recovery after reboot separately. Use an actual receive to verify each scenario. [User guide](user-guide.md#receive-in-the-background)

## Current implementation

| Platform | How Vela stays available |
| --- | --- |
| Android | With background receiving enabled, `ReceivingService` runs a foreground service, keeps a persistent notification, and holds a partial wake lock. When the system recreates the sticky service, it reads the saved setting. When `BootReceiver` receives `BOOT_COMPLETED`, it uses the same setting to decide whether to start the service. |
| macOS | Closing the window keeps the process and menu-bar entry available. The optional **Keep available in background** setting prevents idle system sleep. On macOS 13 or later, users can configure a separate system-managed login item. Network and wake events notify Flutter to recover the node and reachability state. |
| Windows and Linux | With background receiving enabled and a tray available, the app stays in the tray after its window closes. The desktop integration coordinates windows, notifications, and quitting. |

Android's receiving service can start the shared FlutterEngine without a foreground Activity. macOS checks background availability and launch-at-login state separately. [ReceivingService.kt](../android/app/src/main/kotlin/com/example/vela/ReceivingService.kt) · [BootReceiver.kt](../android/app/src/main/kotlin/com/example/vela/BootReceiver.kt) · [AppDelegate.swift](../macos/Runner/AppDelegate.swift) · [MainFlutterWindow.swift](../macos/Runner/MainFlutterWindow.swift)

## Android system constraints

- **Foreground service.** Vela declares `specialUse`. `START_STICKY` lets the OS try to recreate the service after reclaiming its process. The callback can carry a null Intent. A new service started by the app from the background is subject to Android 12's startup restrictions. Check the app's use case and required permissions before considering `connectedDevice` or another service type. [Service API](https://developer.android.com/reference/android/app/Service#START_STICKY) · [Background startup restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start) · [Service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- **User stop.** The Android **Active apps** stop action ends the process. **Force stop** in system app settings also places the app in a stopped state until the user interacts with it again. Test OS reclamation, user stop, and reopening separately. [Stopping an app with a foreground service](https://developer.android.com/develop/background-work/services/fgs/handle-user-stopping) · [Android 15 stopped state](https://developer.android.com/about/versions/15/behavior-changes-all#stopped-state)
- **Power state.** Doze affects the network, wake locks, and scheduling. A battery optimization exemption relaxes some restrictions. Low Power Standby is independent of Doze and can suspend network access while a device is non-interactive even with a foreground service. Record whether LPS is enabled and whether the package is exempt. Record the battery optimization exemption and vendor restrictions separately. [Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby) · [PowerManager](https://developer.android.com/reference/android/os/PowerManager) · [Background optimization](https://developer.android.com/topic/performance/background-optimization)
- **Scheduling and push.** When an app targets Android 15 or higher, `dataSync` and `mediaProcessing` foreground services each get six cumulative background hours per 24 hours. `dataSync` also has boot startup restrictions. WorkManager is for deferrable tasks. High-priority FCM suits timely user-visible notifications. Adding it would require evaluating infrastructure, coverage, and system constraints. [Foreground service timeouts](https://developer.android.com/develop/background-work/services/fgs/timeout) · [Android 15 behavior changes](https://developer.android.com/about/versions/15/behavior-changes-15#fgs-boot-completed) · [FCM priority](https://firebase.google.com/docs/cloud-messaging/android-message-priority)

## macOS system constraints

App Nap affects timers and resource scheduling for apps that are offscreen. Test actual receipt while the menu-bar icon is present. Record screen-off, idle system sleep, manual sleep, and lid closure separately. The activity that prevents idle sleep applies to idle system sleep. The login item using `SMAppService.mainApp` takes effect on a subsequent login and is controlled by system settings. [App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html) · [Sleep and power assertions](https://developer.apple.com/library/archive/qa/qa1340/_index.html) · [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)

## Verification

| Scenario | What to check and record |
| --- | --- |
| Background, short and long screen lock | Send text and a file. Check the incoming notification, acceptance, content, and latency. |
| Android Doze and Low Power Standby | Test each restriction on an isolated device. Record system state, exemptions, receipt, and recovery after leaving that state. |
| Android reclamation and reboot | Check service and node recreation, identity retention, and the next incoming request. Record task dismissal, force-stop, and reopening separately. |
| macOS App Nap, lid close, and wake | Record visible windows, the menu bar, sleep, and wake separately. Use `pmset -g assertions` to check idle-sleep assertions. |
| Windows/Linux tray and sleep | Restore the app from the tray after closing the window. Test notification approval and reconnection after sleep or logout. |
| Resource cost | Under the same network and power conditions, compare battery use, CPU, network traffic, and receiving latency with background receiving on and off. |

An Android 35 emulator run on 2026-11-10 recorded the sticky service rebuilding the engine and node after process termination and receiving text and a file. Record results against the new candidate. Use an isolated device for changes to battery, sleep, or login settings and restore the settings after the test. [Release acceptance checklist](launch-checklist.md)
