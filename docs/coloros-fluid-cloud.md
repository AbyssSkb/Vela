# ColorOS 流体云与 Android Live Updates 调研

调研日期：2026-11-08。以下是文档和源码证据，不代表 Vela 已在任何机型验收。

## Android 16 标准路径

- Android 16 的 `Notification.ProgressStyle` 支持进度、分段、节点、追踪图标，以及标题、正文和通知操作按钮；系统决定各界面的具体排版。[Android 官方：进度通知](https://developer.android.com/about/versions/16/features/progress-centric-notifications)
- 要请求 Live Update，声明 `POST_PROMOTED_NOTIFICATIONS`，请求 promoted ongoing，设置 ongoing 和标题；通知不得使用自定义 `RemoteViews`、`setColorized(true)`、分组摘要或最低重要性渠道。可使用 `hasPromotableCharacteristics()` 检查结构，`canPostPromotedNotifications()` 检查应用是否被允许；前者不检查用户开关，OEM 可以增加条件。系统可将通知显示为状态栏 chip、锁屏和通知栏卡片，也可降级；不能保证 ColorOS 胶囊的具体样式或常驻。[Android 官方：Live Updates](https://developer.android.com/develop/ui/views/notifications/live-update)
- 官方将此类通知限定为用户发起、正在进行且有时效的活动；任务完成后应改用普通通知。可在普通通知中展示完成结果，但上述 API 不承诺完成状态继续作为胶囊或以指定时长保留。[Android 官方：Live Updates 使用条件](https://developer.android.com/develop/ui/views/notifications/live-update)
- 开源项目 [FluidCapsule 的发布代码](https://github.com/Venompool888/FluidCapsule/blob/main/app/src/main/java/io/github/venompool888/fluidcapsule/publisher/AospLiveUpdatePublisher.kt) 使用 `ProgressStyle`、短关键文本、promoted extra 和系统检查；其 [README](https://github.com/Venompool888/FluidCapsule) 称支持部分 ColorOS 设备，项目明确为非官方。它证明一种实现方式，不能证明所有 ColorOS 版本效果相同或实现了任意自定义卡片。

## OPPO 专有路径

以下官方文档正文通过 OPPO 的文档接口 `POST https://open.oppomobile.com/oneoppoapi/doc/detail`，传入相应 `doc_id` 获取；页面链接供浏览器查看。

- **账户和申请**：[OPPO 接入准备](https://open.oppomobile.com/documentation/page/info?id=13572) 明确要求首次接入注册 OPPO 开放平台账号并完成企业认证，提供主账号开发者 ID、客户端包名、峰值和平均 QPS、每日请求量、单次履约请求量及请求频率，并联系 OPPO 确认服务形态。云侧另需客户端应用 AppID 和用户账号关联；端侧方案适用于依赖应用进程存活的场景。是否接受 Vela 文件传输场景、最终审核和服务配置需 OPPO 确认。
- **端侧 API**：[意图共享（端侧）](https://open.oppomobile.com/documentation/page/info?id=13558) 指定 `acquireUnstableContentProviderClient("IntelligentIntent")`，以 `call("shareIntent", null, bundle)` 发送，Bundle 的 `intentData` 为 JSON 字符串；从结果 Bundle 的 `result` 读取 JSON，`code=0` 为成功。官方列出无权限、权限过期、参数错误、大小或频率超限、开关关闭、实体数量超限、版本不支持等错误；调用成功本身不等于已验证实际渲染。
- **服务标识与生命周期**：[进度模板](https://open.oppomobile.com/documentation/page/info?id=13567) 的测试 `intentName` 为 `Example.Progress`，测试 `serviceId` 为 `fluidCloud: 999900001`、`launcher: 999800001`；正式环境的意图名和卡片 serviceId 由 OPPO 在联调时提供。数据需包含 `entityName`、稳定的 `entityId`、规定的 milestone、胶囊和主卡数据。`actionStatus` 为 0 创建、1 刷新、2 立即销卡；官方明确 0 和 1 在卡不存在时都会创卡，因此用户关闭后继续刷新可能重新出现，需确认业务生命周期及系统实际行为。
- **可配置外观**：同一进度模板规定胶囊左右图片和文字、亮暗色文字；主卡可配置标题、内容、图片、点击跳转和指定按钮。左右按钮、顶部按钮、小图、大图互斥；进度是 0–100，节点 2–5 个，指示器可在条内或条上。它是系统模板字段，并未证明支持任意自定义布局或背景。`actionStatus=2` 立即销卡；通过里程碑更新为完成状态后的留存时间和表现需按具体垂域确认。
- **凭据范围**：[OPPO 获取凭据文档](https://open.oppomobile.com/documentation/page/info?id=13559) 规定调用**云侧**接口需 accessToken，正式 token 使用服务端应用的 `client_id` 和 `client_secret` 获取；需关联客户端应用、向 OPPO 反馈 AppID 并开启标准意图接入。若 API 库没有该产品，需联系 OPPO 提供开发者 ID 加白。上述文档未说端侧 Provider 每次调用需要 client secret；不要把 secret 放进客户端。
- [阿里云移动推送文档](https://help.aliyun.com/zh/document_detail/2997310.html) 称其通道支持 ColorOS 15 及以上，OS 15 胶囊最长显示 5 分钟，卡片退出时间依场景而异；这是该通道文档所述范围，不应外推所有端侧接入和系统版本。OPPO 进度模板还列有涉及 OS 14 时的 legacy 字段，具体设备兼容范围应向 OPPO 核实。
- OPPO [ColorOS 15 功能说明](https://www.coloros.com/article/A00000075/) 确认用户可点击或长按胶囊展开卡片、点击卡片进入应用；支持功能因设备和系统更新而异。

## 待确认与验证

1. 向 OPPO 确认 Vela 文件传输是否属于可申请场景、`serviceId` 的申请和测试／上线审核要求，及端侧所需系统配置。
2. 确认目标模板是否支持所需图标、色彩、按钮和完成态的展示与存留，及系统版本差异；不可将标准通知的 `RemoteViews` 当作 Live Update 的可行自定义方案。
3. 在目标一加设备的实际 ColorOS 版本上分别测试进行中进度、长按展开、点击、完成后降级、用户关闭及后台行为；记录系统通知权限、Live Updates 设置和诊断 API 结果。文档与开源源码均不能替代实机验收。
