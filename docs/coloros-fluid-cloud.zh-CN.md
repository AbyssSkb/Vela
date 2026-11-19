# ColorOS 上的传输进度通知

[English](coloros-fluid-cloud.md)

Vela 用 Android 的 Live Updates 展示传输进度。系统可以提升通知，在状态栏显示胶囊，也可能继续以普通通知显示。ColorOS 的具体呈现需要在目标机型和系统版本上确认。 [通知实现](../android/app/src/main/kotlin/com/example/vela/BackgroundBridge.kt)

## Android 标准路径

- 用 `ProgressStyle` 表示当前进度。通知可以带进度条、分段、节点、追踪图标和操作按钮。Vela 在 [AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml) 声明 `POST_PROMOTED_NOTIFICATIONS`，在传输通知中请求提升。 [Android 16 进度通知](https://developer.android.com/about/versions/16/features/progress-centric-notifications)
- 提升需要 ongoing 通知、标题和符合要求的渠道。自定义 `RemoteViews`、显式着色、分组摘要或最低重要性渠道会使通知失去提升资格。用 `hasPromotableCharacteristics()` 检查结构，用 `canPostPromotedNotifications()` 检查应用是否获准。系统和厂商决定最终呈现。 [Live Updates](https://developer.android.com/develop/ui/views/notifications/live-update)
- 把 Live Update 用在用户发起、仍在进行的任务。传输完成后用普通通知报告结果。验收时分别记录进行中、完成和失败状态。 [Live Updates 使用条件](https://developer.android.com/develop/ui/views/notifications/live-update)

## OPPO 专有接入记录

以下是 2026-11-08 调研时记录的 OPPO 文档内容。真正接入时，向 OPPO 确认 Vela 的传输场景、所需审核、服务标识和支持的系统版本。

| 问题 | 当时记录的说明 |
| --- | --- |
| 如何申请 | 首次接入需要开放平台账号和企业认证，提交开发者 ID、包名和请求量等信息，与 OPPO 确认服务形态。 [接入准备](https://open.oppomobile.com/documentation/page/info?id=13572) |
| 端侧怎样调用 | 通过 `IntelligentIntent` Provider 调用 `shareIntent`，传入 JSON `intentData`，从 `result` 读取结果。检查权限、系统支持、开关、大小、频率和实体数量。 [端侧意图共享](https://open.oppomobile.com/documentation/page/info?id=13558) |
| 模板怎样更新 | 进度模板使用意图名、`serviceId`、稳定的 `entityId` 和里程碑。示例用 `Example.Progress`，正式标识由联调给出。`actionStatus` 为 0 创建、1 刷新或 2 销卡，0 和 1 也可能重新创建已消失的卡片。 [进度模板](https://open.oppomobile.com/documentation/page/info?id=13567) |
| 能配置什么 | 系统模板允许配置胶囊图文、主卡内容、操作和进度。进度范围为 0–100，节点为 2–5 个。交互和完成态留存需按目标模板和版本确认。 [进度模板](https://open.oppomobile.com/documentation/page/info?id=13567) |
| 云侧凭据 | 云侧 access token 由服务端用 `client_id` 和 `client_secret` 取得。凭据留在服务端。 [获取凭据](https://open.oppomobile.com/documentation/page/info?id=13559) |

## 在目标设备上验证

记录机型、ColorOS 版本、应用版本、通知权限和 Live Updates 设置。开始一次传输，检查状态栏、锁屏和通知栏的进度显示。测试点击、长按展开、完成后变化和用户主动关闭。分别记下系统允许提升、通知发出、实机出现胶囊这三项。 [ColorOS 功能说明](https://www.coloros.com/article/A00000075/)
