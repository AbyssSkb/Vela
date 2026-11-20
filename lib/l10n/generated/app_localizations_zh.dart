// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get deviceRemoved => '已移除设备';

  @override
  String get legacyPairingsNotice => '检测到旧版设备数据，请重新配对设备。接收的文件和历史记录不受影响。';

  @override
  String get devices => '设备';

  @override
  String get showList => '切换为列表';

  @override
  String get showGraph => '切换为关系图';

  @override
  String get myDevice => '我的设备';

  @override
  String get addDevice => '添加设备';

  @override
  String get settings => '设置';

  @override
  String get deviceName => '设备名称';

  @override
  String get language => '语言';

  @override
  String get systemDefault => '跟随系统';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get english => 'English';

  @override
  String get appearance => '外观';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get save => '保存';

  @override
  String get cancel => '取消';

  @override
  String get close => '关闭';

  @override
  String get remove => '移除';

  @override
  String get rename => '重命名';

  @override
  String get deviceDetails => '设备详情';

  @override
  String get renameDevice => '重命名设备';

  @override
  String get useDeviceName => '恢复设备名称';

  @override
  String get deviceNameRequired => '请输入设备名称';

  @override
  String get nameTooLong => '设备名称过长';

  @override
  String get files => '文件';

  @override
  String get media => '相册';

  @override
  String get mediaPickFailed => '无法打开相册，请重试';

  @override
  String get clipboard => '剪贴板';

  @override
  String sendContentType(String kind) {
    return '发送$kind';
  }

  @override
  String get sendFile => '发送文件';

  @override
  String get sendClipboard => '发送剪贴板';

  @override
  String get chooseDevice => '选择设备';

  @override
  String get sendSelected => '发送已选内容';

  @override
  String get cancelShare => '取消分享';

  @override
  String pendingContent(String content) {
    return '待发送：$content';
  }

  @override
  String sendToDevice(String name) {
    return '发送给 $name';
  }

  @override
  String sendInsteadToDevice(String name) {
    return '改发给 $name';
  }

  @override
  String get changeSendDevice => '更换设备';

  @override
  String get connectDevices => '连接你的设备';

  @override
  String get emptyDevices => '在两台设备上打开 Vela。一台选择「设备码」，另一台选择「添加设备」。';

  @override
  String get deviceCode => '设备码';

  @override
  String get copyDeviceCode => '复制设备码';

  @override
  String get deviceCodeCopied => '设备码已复制';

  @override
  String get copyDeviceCodeFailed => '无法复制设备码。你可以选中设备码并手动复制。';

  @override
  String get showDeviceCode => '在另一台设备上选择「添加设备」，扫描二维码或输入设备码，再回到本机确认配对。';

  @override
  String get enterOrScan => '在另一台设备上选择「设备码」。在这里输入设备码或扫描二维码。';

  @override
  String get enterCode => '在另一台设备上选择「设备码」，然后在这里输入它的设备码。';

  @override
  String get scanCode => '扫码填写设备码';

  @override
  String get scanTitle => '扫描设备码';

  @override
  String get cameraError => '无法打开相机。请手动输入设备码以继续。';

  @override
  String get cameraPermissionNeeded => '请在应用设置中允许相机权限，再扫描设备码。';

  @override
  String get enterCodeManually => '手动输入设备码';

  @override
  String get invalidDeviceQr => '请在另一台设备上选择「设备码」，再扫描它的二维码。';

  @override
  String get invalidDeviceCode => '请输入 64 位设备码';

  @override
  String get connect => '连接';

  @override
  String get cannotAddSelf => '不能添加当前设备';

  @override
  String get connectingPair => '正在添加设备，请在另一台设备上确认。';

  @override
  String get pairRequest => '添加设备？';

  @override
  String get confirmOwnDevice => '在发起请求的设备上选择「设备码」，与下方的首尾各 8 位核对。';

  @override
  String get reject => '拒绝';

  @override
  String get add => '添加';

  @override
  String get pairDeclined => '对方拒绝了配对请求';

  @override
  String get pairConflict => '对方正在添加此设备，请稍后重试';

  @override
  String get pairWaiting => '等待设备响应';

  @override
  String get pairFailed => '无法连接设备。请核对设备码，并确认两台设备都已打开 Vela 且联网。';

  @override
  String get removeDevice => '移除设备';

  @override
  String get removeDeviceQuestion => '移除设备？';

  @override
  String get selectDevices => '多选设备';

  @override
  String get selectAll => '全选';

  @override
  String selectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String removeDevicesQuestion(int count) {
    return '移除 $count 台设备？';
  }

  @override
  String get removeDevicesBody => '将解除与所选设备的配对。离线设备会在下次连接时同步。';

  @override
  String removeRecordsQuestion(int count) {
    return '删除 $count 条记录？';
  }

  @override
  String get removeRecordsBody => '仅删除记录时会保留文件；删除文件后无法恢复。';

  @override
  String get removeRecordsOnly => '仅删除记录';

  @override
  String get removeRecordsAndFiles => '同时删除文件';

  @override
  String get removeRecordAndFile => '删除记录和文件';

  @override
  String get deleteFilesWarning => '文件将被永久删除，无法恢复。';

  @override
  String get deleteFilesFailed => '部分文件无法删除，相关记录已保留';

  @override
  String get removalSyncing => '已移除，正在同步到对方';

  @override
  String get receive => '接收';

  @override
  String get clipboardText => '剪贴板文字';

  @override
  String get clipboardImage => '剪贴板图片';

  @override
  String get clipboardReceived => '剪贴板内容已接收';

  @override
  String get open => '打开';

  @override
  String get openNoApp => '没有可打开此文件的应用';

  @override
  String get openFailed => '无法打开文件';

  @override
  String get sendFailed => '发送失败';

  @override
  String sendFailedTo(String name) {
    return '未能发送给 $name。';
  }

  @override
  String get sendDeviceChanged => '配对已变更，请重新选择设备。';

  @override
  String get originalSendDeviceUnavailable => '原设备已不可用。';

  @override
  String get reviewSendContent => '查看待发送内容';

  @override
  String get preparingSendContent => '正在准备内容…';

  @override
  String get discardSend => '放弃发送';

  @override
  String get receiveFailed => '接收失败';

  @override
  String get transferInterrupted => '传输中断，请重试';

  @override
  String get transferDeclined => '对方拒绝了接收';

  @override
  String get saveFailed => '无法保存文件，请检查存储空间';

  @override
  String get emptyClipboard => '剪贴板没有可发送的内容';

  @override
  String get singleClipboardFile => '暂时一次发送一个剪贴板文件';

  @override
  String get readSharedFailed => '无法读取分享的文件';

  @override
  String get readClipboardFailed => '无法读取剪贴板，请重新复制后重试';

  @override
  String get writeClipboardFailed => '已接收，但未能复制到剪贴板';

  @override
  String get incomingClipboardHint => '接收后将替换本机剪贴板内容。';

  @override
  String get startingVela => '正在启动 Vela…';

  @override
  String get startupFailed => 'Vela 无法启动。';

  @override
  String get diagnostics => '诊断';

  @override
  String get diagnosticsStartupHelp => 'Vela 尚未完成启动。';

  @override
  String get diagnosticsDeviceHelp => '请在其他设备上打开 Vela，再刷新设备状态。';

  @override
  String diagnosticsUnreachableDevices(String names) {
    return '暂时无法连接 · $names';
  }

  @override
  String get diagnosticsRetryStartup => '重试启动 Vela';

  @override
  String get diagnosticsRecoveryFailed => '未能完成检查，请重试。';

  @override
  String get diagnosticsClearEvents => '清空事件';

  @override
  String get diagnosticsClearQuestion => '清空诊断事件？';

  @override
  String diagnosticsUpdated(String time) {
    return '更新于 $time';
  }

  @override
  String diagnosticsStale(String time) {
    return '刷新失败，正在显示 $time 的结果。';
  }

  @override
  String get mobile => '手机';

  @override
  String get tablet => '平板';

  @override
  String get desktop => '电脑';

  @override
  String get device => '设备';

  @override
  String get reachable => '可连接';

  @override
  String get unreachable => '暂时无法连接';

  @override
  String get checking => '正在检查';

  @override
  String get unknown => '状态未知';

  @override
  String get more => '更多操作';

  @override
  String get storageFailed => '无法保存设置';

  @override
  String get systemDeviceName => '设备原名';

  @override
  String get deviceAliasHint => '只在本设备显示';

  @override
  String get selectFileFirst => '选择文件后，再选择接收设备';

  @override
  String get requestAccepted => '已添加设备';

  @override
  String deviceCodeShort(String code) {
    return '设备码 $code';
  }

  @override
  String peerUnpaired(String name) {
    return '$name 已解除配对';
  }

  @override
  String addedPeer(String name) {
    return '已添加 $name';
  }

  @override
  String sentTo(String name) {
    return '已发送给 $name';
  }

  @override
  String receiving(String name) {
    return '正在接收 $name';
  }

  @override
  String get notificationTransferring => '正在传输';

  @override
  String get notificationTransferringShort => '传输中';

  @override
  String sendingTo(String name) {
    return '正在发送给 $name';
  }

  @override
  String connectingTo(String name) {
    return '正在连接 $name';
  }

  @override
  String received(String name) {
    return '已接收 $name';
  }

  @override
  String shareFrom(String name) {
    return '来自 $name 的分享';
  }

  @override
  String removeDeviceBody(String name) {
    return '将同时解除与「$name」的配对。对方离线时，双方下次打开新版并联网后重试同步。';
  }

  @override
  String failedWithReason(String reason, String title) {
    return '$title：$reason';
  }

  @override
  String get refreshDevices => '刷新设备状态';

  @override
  String get transferCancelled => '传输已取消';

  @override
  String get cancelling => '正在取消';

  @override
  String get directConnection => '直连';

  @override
  String get relayConnection => '中继';

  @override
  String get transferHistory => '接收记录';

  @override
  String get viewReceivedBatch => '查看本次接收';

  @override
  String get receivedBatch => '本次接收';

  @override
  String get receivedBatchUnavailable => '找不到本次接收的记录。';

  @override
  String showMoreOfferedFiles(int count) {
    return '查看另外 $count 个文件';
  }

  @override
  String get showFewerOfferedFiles => '收起文件列表';

  @override
  String receivedSavedTo(String folder) {
    return '已保存至 $folder';
  }

  @override
  String get openFile => '打开文件';

  @override
  String get openReceiveFolder => '打开接收文件夹';

  @override
  String get showInFolder => '打开所在文件夹';

  @override
  String get recordDetails => '详情';

  @override
  String get recordName => '名称';

  @override
  String get recordDevice => '设备';

  @override
  String get recordTime => '时间';

  @override
  String get fileDetails => '文件详情';

  @override
  String get fileNameLabel => '文件名';

  @override
  String get fileSizeLabel => '大小';

  @override
  String get receivedAtLabel => '接收时间';

  @override
  String get receivedFromLabel => '来自';

  @override
  String get connectingShort => '连接中';

  @override
  String get incomingShort => '待接收';

  @override
  String get noTransferHistory => '暂无接收记录';

  @override
  String get manageRecords => '管理记录';

  @override
  String get selectRecords => '选择记录';

  @override
  String get clearSearch => '清除搜索';

  @override
  String get clearHistory => '清空记录';

  @override
  String get clearHistoryConfirm => '清空接收记录？接收的文件不会被删除。';

  @override
  String historyReceivedFrom(String name) {
    return '来自 $name';
  }

  @override
  String get moreOptions => '更多选项';

  @override
  String get removeRecord => '删除记录';

  @override
  String get historyText => '剪贴板文字';

  @override
  String get historyImage => '剪贴板图片';

  @override
  String get historyUnknownDevice => '未知设备';

  @override
  String get historyMissing => '文件不存在或无法访问';

  @override
  String get historyCopy => '复制';

  @override
  String get historyCopied => '已复制';

  @override
  String get historyCopyFiles => '复制文件';

  @override
  String get historyCopyFailed => '无法复制到剪贴板，请重试。';

  @override
  String get historySaveFailed => '已传输，但无法保存记录';

  @override
  String filesCount(int count) {
    return '$count 个文件';
  }

  @override
  String filesReceived(int count) {
    return '已接收 $count 个文件';
  }

  @override
  String get viewHistory => '查看记录';

  @override
  String get dropFilesOnly => '暂不支持拖入文件夹';

  @override
  String get tooManyFiles => '一次最多发送 100 个文件';

  @override
  String get backgroundReceiving => '后台接收';

  @override
  String get localBackgroundReceiving => '本机后台接收';

  @override
  String get enableBackgroundReceiving => '允许后台接收';

  @override
  String get notificationBackgroundBlocked => '通知已关闭，接收需打开 Vela。';

  @override
  String get notificationAutoAcceptMuted => '通知已关闭，仍可自动接收。';

  @override
  String get notificationAutoAcceptStopped => '通知已关闭，请检查后台接收。';

  @override
  String get notificationSettings => '通知';

  @override
  String get notificationSystemSettings => '系统通知设置';

  @override
  String get notificationOff => '已关闭';

  @override
  String get notificationRequests => '接收请求';

  @override
  String get notificationProgress => '传输进度';

  @override
  String get notificationResults => '传输结果';

  @override
  String get notificationLive => '实时活动';

  @override
  String get notificationCompleted => '传输完成';

  @override
  String get notificationCompletedShort => '已完成';

  @override
  String get backgroundReady => '接收服务已启动';

  @override
  String get backgroundStartHint => '未开启';

  @override
  String get backgroundMacMaySleep => '唤醒时可接收';

  @override
  String get backgroundMacInactive => '仍可进入空闲睡眠';

  @override
  String get backgroundMacAwake => '已阻止空闲睡眠';

  @override
  String get backgroundTrayUnavailable => '需保持窗口打开';

  @override
  String get backgroundTrayReady => '托盘接收已开启';

  @override
  String get backgroundServiceStopped => '接收服务未就绪';

  @override
  String get backgroundAllowRequests => '接收请求通知已关闭';

  @override
  String get backgroundAppNotificationsOff => 'Vela 通知已关闭';

  @override
  String get backgroundOpenBatterySettings => '打开应用设置';

  @override
  String get backgroundBatteryLimitsLockedReceiving => '电池优化可能中断锁屏接收';

  @override
  String get backgroundSettingsOpenFailed => '无法打开系统设置。';

  @override
  String get backgroundCheckBattery => '请检查电池设置';

  @override
  String get backgroundServiceReady => '接收服务运行中';

  @override
  String get settingsTroubleshooting => '故障排查';

  @override
  String get userGuide => '使用指南';

  @override
  String get backgroundUnavailable => '无法更改后台接收，请检查系统设置。';

  @override
  String get backgroundNotification => '通知';

  @override
  String get backgroundBattery => '电池优化';

  @override
  String get backgroundBatteryExempt => '已豁免';

  @override
  String get backgroundBatteryRestricted => '受限';

  @override
  String get backgroundBatteryOptimized => '未豁免';

  @override
  String get backgroundRestricted => '系统后台限制';

  @override
  String get backgroundAllowed => '已允许';

  @override
  String get backgroundNeedsAttention => '需要检查';

  @override
  String get backgroundBatteryHint => '若后台经常离线，可在系统设置中允许不受限制的电池使用。';

  @override
  String get backgroundVendorGuide => '后台接收指南';

  @override
  String get backgroundOffer => '有设备正在发送内容';

  @override
  String get backgroundOff => '未开启';

  @override
  String get backgroundOn => '已开启';

  @override
  String get saveAs => '另存为';

  @override
  String get revealInFinder => '在 Finder 中显示';

  @override
  String get savedFile => '文件已保存';

  @override
  String get saveFileFailed => '无法保存文件';

  @override
  String get openLink => '打开链接';

  @override
  String get openLinkFailed => '无法打开链接';

  @override
  String get openAfterReceive => '接收完成后显示窗口';

  @override
  String get autoAccept => '自动接收';

  @override
  String get retry => '重试';

  @override
  String get fileUnavailable => '文件无法读取，请重新选择';

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String get settingsGeneral => '常规';

  @override
  String get settingsReceiving => '接收';

  @override
  String get saveLocation => '保存位置';

  @override
  String get downloadsFolder => '下载';

  @override
  String get chooseFolder => '选择文件夹';

  @override
  String get useDownloads => '使用下载目录';

  @override
  String get saveLocationUnavailable => 'Vela 无法访问所选文件夹。';

  @override
  String get chooseSaveLocationAgain => '重新选择保存位置';

  @override
  String get savingFile => '正在保存';

  @override
  String get savedPrivately => '无法保存到所选位置，文件已保存在应用中';

  @override
  String get settingsAbout => '关于 Vela';

  @override
  String get appUpdateCheck => '检查';

  @override
  String get appUpdateFailed => '更新失败。';

  @override
  String get relaySettings => '中继服务器';

  @override
  String get relayEnabled => '使用自定义中继';

  @override
  String get relayEnabledDetail => '未添加中继，仍使用公共中继。';

  @override
  String get relayToggleFailed => '无法更改中继设置';

  @override
  String get relayBusy => '请先完成当前传输或配对';

  @override
  String get relayCustomOnly => '其他设备也需配置相同中继。';

  @override
  String get relayShowToken => '显示令牌';

  @override
  String get relayHideToken => '隐藏令牌';

  @override
  String get relayDefaultsKept => '公共中继始终保留';

  @override
  String get addRelay => '添加中继';

  @override
  String get editRelay => '编辑中继';

  @override
  String get relayUrl => '中继地址';

  @override
  String get relayToken => '访问令牌（可选）';

  @override
  String get relayInvalid => '请输入有效的 HTTPS 中继地址';

  @override
  String get relayDuplicate => '这个中继已添加';

  @override
  String get relayFailed => '无法保存中继，请重试';

  @override
  String get relayRemove => '移除中继';

  @override
  String get relayTest => '测试连接';

  @override
  String get relayTestShort => '测试';

  @override
  String get relayTestSuccess => '本机已连接此中继。';

  @override
  String get relayTestAuth => '中继拒绝访问，请检查令牌';

  @override
  String get relayTestTimeout => '连接超时，请检查地址和网络';

  @override
  String get relayTestFailed => '无法连接中继';

  @override
  String get searchHistory => '搜索记录';

  @override
  String get noHistoryMatches => '没有找到匹配的记录';

  @override
  String get transferBusy => '已有传输正在进行，请稍后重试';

  @override
  String get backgroundUnknown => '未知';

  @override
  String get backgroundLowPowerStandbyRestricted => '低功耗待机会限制锁屏时的网络连接';

  @override
  String get backgroundAutoStart => '自启动';

  @override
  String get macKeepAwake => '防止空闲睡眠';

  @override
  String get backgroundLogin => '登录时启动';

  @override
  String get backgroundLoginApproval => '需要在系统设置中允许';

  @override
  String get backgroundOpenLoginSettings => '打开登录项设置';

  @override
  String get backgroundLoginNotFound => '无法找到登录项';

  @override
  String get backgroundLoginUnsupported => '需要 macOS 13 或更新版本';

  @override
  String get backgroundLoginFailed => '无法更改登录启动项，请检查系统设置。';

  @override
  String get sendText => '发送文字';

  @override
  String get enterText => '输入或粘贴文字';

  @override
  String get folder => '文件夹';

  @override
  String get preparingFolder => '正在准备文件夹…';

  @override
  String get folderPrepareFailed => '无法准备文件夹';

  @override
  String get restoreFolder => '还原文件夹';

  @override
  String get restoringFolder => '正在还原文件夹…';

  @override
  String get folderRestored => '文件夹已还原';

  @override
  String get folderRestoreFailed => '无法还原文件夹，压缩包已保留。';

  @override
  String get textContent => '文字';

  @override
  String get textReceived => '已收到文字';

  @override
  String get view => '查看';

  @override
  String get viewText => '查看文字';

  @override
  String get textTooLarge => '文字不能超过 1 MiB';

  @override
  String get trayOpen => '打开 Vela';

  @override
  String get trayQuit => '退出';

  @override
  String get desktopTray => '系统托盘';

  @override
  String get graphPairedDevicesHint => '连线表示已配对。切换到列表可查看连接状态。';

  @override
  String get addDeviceAndContinue => '添加设备并继续';

  @override
  String get sendContentReady => '完成';

  @override
  String waitingForRecipient(String name) {
    return '正在等待 $name 响应';
  }

  @override
  String sendDeclinedBy(String name) {
    return '$name 已拒绝接收。';
  }
}
