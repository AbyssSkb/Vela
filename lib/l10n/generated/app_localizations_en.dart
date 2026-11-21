// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get deviceRemoved => 'Device removed';

  @override
  String get legacyPairingsNotice => 'Pair your devices again.';

  @override
  String get devices => 'Devices';

  @override
  String get showList => 'Show list';

  @override
  String get showGraph => 'Show graph';

  @override
  String get myDevice => 'This device';

  @override
  String get addDevice => 'Add device';

  @override
  String get settings => 'Settings';

  @override
  String get deviceName => 'Device name';

  @override
  String get language => 'Language';

  @override
  String get systemDefault => 'System default';

  @override
  String get simplifiedChinese => 'Simplified Chinese';

  @override
  String get english => 'English';

  @override
  String get appearance => 'Appearance';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get remove => 'Remove';

  @override
  String get rename => 'Rename';

  @override
  String get deviceDetails => 'Device details';

  @override
  String get renameDevice => 'Rename device';

  @override
  String get useDeviceName => 'Restore device name';

  @override
  String get deviceNameRequired => 'Enter a device name';

  @override
  String get nameTooLong => 'Device name is too long';

  @override
  String get files => 'Files';

  @override
  String get media => 'Photos';

  @override
  String get mediaPickFailed => 'Couldn\'t open the photo picker. Try again.';

  @override
  String get clipboard => 'Clipboard';

  @override
  String sendContentType(String kind) {
    return 'Send $kind';
  }

  @override
  String get sendFile => 'Send file';

  @override
  String get sendClipboard => 'Send clipboard';

  @override
  String get chooseDevice => 'Choose a device';

  @override
  String get sendSelected => 'Send selected item';

  @override
  String get cancelShare => 'Cancel share';

  @override
  String pendingContent(String content) {
    return 'Ready to send: $content';
  }

  @override
  String sendToDevice(String name) {
    return 'Send to $name';
  }

  @override
  String sendInsteadToDevice(String name) {
    return 'Send to $name instead';
  }

  @override
  String get changeSendDevice => 'Change device';

  @override
  String get connectDevices => 'Connect your devices';

  @override
  String get emptyDevices =>
      'Open Vela on both devices. Choose Device code on one and Add device on the other.';

  @override
  String get deviceCode => 'Device code';

  @override
  String get copyDeviceCode => 'Copy device code';

  @override
  String get deviceCodeCopied => 'Device code copied';

  @override
  String get copyDeviceCodeFailed =>
      'Could not copy the device code. You can select and copy it manually.';

  @override
  String get showDeviceCode =>
      'On the other device, choose Add device and scan this QR code or enter the device code. Then approve the request here.';

  @override
  String get enterOrScan =>
      'On the other device, choose Device code. Enter the code here or scan the QR code.';

  @override
  String get enterCode =>
      'On the other device, choose Device code and enter its code here.';

  @override
  String get scanCode => 'Scan device code';

  @override
  String get scanTitle => 'Scan device code';

  @override
  String get cameraError =>
      'Could not open the camera. Enter the device code manually to continue.';

  @override
  String get cameraPermissionNeeded =>
      'Allow camera access in app settings to scan a device code.';

  @override
  String get enterCodeManually => 'Enter device code manually';

  @override
  String get invalidDeviceQr =>
      'Choose Device code on the other device and scan its QR code.';

  @override
  String get invalidDeviceCode => 'Enter a 64-character device code';

  @override
  String get connect => 'Connect';

  @override
  String get cannotAddSelf => 'You cannot add this device.';

  @override
  String get connectingPair =>
      'Adding device… Confirm the request on the other device.';

  @override
  String get pairRequest => 'Add device?';

  @override
  String get confirmOwnDevice =>
      'On the requesting device, choose Device code. Match the first and last eight characters with the code below.';

  @override
  String get reject => 'Decline';

  @override
  String get add => 'Add';

  @override
  String get pairDeclined => 'The other device declined the request.';

  @override
  String get pairConflict =>
      'The other device is already adding this device. Please try again.';

  @override
  String get pairWaiting => 'Waiting for the device';

  @override
  String get pairFailed =>
      'Could not connect. Check the device code and make sure Vela is open and online on both devices.';

  @override
  String get removeDevice => 'Remove device';

  @override
  String get removeDeviceQuestion => 'Remove device?';

  @override
  String get selectDevices => 'Select devices';

  @override
  String get selectAll => 'Select all';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String removeDevicesQuestion(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Remove $count devices?',
      one: 'Remove 1 device?',
    );
    return '$_temp0';
  }

  @override
  String get removeDevicesBody =>
      'The selected devices will be unpaired. Offline devices will sync when they reconnect.';

  @override
  String removeRecordsQuestion(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Remove $count records?',
      one: 'Remove 1 record?',
    );
    return '$_temp0';
  }

  @override
  String get removeRecordsBody =>
      'Removing records keeps the files. Deleted files cannot be recovered.';

  @override
  String get removeRecordsOnly => 'Remove records only';

  @override
  String get removeRecordsAndFiles => 'Also delete files';

  @override
  String get removeRecordAndFile => 'Delete records and files';

  @override
  String get deleteFilesWarning => 'Deleted files cannot be recovered.';

  @override
  String get deleteFilesFailed =>
      'Some files could not be deleted; their records were kept.';

  @override
  String get removalSyncing => 'Removed. Syncing to the other device.';

  @override
  String get receive => 'Accept';

  @override
  String get clipboardText => 'Clipboard text';

  @override
  String get clipboardImage => 'Clipboard image';

  @override
  String get clipboardReceived => 'Clipboard received';

  @override
  String get open => 'Open';

  @override
  String get openNoApp => 'No app can open this file.';

  @override
  String get openFailed => 'Could not open the file.';

  @override
  String get sendFailed => 'Could not send';

  @override
  String sendFailedTo(String name) {
    return 'Couldn\'t send to $name.';
  }

  @override
  String get sendDeviceChanged =>
      'The device pairing changed. Choose a device again.';

  @override
  String get originalSendDeviceUnavailable =>
      'The original device is unavailable.';

  @override
  String get reviewSendContent => 'Review content';

  @override
  String get preparingSendContent => 'Preparing content…';

  @override
  String get discardSend => 'Discard send';

  @override
  String get receiveFailed => 'Could not receive';

  @override
  String get transferInterrupted => 'Transfer interrupted. Try again.';

  @override
  String get transferDeclined => 'The other device declined.';

  @override
  String get saveFailed => 'Could not save the file. Check storage space.';

  @override
  String get emptyClipboard => 'There is nothing to send on the clipboard.';

  @override
  String get singleClipboardFile =>
      'Only one clipboard file can be sent at a time.';

  @override
  String get readSharedFailed => 'Could not read the shared file.';

  @override
  String get readClipboardFailed =>
      'Couldn\'t read the clipboard. Copy the content again and retry.';

  @override
  String get writeClipboardFailed =>
      'Received, but couldn\'t copy to the clipboard.';

  @override
  String get incomingClipboardHint =>
      'Accepting replaces this device’s clipboard.';

  @override
  String get startingVela => 'Starting Vela…';

  @override
  String get startupFailed => 'Vela could not start.';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get diagnosticsStartupHelp => 'Vela isn’t ready yet.';

  @override
  String get diagnosticsDeviceHelp =>
      'Open Vela on your other devices, then refresh their status.';

  @override
  String diagnosticsUnreachableDevices(String names) {
    return 'Temporarily unreachable · $names';
  }

  @override
  String get diagnosticsRetryStartup => 'Try starting Vela again';

  @override
  String get diagnosticsRecoveryFailed =>
      'Could not complete the check. Try again.';

  @override
  String get diagnosticsClearEvents => 'Clear events';

  @override
  String get diagnosticsClearQuestion => 'Clear diagnostic events?';

  @override
  String diagnosticsUpdated(String time) {
    return 'Updated at $time';
  }

  @override
  String diagnosticsStale(String time) {
    return 'Refresh failed. Showing results from $time.';
  }

  @override
  String get mobile => 'Phone';

  @override
  String get tablet => 'Tablet';

  @override
  String get desktop => 'Computer';

  @override
  String get device => 'Device';

  @override
  String get reachable => 'Reachable';

  @override
  String get unreachable => 'Temporarily unreachable';

  @override
  String get checking => 'Checking';

  @override
  String get unknown => 'Status unknown';

  @override
  String get more => 'More options';

  @override
  String get storageFailed => 'Could not save settings.';

  @override
  String get systemDeviceName => 'Original device name';

  @override
  String get deviceAliasHint => 'Only shown on this device.';

  @override
  String get selectFileFirst => 'Choose a file, then a device.';

  @override
  String get requestAccepted => 'Device added';

  @override
  String deviceCodeShort(String code) {
    return 'Device code $code';
  }

  @override
  String peerUnpaired(String name) {
    return '$name unpaired this device.';
  }

  @override
  String addedPeer(String name) {
    return 'Added $name';
  }

  @override
  String sentTo(String name) {
    return 'Sent to $name';
  }

  @override
  String receiving(String name) {
    return 'Receiving $name';
  }

  @override
  String get notificationTransferring => 'Transferring';

  @override
  String get notificationTransferringShort => 'Moving';

  @override
  String sendingTo(String name) {
    return 'Sending to $name';
  }

  @override
  String connectingTo(String name) {
    return 'Connecting to $name';
  }

  @override
  String received(String name) {
    return 'Received $name';
  }

  @override
  String shareFrom(String name) {
    return 'Sharing from $name';
  }

  @override
  String removeDeviceBody(String name) {
    return 'This also unpairs $name. If they are offline, sync will retry when both devices open the updated app and reconnect.';
  }

  @override
  String failedWithReason(String reason, String title) {
    return '$title: $reason';
  }

  @override
  String get refreshDevices => 'Refresh device status';

  @override
  String get refreshThisDevice => 'Refresh this device';

  @override
  String get transferCancelled => 'Transfer cancelled';

  @override
  String get cancelling => 'Cancelling';

  @override
  String get directConnection => 'Direct';

  @override
  String get relayConnection => 'Relay';

  @override
  String get transferHistory => 'Received';

  @override
  String get viewReceivedBatch => 'View this batch';

  @override
  String get receivedBatch => 'Received batch';

  @override
  String get receivedBatchUnavailable =>
      'The records for this batch are unavailable.';

  @override
  String showMoreOfferedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Show $count more files',
      one: 'Show 1 more file',
    );
    return '$_temp0';
  }

  @override
  String get showFewerOfferedFiles => 'Show fewer files';

  @override
  String get openFile => 'Open file';

  @override
  String get openReceiveFolder => 'Open receive folder';

  @override
  String get showInFolder => 'Open containing folder';

  @override
  String get recordDetails => 'Details';

  @override
  String get recordName => 'Name';

  @override
  String get recordDevice => 'Device';

  @override
  String get recordTime => 'Time';

  @override
  String get fileDetails => 'File details';

  @override
  String get fileNameLabel => 'Name';

  @override
  String get fileSizeLabel => 'Size';

  @override
  String get receivedAtLabel => 'Received';

  @override
  String get receivedFromLabel => 'From';

  @override
  String get connectingShort => 'Linking';

  @override
  String get incomingShort => 'Incoming';

  @override
  String get noTransferHistory => 'No received items yet';

  @override
  String get manageRecords => 'Manage records';

  @override
  String get selectRecords => 'Select records';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get clearHistory => 'Clear history';

  @override
  String get clearHistoryConfirm =>
      'Clear received history? Received files will not be deleted.';

  @override
  String historyReceivedFrom(String name) {
    return 'From $name';
  }

  @override
  String get moreOptions => 'More options';

  @override
  String get removeRecord => 'Remove record';

  @override
  String get historyText => 'Clipboard text';

  @override
  String get historyImage => 'Clipboard image';

  @override
  String get historyUnknownDevice => 'Unknown device';

  @override
  String get historyMissing => 'File is missing or cannot be accessed';

  @override
  String get historyCopy => 'Copy';

  @override
  String get historyCopied => 'Copied';

  @override
  String get historyCopyFiles => 'Copy files';

  @override
  String get historyCopyFailed => 'Couldn’t copy to the clipboard. Try again.';

  @override
  String get historySaveFailed => 'Transferred, but could not save history';

  @override
  String filesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String filesReceived(int count) {
    return 'Received $count files';
  }

  @override
  String get viewHistory => 'View history';

  @override
  String get dropFilesOnly => 'Folders are not supported yet';

  @override
  String get tooManyFiles => 'You can send up to 100 files at once';

  @override
  String get backgroundReceiving => 'Background receiving';

  @override
  String get enableBackgroundReceiving => 'Allow background receiving';

  @override
  String get notificationSettings => 'Notifications';

  @override
  String get notificationSystemSettings => 'System notification settings';

  @override
  String get notificationOn => 'On';

  @override
  String get notificationOff => 'Off';

  @override
  String get notificationRequests => 'Incoming request notifications';

  @override
  String get notificationProgress => 'Transfer progress';

  @override
  String get notificationResults => 'Transfer results';

  @override
  String get notificationLive => 'Live updates';

  @override
  String get notificationCompleted => 'Transfer complete';

  @override
  String get notificationCompletedShort => 'Done';

  @override
  String get backgroundReady => 'Receiving service started';

  @override
  String get backgroundStartHint => 'Off';

  @override
  String get backgroundMacMaySleep => 'Receives while awake';

  @override
  String get backgroundMacInactive => 'Idle sleep is still allowed';

  @override
  String get backgroundMacAwake => 'Idle sleep blocked';

  @override
  String get backgroundTrayUnavailable => 'Keep the window open';

  @override
  String get backgroundTrayReady => 'Tray active';

  @override
  String get backgroundServiceStopped => 'Service not ready';

  @override
  String get backgroundAllowRequests => 'Request notifications are off';

  @override
  String get backgroundAppNotificationsOff => 'Vela notifications are off';

  @override
  String get backgroundOpenBatterySettings => 'Open app settings';

  @override
  String get backgroundBatteryLimitsLockedReceiving =>
      'Battery optimization can interrupt receiving while locked';

  @override
  String get backgroundSettingsOpenFailed => 'Could not open system settings.';

  @override
  String get backgroundCheckBattery => 'Check battery settings';

  @override
  String get backgroundServiceReady => 'Service running';

  @override
  String get settingsTroubleshooting => 'Troubleshooting';

  @override
  String get userGuide => 'User guide';

  @override
  String get backgroundUnavailable =>
      'Could not change background receiving. Check system settings.';

  @override
  String get backgroundNotification => 'Notifications';

  @override
  String get backgroundBattery => 'Battery optimization exemption';

  @override
  String get backgroundBatteryExempt => 'Exempt';

  @override
  String get backgroundBatteryRestricted => 'Restricted';

  @override
  String get backgroundBatteryOptimized => 'Not exempt';

  @override
  String get backgroundRestricted => 'System background restrictions';

  @override
  String get backgroundBatteryHint =>
      'If the device frequently goes offline, allow unrestricted battery use in system settings.';

  @override
  String get backgroundVendorGuide => 'Background receiving guide';

  @override
  String get backgroundOffer => 'A device is sending content';

  @override
  String get backgroundOn => 'On';

  @override
  String get saveAs => 'Save as';

  @override
  String get revealInFinder => 'Show in Finder';

  @override
  String get savedFile => 'File saved';

  @override
  String get saveFileFailed => 'Could not save file';

  @override
  String get openLink => 'Open link';

  @override
  String get openLinkFailed => 'Could not open link';

  @override
  String get openAfterReceive => 'Show window after receiving';

  @override
  String get autoAccept => 'Auto accept';

  @override
  String get retry => 'Retry';

  @override
  String get fileUnavailable => 'Cannot read the file. Select it again.';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsReceiving => 'Receiving';

  @override
  String get saveLocation => 'Save location';

  @override
  String get downloadsFolder => 'Downloads';

  @override
  String get chooseFolder => 'Choose folder';

  @override
  String get useDownloads => 'Use Downloads';

  @override
  String get saveLocationUnavailable =>
      'Vela can\'t access the selected folder.';

  @override
  String get chooseSaveLocationAgain => 'Choose a save location again';

  @override
  String get savingFile => 'Saving';

  @override
  String get savedPrivately =>
      'Couldn\'t save to the selected location. The file is kept in Vela.';

  @override
  String get settingsAbout => 'About Vela';

  @override
  String get appUpdateCheck => 'Check';

  @override
  String get appUpdateFailed => 'Could not update.';

  @override
  String get relaySettings => 'Relay servers';

  @override
  String get relayEnabled => 'Use custom relays';

  @override
  String get relayEnabledDetail => 'Using public relays until you add one.';

  @override
  String get relayToggleFailed => 'Could not change relay settings';

  @override
  String get relayBusy => 'Finish the current transfer or pairing first';

  @override
  String get relayCustomOnly => 'Use the same relays on your other devices.';

  @override
  String get relayShowToken => 'Show token';

  @override
  String get relayHideToken => 'Hide token';

  @override
  String get relayDefaultsKept => 'Public relays remain available';

  @override
  String get addRelay => 'Add relay';

  @override
  String get editRelay => 'Edit relay';

  @override
  String get relayUrl => 'Relay address';

  @override
  String get relayToken => 'Access token (optional)';

  @override
  String get relayInvalid => 'Enter a valid HTTPS relay address';

  @override
  String get relayDuplicate => 'This relay is already added';

  @override
  String get relayFailed => 'Could not save the relay. Try again.';

  @override
  String get relayRemove => 'Remove relay';

  @override
  String get relayTest => 'Test connection';

  @override
  String get relayTestShort => 'Test';

  @override
  String get relayTestSuccess => 'This device can reach the relay.';

  @override
  String get relayTestAuth => 'Access denied. Check the token.';

  @override
  String get relayTestTimeout =>
      'Connection timed out. Check the address and network.';

  @override
  String get relayTestFailed => 'Could not connect to the relay.';

  @override
  String get searchHistory => 'Search history';

  @override
  String get noHistoryMatches => 'No matching records';

  @override
  String get transferBusy =>
      'Another transfer is in progress. Try again shortly.';

  @override
  String get backgroundUnknown => 'Unknown';

  @override
  String get backgroundLowPowerStandbyRestricted =>
      'Low Power Standby restricts network access while locked';

  @override
  String get backgroundAutoStart => 'Auto-start settings';

  @override
  String get backgroundLogin => 'Open at login';

  @override
  String get backgroundLoginApproval =>
      'Allow launch at login in System Settings';

  @override
  String get backgroundOpenLoginSettings => 'Open Login Items';

  @override
  String get backgroundLoginFailed => 'Could not change launch at login.';

  @override
  String get sendText => 'Send text';

  @override
  String get enterText => 'Type or paste text';

  @override
  String get folder => 'Folder';

  @override
  String get preparingFolder => 'Preparing folder…';

  @override
  String get folderPrepareFailed => 'Could not prepare the folder';

  @override
  String get restoreFolder => 'Restore folder';

  @override
  String get restoringFolder => 'Restoring folder…';

  @override
  String get folderRestored => 'Folder restored';

  @override
  String get folderRestoreFailed =>
      'Could not restore the folder. The archive was kept.';

  @override
  String get textContent => 'Text';

  @override
  String get textReceived => 'Text received';

  @override
  String get view => 'View';

  @override
  String get viewText => 'View text';

  @override
  String get textTooLarge => 'Text must be no larger than 1 MiB';

  @override
  String get trayOpen => 'Open Vela';

  @override
  String get trayQuit => 'Quit';

  @override
  String get desktopTray => 'System tray';

  @override
  String get graphPairedDevicesHint =>
      'Lines show paired devices. Switch to the list for connection status.';

  @override
  String get addDeviceAndContinue => 'Add device and continue';

  @override
  String get sendContentReady => 'Done';

  @override
  String waitingForRecipient(String name) {
    return 'Waiting for $name to respond';
  }

  @override
  String sendDeclinedBy(String name) {
    return '$name declined the transfer.';
  }
}
