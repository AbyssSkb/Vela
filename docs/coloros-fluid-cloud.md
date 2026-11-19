# Transfer progress notifications on ColorOS

[简体中文](coloros-fluid-cloud.zh-CN.md)

Vela uses Android Live Updates to display transfer progress. The OS can promote the notification to a status-bar chip or display it as an ordinary notification. Check the rendering on the target ColorOS device and version. [Notification implementation](../android/app/src/main/kotlin/com/example/vela/BackgroundBridge.kt)

## Standard Android path

- Use `ProgressStyle` for the current progress. A notification can include a progress bar, segments, points, a tracker icon, and actions. Vela declares `POST_PROMOTED_NOTIFICATIONS` in [AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml) and requests promotion on transfer notifications. [Android 16 progress notifications](https://developer.android.com/about/versions/16/features/progress-centric-notifications)
- Promotion requires an ongoing notification, a title, and an eligible channel. Custom `RemoteViews`, explicit colorization, group summaries, and minimum-importance channels disqualify it. Use `hasPromotableCharacteristics()` to check the notification structure and `canPostPromotedNotifications()` to check whether the app has permission. The OS and manufacturer control the rendering. [Live Updates](https://developer.android.com/develop/ui/views/notifications/live-update)
- Use a Live Update for an ongoing task the user started. Report the result with an ordinary notification after the transfer. Verify in-progress, completed, and failed states separately. [Live Updates usage guidelines](https://developer.android.com/develop/ui/views/notifications/live-update)

## OPPO integration notes

These notes summarize OPPO's documentation as reviewed on 2026-11-08. Before an integration, confirm Vela's transfer use case, the required review, service identifiers, and supported system versions with OPPO.

| Question | What the documentation described |
| --- | --- |
| How to apply | First-time integration requires an OPPO Open Platform account and enterprise verification. Submit the developer ID, package name, and request volumes and confirm the service type with OPPO. [Preparation](https://open.oppomobile.com/documentation/page/info?id=13572) |
| How an on-device call works | Call `shareIntent` through the `IntelligentIntent` provider with JSON `intentData`, then read the outcome from `result`. Check permissions, system support, user settings, sizes, rates, and entity counts. [On-device intent sharing](https://open.oppomobile.com/documentation/page/info?id=13558) |
| How to update a template | The progress template uses an intent name, `serviceId`, stable `entityId`, and milestones. The sample uses `Example.Progress`. OPPO assigns production identifiers during integration. An `actionStatus` of 0 creates, 1 refreshes, and 2 removes the card. Both 0 and 1 may recreate a dismissed card. [Progress template](https://open.oppomobile.com/documentation/page/info?id=13567) |
| What can be configured | The system template exposes chip images and text, main-card content, actions, and progress. Progress runs from 0 to 100, with 2–5 points. Confirm interaction and retention after completion on the target template and version. [Progress template](https://open.oppomobile.com/documentation/page/info?id=13567) |
| Cloud credentials | The server obtains the cloud-side access token using `client_id` and `client_secret`. Keep the credentials on the server. [Credentials](https://open.oppomobile.com/documentation/page/info?id=13559) |

## Verify on a target device

Record the device model, ColorOS version, Vela version, notification permissions, and Live Updates settings. Start a transfer and check progress on the status bar, lock screen, and notification drawer. Test tapping, long-press expansion, completion, and user dismissal. Record promotion permission, notification delivery, and the presence of the status-bar chip separately. [ColorOS feature description](https://www.coloros.com/article/A00000075/)
