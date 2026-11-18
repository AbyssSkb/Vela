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
  String get legacyPairingsNotice =>
      'Existing device pairings need to be set up again. Your files and history are unchanged.';

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
  String get useDeviceName => 'Use device name';

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
  String get selectedFile => 'File selected. Choose a device to send.';

  @override
  String get selectedText => 'Text selected. Choose a device to send.';

  @override
  String get connectDevices => 'Connect your devices';

  @override
  String get emptyDevices => 'Add a device to share files and clipboard.';

  @override
  String get deviceCode => 'Device code';

  @override
  String get copyDeviceCode => 'Copy device code';

  @override
  String get deviceCodeCopied => 'Device code copied';

  @override
  String get showDeviceCode =>
      'Scan or enter this code on your other device, then confirm the pairing request.';

  @override
  String get enterOrScan => 'Enter or scan the code from your other device.';

  @override
  String get enterCode => 'Enter the code from your other device.';

  @override
  String get scanCode => 'Scan device code';

  @override
  String get scanTitle => 'Scan device code';

  @override
  String get cameraError => 'Cannot open the camera. Check camera permission.';

  @override
  String get invalidDeviceCode => 'Enter a 64-character device code';

  @override
  String get connect => 'Connect';

  @override
  String get cannotAddSelf => 'You cannot add this device.';

  @override
  String get connectingPair => 'Adding device…';

  @override
  String get pairRequest => 'Add device?';

  @override
  String get confirmOwnDevice => 'Confirm this is your device.';

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
      'Could not connect. Check that both devices are running the latest version.';

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
  String get removeRecordsOnly => 'Records only';

  @override
  String get removeRecordsAndFiles => 'Also delete files';

  @override
  String get removeRecordAndFile => 'Delete record and file';

  @override
  String get deleteFilesWarning =>
      'The file will be permanently deleted and cannot be recovered.';

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
      'The device pairing changed. Discard this send and select the device again.';

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
  String get startupFailed => 'Could not start. Restart the app.';

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
  String get systemDeviceName => 'Use system device name';

  @override
  String get nameVisible => 'Your other devices will see this name.';

  @override
  String get deviceAliasHint => 'Only shown on this device.';

  @override
  String get selectFileFirst => 'Choose a file, then a device.';

  @override
  String get noDevices => 'Add a device first.';

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
  String get notificationSending => 'Sending';

  @override
  String sendingTo(String name) {
    return 'Sending to $name';
  }

  @override
  String connectingTo(String name) {
    return 'Sending to $name';
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
  String get transferNotificationTitle => 'Transfer';

  @override
  String get noTransferHistory => 'No received items yet';

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
  String get historySaveFailed => 'Transferred, but could not save history';

  @override
  String filesCount(int count) {
    return '$count files';
  }

  @override
  String filesReceived(int count) {
    return 'Received $count files';
  }

  @override
  String get viewHistory => 'View history';

  @override
  String get dropFilesHere => 'Drop files to send';

  @override
  String get dropFilesOnly => 'Folders are not supported yet';

  @override
  String get dropAlreadyPending => 'Finish with the selected content first';

  @override
  String get tooManyFiles => 'You can send up to 100 files at once';

  @override
  String get backgroundReceiving => 'Background receiving';

  @override
  String get notificationSettings => 'Notifications';

  @override
  String get notificationSystemSettings => 'System notification settings';

  @override
  String get notificationRequests => 'Incoming requests';

  @override
  String get notificationRequestsHint =>
      'Alerts when a device sends content, with accept and decline actions';

  @override
  String get notificationProgress => 'Transfer progress';

  @override
  String get notificationProgressHint =>
      'Shows progress and speed; uses live updates when supported';

  @override
  String get notificationResults => 'Transfer results';

  @override
  String get notificationResultsHint =>
      'Keeps completion and failure notifications, with an option to open files';

  @override
  String get notificationLive => 'Live updates';

  @override
  String get notificationLiveAllowed =>
      'Allowed; presentation is decided by the system';

  @override
  String get notificationLiveDisabled =>
      'Not allowed; standard notifications are used';

  @override
  String get notificationLiveUnsupported =>
      'This system uses standard notifications';

  @override
  String get notificationChannelHint =>
      'Adjust banners, sound, vibration and lock-screen display in system settings';

  @override
  String get notificationReceivedTitle => 'Received';

  @override
  String get notificationReceivedShort => 'Received';

  @override
  String get backgroundDescription =>
      'Keep a connection available and receive requests in the background. A system notification is shown and battery use may increase.';

  @override
  String get backgroundReady => 'Waiting for devices';

  @override
  String get backgroundUnavailable =>
      'Could not change background receiving. Check system settings.';

  @override
  String get backgroundDiagnostic => 'Background checks';

  @override
  String get backgroundNotification => 'Notifications';

  @override
  String get backgroundBattery => 'Battery optimization';

  @override
  String get backgroundRestricted => 'System background restrictions';

  @override
  String get backgroundRunning => 'Receiving service';

  @override
  String get backgroundAllowed => 'Allowed';

  @override
  String get backgroundNeedsAttention => 'Check settings';

  @override
  String get backgroundBatteryHint =>
      'If the device frequently goes offline, allow unrestricted battery use in system settings.';

  @override
  String get backgroundVendorGuide => 'View manufacturer guidance';

  @override
  String get backgroundLimits =>
      'These checks reflect current system settings and cannot guarantee that every manufacturer will keep the app running.';

  @override
  String get backgroundOffer => 'A device is sending content';

  @override
  String get backgroundOff => 'Off';

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
  String get focusOnReceive => 'Show window for incoming requests';

  @override
  String get focusOnReceiveHint => 'Bring Vela to the foreground automatically';

  @override
  String get autoAccept => 'Auto accept';

  @override
  String get autoAcceptHint => 'Receive content without confirmation';

  @override
  String get retry => 'Retry';

  @override
  String get fileUnavailable => 'Cannot read the file. Select it again.';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get settingsDevice => 'Device';

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
      'Can\'t access this location. Choose it again.';

  @override
  String get savingFile => 'Saving';

  @override
  String get savedPrivately =>
      'Couldn\'t save to the selected location. The file is kept in Vela.';

  @override
  String get settingsDisplay => 'Display';

  @override
  String get relaySettings => 'Relay servers';

  @override
  String get relaySettingsHint => 'Manage custom relays';

  @override
  String get relayEnabled => 'Use custom relays';

  @override
  String get relayEnabledDetail =>
      'Uses public relays when no custom relay is configured';

  @override
  String get relayDisabledDetail => 'Uses Iroh public relays';

  @override
  String get relayToggleFailed => 'Could not change relay settings';

  @override
  String get relayBusy => 'Finish the current transfer or pairing first';

  @override
  String get relayCustomOnly =>
      'Only custom relays are used. Configure the same relay list on your other devices.';

  @override
  String get relayPublic => 'Public relays';

  @override
  String get relayPublicDetail => 'Default candidates';

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
  String get relayTestSuccess => 'Relay connected';

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
  String get backgroundNode => 'Receiving node';

  @override
  String get backgroundLowPowerStandby => 'Low Power Standby exemption';

  @override
  String get backgroundAutoStart => 'Auto-start';

  @override
  String get backgroundAutoStartHint =>
      'Status cannot be checked automatically. Search system settings for auto-start and enable Vela if available.';

  @override
  String get backgroundAutoStartOplusHint =>
      'Status cannot be checked automatically. Try Settings → Apps → Auto launch → Vela, or search settings for auto-start.';

  @override
  String get macKeepAwake => 'Keep available in background';

  @override
  String get macKeepAwakeHint =>
      'Prevent idle sleep while Vela is running. The display can still turn off; battery use may increase.';

  @override
  String get macKeepAwakeActive => 'Keep-awake activity';

  @override
  String get macKeepAwakeLimits =>
      'Vela may still sleep when the lid is closed or sleep is requested.';

  @override
  String get backgroundLogin => 'Open at login';

  @override
  String get backgroundLoginApproval => 'Approval required in System Settings';

  @override
  String get backgroundLoginNotFound => 'Login item unavailable';

  @override
  String get backgroundLoginUnsupported => 'Requires macOS 13 or later';

  @override
  String get backgroundLoginFailed =>
      'Could not change the login item. Check System Settings.';

  @override
  String get backgroundNodeInitialized => 'Initialized';

  @override
  String get backgroundNodeNotInitialized => 'Not initialized';

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
  String get desktopBackgroundHint =>
      'Keep Vela in the system tray when the window is closed. Quit from the tray menu to stop receiving.';

  @override
  String get desktopBackgroundLimits =>
      'Receiving stops when Vela is quit or the computer sleeps. Tray availability depends on your desktop environment.';

  @override
  String get desktopTray => 'System tray';
}
