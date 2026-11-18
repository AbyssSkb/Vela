import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @deviceRemoved.
  ///
  /// In en, this message translates to:
  /// **'Device removed'**
  String get deviceRemoved;

  /// No description provided for @legacyPairingsNotice.
  ///
  /// In en, this message translates to:
  /// **'Existing device pairings need to be set up again. Your files and history are unchanged.'**
  String get legacyPairingsNotice;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @showList.
  ///
  /// In en, this message translates to:
  /// **'Show list'**
  String get showList;

  /// No description provided for @showGraph.
  ///
  /// In en, this message translates to:
  /// **'Show graph'**
  String get showGraph;

  /// No description provided for @myDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get myDevice;

  /// No description provided for @addDevice.
  ///
  /// In en, this message translates to:
  /// **'Add device'**
  String get addDevice;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @deviceName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceName;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @simplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get simplifiedChinese;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @deviceDetails.
  ///
  /// In en, this message translates to:
  /// **'Device details'**
  String get deviceDetails;

  /// No description provided for @renameDevice.
  ///
  /// In en, this message translates to:
  /// **'Rename device'**
  String get renameDevice;

  /// No description provided for @useDeviceName.
  ///
  /// In en, this message translates to:
  /// **'Use device name'**
  String get useDeviceName;

  /// No description provided for @deviceNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a device name'**
  String get deviceNameRequired;

  /// No description provided for @nameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Device name is too long'**
  String get nameTooLong;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// No description provided for @media.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get media;

  /// No description provided for @mediaPickFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the photo picker. Try again.'**
  String get mediaPickFailed;

  /// No description provided for @clipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get clipboard;

  /// No description provided for @sendFile.
  ///
  /// In en, this message translates to:
  /// **'Send file'**
  String get sendFile;

  /// No description provided for @sendClipboard.
  ///
  /// In en, this message translates to:
  /// **'Send clipboard'**
  String get sendClipboard;

  /// No description provided for @chooseDevice.
  ///
  /// In en, this message translates to:
  /// **'Choose a device'**
  String get chooseDevice;

  /// No description provided for @sendSelected.
  ///
  /// In en, this message translates to:
  /// **'Send selected item'**
  String get sendSelected;

  /// No description provided for @cancelShare.
  ///
  /// In en, this message translates to:
  /// **'Cancel share'**
  String get cancelShare;

  /// No description provided for @pendingContent.
  ///
  /// In en, this message translates to:
  /// **'Ready to send: {content}'**
  String pendingContent(String content);

  /// No description provided for @sendToDevice.
  ///
  /// In en, this message translates to:
  /// **'Send to {name}'**
  String sendToDevice(String name);

  /// No description provided for @connectDevices.
  ///
  /// In en, this message translates to:
  /// **'Connect your devices'**
  String get connectDevices;

  /// No description provided for @emptyDevices.
  ///
  /// In en, this message translates to:
  /// **'Open Vela on both devices. Show the code on one, then add it on the other.'**
  String get emptyDevices;

  /// No description provided for @showMyCode.
  ///
  /// In en, this message translates to:
  /// **'Show my QR code'**
  String get showMyCode;

  /// No description provided for @deviceCode.
  ///
  /// In en, this message translates to:
  /// **'Device code'**
  String get deviceCode;

  /// No description provided for @copyDeviceCode.
  ///
  /// In en, this message translates to:
  /// **'Copy device code'**
  String get copyDeviceCode;

  /// No description provided for @deviceCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Device code copied'**
  String get deviceCodeCopied;

  /// No description provided for @showDeviceCode.
  ///
  /// In en, this message translates to:
  /// **'On the other device, choose Add device and scan this QR code or enter the device code. Then approve the request here.'**
  String get showDeviceCode;

  /// No description provided for @enterOrScan.
  ///
  /// In en, this message translates to:
  /// **'On the other device, open This device to show its code. Enter it here or scan its QR code.'**
  String get enterOrScan;

  /// No description provided for @enterCode.
  ///
  /// In en, this message translates to:
  /// **'On the other device, open This device and enter its code here.'**
  String get enterCode;

  /// No description provided for @scanCode.
  ///
  /// In en, this message translates to:
  /// **'Scan device code'**
  String get scanCode;

  /// No description provided for @scanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan device code'**
  String get scanTitle;

  /// No description provided for @cameraError.
  ///
  /// In en, this message translates to:
  /// **'Cannot open the camera. Check camera permission.'**
  String get cameraError;

  /// No description provided for @invalidDeviceCode.
  ///
  /// In en, this message translates to:
  /// **'Enter a 64-character device code'**
  String get invalidDeviceCode;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @cannotAddSelf.
  ///
  /// In en, this message translates to:
  /// **'You cannot add this device.'**
  String get cannotAddSelf;

  /// No description provided for @connectingPair.
  ///
  /// In en, this message translates to:
  /// **'Adding device… Confirm the request on the other device.'**
  String get connectingPair;

  /// No description provided for @pairRequest.
  ///
  /// In en, this message translates to:
  /// **'Add device?'**
  String get pairRequest;

  /// No description provided for @confirmOwnDevice.
  ///
  /// In en, this message translates to:
  /// **'Confirm this is your device.'**
  String get confirmOwnDevice;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get reject;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @pairDeclined.
  ///
  /// In en, this message translates to:
  /// **'The other device declined the request.'**
  String get pairDeclined;

  /// No description provided for @pairConflict.
  ///
  /// In en, this message translates to:
  /// **'The other device is already adding this device. Please try again.'**
  String get pairConflict;

  /// No description provided for @pairWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the device'**
  String get pairWaiting;

  /// No description provided for @pairFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect. Check that both devices are running the latest version.'**
  String get pairFailed;

  /// No description provided for @removeDevice.
  ///
  /// In en, this message translates to:
  /// **'Remove device'**
  String get removeDevice;

  /// No description provided for @removeDeviceQuestion.
  ///
  /// In en, this message translates to:
  /// **'Remove device?'**
  String get removeDeviceQuestion;

  /// No description provided for @selectDevices.
  ///
  /// In en, this message translates to:
  /// **'Select devices'**
  String get selectDevices;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @removeDevicesQuestion.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Remove 1 device?} other{Remove {count} devices?}}'**
  String removeDevicesQuestion(int count);

  /// No description provided for @removeDevicesBody.
  ///
  /// In en, this message translates to:
  /// **'The selected devices will be unpaired. Offline devices will sync when they reconnect.'**
  String get removeDevicesBody;

  /// No description provided for @removeRecordsQuestion.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Remove 1 record?} other{Remove {count} records?}}'**
  String removeRecordsQuestion(int count);

  /// No description provided for @removeRecordsBody.
  ///
  /// In en, this message translates to:
  /// **'Removing records keeps the files. Deleted files cannot be recovered.'**
  String get removeRecordsBody;

  /// No description provided for @removeRecordsOnly.
  ///
  /// In en, this message translates to:
  /// **'Remove records only'**
  String get removeRecordsOnly;

  /// No description provided for @removeRecordsAndFiles.
  ///
  /// In en, this message translates to:
  /// **'Also delete files'**
  String get removeRecordsAndFiles;

  /// No description provided for @removeRecordAndFile.
  ///
  /// In en, this message translates to:
  /// **'Delete records and files'**
  String get removeRecordAndFile;

  /// No description provided for @deleteFilesWarning.
  ///
  /// In en, this message translates to:
  /// **'Deleted files cannot be recovered.'**
  String get deleteFilesWarning;

  /// No description provided for @deleteFilesFailed.
  ///
  /// In en, this message translates to:
  /// **'Some files could not be deleted; their records were kept.'**
  String get deleteFilesFailed;

  /// No description provided for @removalSyncing.
  ///
  /// In en, this message translates to:
  /// **'Removed. Syncing to the other device.'**
  String get removalSyncing;

  /// No description provided for @receive.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get receive;

  /// No description provided for @clipboardText.
  ///
  /// In en, this message translates to:
  /// **'Clipboard text'**
  String get clipboardText;

  /// No description provided for @clipboardImage.
  ///
  /// In en, this message translates to:
  /// **'Clipboard image'**
  String get clipboardImage;

  /// No description provided for @clipboardReceived.
  ///
  /// In en, this message translates to:
  /// **'Clipboard received'**
  String get clipboardReceived;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @openNoApp.
  ///
  /// In en, this message translates to:
  /// **'No app can open this file.'**
  String get openNoApp;

  /// No description provided for @openFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file.'**
  String get openFailed;

  /// No description provided for @sendFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send'**
  String get sendFailed;

  /// No description provided for @sendFailedTo.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send to {name}.'**
  String sendFailedTo(String name);

  /// No description provided for @sendDeviceChanged.
  ///
  /// In en, this message translates to:
  /// **'The device pairing changed. Discard this send and select the device again.'**
  String get sendDeviceChanged;

  /// No description provided for @discardSend.
  ///
  /// In en, this message translates to:
  /// **'Discard send'**
  String get discardSend;

  /// No description provided for @receiveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not receive'**
  String get receiveFailed;

  /// No description provided for @transferInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Transfer interrupted. Try again.'**
  String get transferInterrupted;

  /// No description provided for @transferDeclined.
  ///
  /// In en, this message translates to:
  /// **'The other device declined.'**
  String get transferDeclined;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the file. Check storage space.'**
  String get saveFailed;

  /// No description provided for @emptyClipboard.
  ///
  /// In en, this message translates to:
  /// **'There is nothing to send on the clipboard.'**
  String get emptyClipboard;

  /// No description provided for @singleClipboardFile.
  ///
  /// In en, this message translates to:
  /// **'Only one clipboard file can be sent at a time.'**
  String get singleClipboardFile;

  /// No description provided for @readSharedFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the shared file.'**
  String get readSharedFailed;

  /// No description provided for @readClipboardFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the clipboard. Copy the content again and retry.'**
  String get readClipboardFailed;

  /// No description provided for @writeClipboardFailed.
  ///
  /// In en, this message translates to:
  /// **'Received, but couldn\'t copy to the clipboard.'**
  String get writeClipboardFailed;

  /// No description provided for @startupFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start. Restart the app.'**
  String get startupFailed;

  /// No description provided for @mobile.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get mobile;

  /// No description provided for @tablet.
  ///
  /// In en, this message translates to:
  /// **'Tablet'**
  String get tablet;

  /// No description provided for @desktop.
  ///
  /// In en, this message translates to:
  /// **'Computer'**
  String get desktop;

  /// No description provided for @device.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get device;

  /// No description provided for @reachable.
  ///
  /// In en, this message translates to:
  /// **'Reachable'**
  String get reachable;

  /// No description provided for @unreachable.
  ///
  /// In en, this message translates to:
  /// **'Temporarily unreachable'**
  String get unreachable;

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get checking;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Status unknown'**
  String get unknown;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get more;

  /// No description provided for @storageFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save settings.'**
  String get storageFailed;

  /// No description provided for @systemDeviceName.
  ///
  /// In en, this message translates to:
  /// **'Use system device name'**
  String get systemDeviceName;

  /// No description provided for @nameVisible.
  ///
  /// In en, this message translates to:
  /// **'Your other devices will see this name.'**
  String get nameVisible;

  /// No description provided for @deviceAliasHint.
  ///
  /// In en, this message translates to:
  /// **'Only shown on this device.'**
  String get deviceAliasHint;

  /// No description provided for @selectFileFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose a file, then a device.'**
  String get selectFileFirst;

  /// No description provided for @noDevices.
  ///
  /// In en, this message translates to:
  /// **'Add a device first.'**
  String get noDevices;

  /// No description provided for @requestAccepted.
  ///
  /// In en, this message translates to:
  /// **'Device added'**
  String get requestAccepted;

  /// No description provided for @deviceCodeShort.
  ///
  /// In en, this message translates to:
  /// **'Device code {code}'**
  String deviceCodeShort(String code);

  /// No description provided for @peerUnpaired.
  ///
  /// In en, this message translates to:
  /// **'{name} unpaired this device.'**
  String peerUnpaired(String name);

  /// No description provided for @addedPeer.
  ///
  /// In en, this message translates to:
  /// **'Added {name}'**
  String addedPeer(String name);

  /// No description provided for @sentTo.
  ///
  /// In en, this message translates to:
  /// **'Sent to {name}'**
  String sentTo(String name);

  /// No description provided for @receiving.
  ///
  /// In en, this message translates to:
  /// **'Receiving {name}'**
  String receiving(String name);

  /// No description provided for @notificationSending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get notificationSending;

  /// No description provided for @sendingTo.
  ///
  /// In en, this message translates to:
  /// **'Sending to {name}'**
  String sendingTo(String name);

  /// No description provided for @connectingTo.
  ///
  /// In en, this message translates to:
  /// **'Sending to {name}'**
  String connectingTo(String name);

  /// No description provided for @received.
  ///
  /// In en, this message translates to:
  /// **'Received {name}'**
  String received(String name);

  /// No description provided for @shareFrom.
  ///
  /// In en, this message translates to:
  /// **'Sharing from {name}'**
  String shareFrom(String name);

  /// No description provided for @removeDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'This also unpairs {name}. If they are offline, sync will retry when both devices open the updated app and reconnect.'**
  String removeDeviceBody(String name);

  /// No description provided for @failedWithReason.
  ///
  /// In en, this message translates to:
  /// **'{title}: {reason}'**
  String failedWithReason(String reason, String title);

  /// No description provided for @refreshDevices.
  ///
  /// In en, this message translates to:
  /// **'Refresh device status'**
  String get refreshDevices;

  /// No description provided for @transferCancelled.
  ///
  /// In en, this message translates to:
  /// **'Transfer cancelled'**
  String get transferCancelled;

  /// No description provided for @cancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling'**
  String get cancelling;

  /// No description provided for @directConnection.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get directConnection;

  /// No description provided for @relayConnection.
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get relayConnection;

  /// No description provided for @transferHistory.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get transferHistory;

  /// No description provided for @openReceivedHistory.
  ///
  /// In en, this message translates to:
  /// **'View received items'**
  String get openReceivedHistory;

  /// No description provided for @openFile.
  ///
  /// In en, this message translates to:
  /// **'Open file'**
  String get openFile;

  /// No description provided for @openReceiveFolder.
  ///
  /// In en, this message translates to:
  /// **'Open receive folder'**
  String get openReceiveFolder;

  /// No description provided for @showInFolder.
  ///
  /// In en, this message translates to:
  /// **'Open containing folder'**
  String get showInFolder;

  /// No description provided for @recordDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get recordDetails;

  /// No description provided for @recordName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get recordName;

  /// No description provided for @recordDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get recordDevice;

  /// No description provided for @recordTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get recordTime;

  /// No description provided for @fileDetails.
  ///
  /// In en, this message translates to:
  /// **'File details'**
  String get fileDetails;

  /// No description provided for @fileNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fileNameLabel;

  /// No description provided for @fileSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get fileSizeLabel;

  /// No description provided for @receivedAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get receivedAtLabel;

  /// No description provided for @receivedFromLabel.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get receivedFromLabel;

  /// No description provided for @connectingShort.
  ///
  /// In en, this message translates to:
  /// **'Linking'**
  String get connectingShort;

  /// No description provided for @incomingShort.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get incomingShort;

  /// No description provided for @transferNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transferNotificationTitle;

  /// No description provided for @noTransferHistory.
  ///
  /// In en, this message translates to:
  /// **'No received items yet'**
  String get noTransferHistory;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistory;

  /// No description provided for @clearHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear received history? Received files will not be deleted.'**
  String get clearHistoryConfirm;

  /// No description provided for @historyReceivedFrom.
  ///
  /// In en, this message translates to:
  /// **'From {name}'**
  String historyReceivedFrom(String name);

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @removeRecord.
  ///
  /// In en, this message translates to:
  /// **'Remove record'**
  String get removeRecord;

  /// No description provided for @historyText.
  ///
  /// In en, this message translates to:
  /// **'Clipboard text'**
  String get historyText;

  /// No description provided for @historyImage.
  ///
  /// In en, this message translates to:
  /// **'Clipboard image'**
  String get historyImage;

  /// No description provided for @historyUnknownDevice.
  ///
  /// In en, this message translates to:
  /// **'Unknown device'**
  String get historyUnknownDevice;

  /// No description provided for @historyMissing.
  ///
  /// In en, this message translates to:
  /// **'File is missing or cannot be accessed'**
  String get historyMissing;

  /// No description provided for @historyCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get historyCopy;

  /// No description provided for @historyCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get historyCopied;

  /// No description provided for @historySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Transferred, but could not save history'**
  String get historySaveFailed;

  /// No description provided for @filesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 file} other{{count} files}}'**
  String filesCount(int count);

  /// No description provided for @filesReceived.
  ///
  /// In en, this message translates to:
  /// **'Received {count} files'**
  String filesReceived(int count);

  /// No description provided for @viewHistory.
  ///
  /// In en, this message translates to:
  /// **'View history'**
  String get viewHistory;

  /// No description provided for @dropFilesHere.
  ///
  /// In en, this message translates to:
  /// **'Drop files to send'**
  String get dropFilesHere;

  /// No description provided for @dropFilesOnly.
  ///
  /// In en, this message translates to:
  /// **'Folders are not supported yet'**
  String get dropFilesOnly;

  /// No description provided for @dropAlreadyPending.
  ///
  /// In en, this message translates to:
  /// **'Finish with the selected content first'**
  String get dropAlreadyPending;

  /// No description provided for @tooManyFiles.
  ///
  /// In en, this message translates to:
  /// **'You can send up to 100 files at once'**
  String get tooManyFiles;

  /// No description provided for @backgroundReceiving.
  ///
  /// In en, this message translates to:
  /// **'Background receiving'**
  String get backgroundReceiving;

  /// No description provided for @notificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationSettings;

  /// No description provided for @notificationSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'System notification settings'**
  String get notificationSystemSettings;

  /// No description provided for @notificationRequests.
  ///
  /// In en, this message translates to:
  /// **'Incoming requests'**
  String get notificationRequests;

  /// No description provided for @notificationRequestsHint.
  ///
  /// In en, this message translates to:
  /// **'Alerts when a device sends content, with accept and decline actions'**
  String get notificationRequestsHint;

  /// No description provided for @notificationProgress.
  ///
  /// In en, this message translates to:
  /// **'Transfer progress'**
  String get notificationProgress;

  /// No description provided for @notificationProgressHint.
  ///
  /// In en, this message translates to:
  /// **'Shows progress and speed; uses live updates when supported'**
  String get notificationProgressHint;

  /// No description provided for @notificationResults.
  ///
  /// In en, this message translates to:
  /// **'Transfer results'**
  String get notificationResults;

  /// No description provided for @notificationResultsHint.
  ///
  /// In en, this message translates to:
  /// **'Keeps completion and failure notifications, with an option to open files'**
  String get notificationResultsHint;

  /// No description provided for @notificationLive.
  ///
  /// In en, this message translates to:
  /// **'Live updates'**
  String get notificationLive;

  /// No description provided for @notificationLiveAllowed.
  ///
  /// In en, this message translates to:
  /// **'Allowed; presentation is decided by the system'**
  String get notificationLiveAllowed;

  /// No description provided for @notificationLiveDisabled.
  ///
  /// In en, this message translates to:
  /// **'Not allowed; standard notifications are used'**
  String get notificationLiveDisabled;

  /// No description provided for @notificationLiveUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This system uses standard notifications'**
  String get notificationLiveUnsupported;

  /// No description provided for @notificationChannelHint.
  ///
  /// In en, this message translates to:
  /// **'Adjust banners, sound, vibration and lock-screen display in system settings'**
  String get notificationChannelHint;

  /// No description provided for @notificationReceivedTitle.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get notificationReceivedTitle;

  /// No description provided for @notificationReceivedShort.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get notificationReceivedShort;

  /// No description provided for @backgroundDescription.
  ///
  /// In en, this message translates to:
  /// **'Keep a connection available and receive requests in the background. A system notification is shown and battery use may increase.'**
  String get backgroundDescription;

  /// No description provided for @backgroundReady.
  ///
  /// In en, this message translates to:
  /// **'Waiting for devices'**
  String get backgroundReady;

  /// No description provided for @backgroundStartHint.
  ///
  /// In en, this message translates to:
  /// **'Off · Turn on to receive while Vela is in the background.'**
  String get backgroundStartHint;

  /// No description provided for @backgroundMacMaySleep.
  ///
  /// In en, this message translates to:
  /// **'Receives with the window closed while the Mac is awake.'**
  String get backgroundMacMaySleep;

  /// No description provided for @backgroundMacAwake.
  ///
  /// In en, this message translates to:
  /// **'Receives with the window closed. Idle sleep is prevented.'**
  String get backgroundMacAwake;

  /// No description provided for @backgroundTrayUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No system tray available. Leave the window open to receive.'**
  String get backgroundTrayUnavailable;

  /// No description provided for @backgroundTrayReady.
  ///
  /// In en, this message translates to:
  /// **'Receives from the tray while the computer is awake.'**
  String get backgroundTrayReady;

  /// No description provided for @backgroundServiceStopped.
  ///
  /// In en, this message translates to:
  /// **'Not ready · Check the receiving service and node below.'**
  String get backgroundServiceStopped;

  /// No description provided for @backgroundAllowRequests.
  ///
  /// In en, this message translates to:
  /// **'Allow incoming request notifications to accept in the background.'**
  String get backgroundAllowRequests;

  /// No description provided for @backgroundCheckBattery.
  ///
  /// In en, this message translates to:
  /// **'Check battery settings to keep background receiving available.'**
  String get backgroundCheckBattery;

  /// No description provided for @backgroundServiceReady.
  ///
  /// In en, this message translates to:
  /// **'Receiving service is running.'**
  String get backgroundServiceReady;

  /// No description provided for @settingsTroubleshooting.
  ///
  /// In en, this message translates to:
  /// **'Troubleshooting'**
  String get settingsTroubleshooting;

  /// No description provided for @backgroundUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not change background receiving. Check system settings.'**
  String get backgroundUnavailable;

  /// No description provided for @backgroundDiagnostic.
  ///
  /// In en, this message translates to:
  /// **'Background checks'**
  String get backgroundDiagnostic;

  /// No description provided for @backgroundNotification.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get backgroundNotification;

  /// No description provided for @backgroundBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery optimization'**
  String get backgroundBattery;

  /// No description provided for @backgroundRestricted.
  ///
  /// In en, this message translates to:
  /// **'System background restrictions'**
  String get backgroundRestricted;

  /// No description provided for @backgroundRunning.
  ///
  /// In en, this message translates to:
  /// **'Receiving service'**
  String get backgroundRunning;

  /// No description provided for @backgroundAllowed.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get backgroundAllowed;

  /// No description provided for @backgroundNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Check settings'**
  String get backgroundNeedsAttention;

  /// No description provided for @backgroundBatteryHint.
  ///
  /// In en, this message translates to:
  /// **'If the device frequently goes offline, allow unrestricted battery use in system settings.'**
  String get backgroundBatteryHint;

  /// No description provided for @backgroundVendorGuide.
  ///
  /// In en, this message translates to:
  /// **'View manufacturer guidance'**
  String get backgroundVendorGuide;

  /// No description provided for @backgroundLimits.
  ///
  /// In en, this message translates to:
  /// **'These checks reflect current system settings and cannot guarantee that every manufacturer will keep the app running.'**
  String get backgroundLimits;

  /// No description provided for @backgroundOffer.
  ///
  /// In en, this message translates to:
  /// **'A device is sending content'**
  String get backgroundOffer;

  /// No description provided for @backgroundOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get backgroundOff;

  /// No description provided for @backgroundOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get backgroundOn;

  /// No description provided for @saveAs.
  ///
  /// In en, this message translates to:
  /// **'Save as'**
  String get saveAs;

  /// No description provided for @revealInFinder.
  ///
  /// In en, this message translates to:
  /// **'Show in Finder'**
  String get revealInFinder;

  /// No description provided for @savedFile.
  ///
  /// In en, this message translates to:
  /// **'File saved'**
  String get savedFile;

  /// No description provided for @saveFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save file'**
  String get saveFileFailed;

  /// No description provided for @openLink.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get openLink;

  /// No description provided for @openLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open link'**
  String get openLinkFailed;

  /// No description provided for @focusOnReceive.
  ///
  /// In en, this message translates to:
  /// **'Show window for incoming requests'**
  String get focusOnReceive;

  /// No description provided for @focusOnReceiveHint.
  ///
  /// In en, this message translates to:
  /// **'Bring Vela to the foreground automatically'**
  String get focusOnReceiveHint;

  /// No description provided for @autoAccept.
  ///
  /// In en, this message translates to:
  /// **'Auto accept'**
  String get autoAccept;

  /// No description provided for @autoAcceptHint.
  ///
  /// In en, this message translates to:
  /// **'Receive content without confirmation'**
  String get autoAcceptHint;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @fileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cannot read the file. Select it again.'**
  String get fileUnavailable;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @settingsDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get settingsDevice;

  /// No description provided for @settingsReceiving.
  ///
  /// In en, this message translates to:
  /// **'Receiving'**
  String get settingsReceiving;

  /// No description provided for @saveLocation.
  ///
  /// In en, this message translates to:
  /// **'Save location'**
  String get saveLocation;

  /// No description provided for @downloadsFolder.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloadsFolder;

  /// No description provided for @chooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get chooseFolder;

  /// No description provided for @useDownloads.
  ///
  /// In en, this message translates to:
  /// **'Use Downloads'**
  String get useDownloads;

  /// No description provided for @saveLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Can\'t access this location. Choose it again.'**
  String get saveLocationUnavailable;

  /// No description provided for @savingFile.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get savingFile;

  /// No description provided for @savedPrivately.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save to the selected location. The file is kept in Vela.'**
  String get savedPrivately;

  /// No description provided for @settingsDisplay.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get settingsDisplay;

  /// No description provided for @relaySettings.
  ///
  /// In en, this message translates to:
  /// **'Relay servers'**
  String get relaySettings;

  /// No description provided for @relaySettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Manage custom relays'**
  String get relaySettingsHint;

  /// No description provided for @relayEnabled.
  ///
  /// In en, this message translates to:
  /// **'Use custom relays'**
  String get relayEnabled;

  /// No description provided for @relayEnabledDetail.
  ///
  /// In en, this message translates to:
  /// **'Uses public relays when no custom relay is configured'**
  String get relayEnabledDetail;

  /// No description provided for @relayDisabledDetail.
  ///
  /// In en, this message translates to:
  /// **'Uses Iroh public relays'**
  String get relayDisabledDetail;

  /// No description provided for @relayToggleFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change relay settings'**
  String get relayToggleFailed;

  /// No description provided for @relayBusy.
  ///
  /// In en, this message translates to:
  /// **'Finish the current transfer or pairing first'**
  String get relayBusy;

  /// No description provided for @relayCustomOnly.
  ///
  /// In en, this message translates to:
  /// **'Only custom relays are used. Configure the same relay list on your other devices.'**
  String get relayCustomOnly;

  /// No description provided for @relayPublic.
  ///
  /// In en, this message translates to:
  /// **'Public relays'**
  String get relayPublic;

  /// No description provided for @relayPublicDetail.
  ///
  /// In en, this message translates to:
  /// **'Default candidates'**
  String get relayPublicDetail;

  /// No description provided for @relayShowToken.
  ///
  /// In en, this message translates to:
  /// **'Show token'**
  String get relayShowToken;

  /// No description provided for @relayHideToken.
  ///
  /// In en, this message translates to:
  /// **'Hide token'**
  String get relayHideToken;

  /// No description provided for @relayDefaultsKept.
  ///
  /// In en, this message translates to:
  /// **'Public relays remain available'**
  String get relayDefaultsKept;

  /// No description provided for @addRelay.
  ///
  /// In en, this message translates to:
  /// **'Add relay'**
  String get addRelay;

  /// No description provided for @editRelay.
  ///
  /// In en, this message translates to:
  /// **'Edit relay'**
  String get editRelay;

  /// No description provided for @relayUrl.
  ///
  /// In en, this message translates to:
  /// **'Relay address'**
  String get relayUrl;

  /// No description provided for @relayToken.
  ///
  /// In en, this message translates to:
  /// **'Access token (optional)'**
  String get relayToken;

  /// No description provided for @relayInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid HTTPS relay address'**
  String get relayInvalid;

  /// No description provided for @relayDuplicate.
  ///
  /// In en, this message translates to:
  /// **'This relay is already added'**
  String get relayDuplicate;

  /// No description provided for @relayFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the relay. Try again.'**
  String get relayFailed;

  /// No description provided for @relayRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove relay'**
  String get relayRemove;

  /// No description provided for @relayTest.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get relayTest;

  /// No description provided for @relayTestShort.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get relayTestShort;

  /// No description provided for @relayTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Relay connected'**
  String get relayTestSuccess;

  /// No description provided for @relayTestAuth.
  ///
  /// In en, this message translates to:
  /// **'Access denied. Check the token.'**
  String get relayTestAuth;

  /// No description provided for @relayTestTimeout.
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Check the address and network.'**
  String get relayTestTimeout;

  /// No description provided for @relayTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the relay.'**
  String get relayTestFailed;

  /// No description provided for @searchHistory.
  ///
  /// In en, this message translates to:
  /// **'Search history'**
  String get searchHistory;

  /// No description provided for @noHistoryMatches.
  ///
  /// In en, this message translates to:
  /// **'No matching records'**
  String get noHistoryMatches;

  /// No description provided for @transferBusy.
  ///
  /// In en, this message translates to:
  /// **'Another transfer is in progress. Try again shortly.'**
  String get transferBusy;

  /// No description provided for @backgroundUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get backgroundUnknown;

  /// No description provided for @backgroundNode.
  ///
  /// In en, this message translates to:
  /// **'Receiving node'**
  String get backgroundNode;

  /// No description provided for @backgroundLowPowerStandby.
  ///
  /// In en, this message translates to:
  /// **'Low Power Standby exemption'**
  String get backgroundLowPowerStandby;

  /// No description provided for @backgroundAutoStart.
  ///
  /// In en, this message translates to:
  /// **'Auto-start'**
  String get backgroundAutoStart;

  /// No description provided for @backgroundAutoStartHint.
  ///
  /// In en, this message translates to:
  /// **'Status cannot be checked automatically. Search system settings for auto-start and enable Vela if available.'**
  String get backgroundAutoStartHint;

  /// No description provided for @backgroundAutoStartOplusHint.
  ///
  /// In en, this message translates to:
  /// **'Status cannot be checked automatically. Try Settings → Apps → Auto launch → Vela, or search settings for auto-start.'**
  String get backgroundAutoStartOplusHint;

  /// No description provided for @macKeepAwake.
  ///
  /// In en, this message translates to:
  /// **'Keep available in background'**
  String get macKeepAwake;

  /// No description provided for @macKeepAwakeHint.
  ///
  /// In en, this message translates to:
  /// **'Prevent idle sleep while Vela is running. The display can still turn off; battery use may increase.'**
  String get macKeepAwakeHint;

  /// No description provided for @macKeepAwakeActive.
  ///
  /// In en, this message translates to:
  /// **'Keep-awake activity'**
  String get macKeepAwakeActive;

  /// No description provided for @macKeepAwakeLimits.
  ///
  /// In en, this message translates to:
  /// **'Vela may still sleep when the lid is closed or sleep is requested.'**
  String get macKeepAwakeLimits;

  /// No description provided for @backgroundLogin.
  ///
  /// In en, this message translates to:
  /// **'Open at login'**
  String get backgroundLogin;

  /// No description provided for @backgroundLoginApproval.
  ///
  /// In en, this message translates to:
  /// **'Approval required in System Settings'**
  String get backgroundLoginApproval;

  /// No description provided for @backgroundLoginNotFound.
  ///
  /// In en, this message translates to:
  /// **'Login item unavailable'**
  String get backgroundLoginNotFound;

  /// No description provided for @backgroundLoginUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Requires macOS 13 or later'**
  String get backgroundLoginUnsupported;

  /// No description provided for @backgroundLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change the login item. Check System Settings.'**
  String get backgroundLoginFailed;

  /// No description provided for @backgroundNodeInitialized.
  ///
  /// In en, this message translates to:
  /// **'Initialized'**
  String get backgroundNodeInitialized;

  /// No description provided for @backgroundNodeNotInitialized.
  ///
  /// In en, this message translates to:
  /// **'Not initialized'**
  String get backgroundNodeNotInitialized;

  /// No description provided for @sendText.
  ///
  /// In en, this message translates to:
  /// **'Send text'**
  String get sendText;

  /// No description provided for @enterText.
  ///
  /// In en, this message translates to:
  /// **'Type or paste text'**
  String get enterText;

  /// No description provided for @folder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folder;

  /// No description provided for @preparingFolder.
  ///
  /// In en, this message translates to:
  /// **'Preparing folder…'**
  String get preparingFolder;

  /// No description provided for @folderPrepareFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare the folder'**
  String get folderPrepareFailed;

  /// No description provided for @restoreFolder.
  ///
  /// In en, this message translates to:
  /// **'Restore folder'**
  String get restoreFolder;

  /// No description provided for @restoringFolder.
  ///
  /// In en, this message translates to:
  /// **'Restoring folder…'**
  String get restoringFolder;

  /// No description provided for @folderRestored.
  ///
  /// In en, this message translates to:
  /// **'Folder restored'**
  String get folderRestored;

  /// No description provided for @folderRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not restore the folder. The archive was kept.'**
  String get folderRestoreFailed;

  /// No description provided for @textContent.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textContent;

  /// No description provided for @textReceived.
  ///
  /// In en, this message translates to:
  /// **'Text received'**
  String get textReceived;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @viewText.
  ///
  /// In en, this message translates to:
  /// **'View text'**
  String get viewText;

  /// No description provided for @textTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Text must be no larger than 1 MiB'**
  String get textTooLarge;

  /// No description provided for @desktopBackgroundHint.
  ///
  /// In en, this message translates to:
  /// **'Keep Vela in the system tray when the window is closed. Quit from the tray menu to stop receiving.'**
  String get desktopBackgroundHint;

  /// No description provided for @desktopBackgroundLimits.
  ///
  /// In en, this message translates to:
  /// **'Receiving stops when Vela is quit or the computer sleeps. Tray availability depends on your desktop environment.'**
  String get desktopBackgroundLimits;

  /// No description provided for @desktopTray.
  ///
  /// In en, this message translates to:
  /// **'System tray'**
  String get desktopTray;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
