import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
// Debug-only integration driver for exercising two running desktop instances.
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dev_pair_test.dart';
import 'clipboard_content.dart';
import 'src/rust/api/node.dart';
import 'src/rust/api/folder.dart';
import 'src/rust/frb_generated.dart';
import 'l10n/generated/app_localizations.dart';
import 'peer_state.dart';
import 'app_runtime.dart';
import 'presence_controller.dart';
import 'content_kind.dart';
import 'transfer_failure.dart';
import 'received_storage.dart';
import 'incoming_offer_prompt.dart';
import 'received_content.dart';
import 'send_session.dart';
import 'paired_devices.dart';
import 'pending_share.dart';
import 'prepared_transfer.dart';
import 'pairing_session.dart';
import 'peer_confirmation.dart';
import 'presence_probe.dart';
import 'notice.dart';
import 'transfer_rate.dart';
import 'transfer_history.dart';
import 'transfer_history_store.dart';
import 'background_settings.dart';
import 'diagnostics_page.dart';
import 'notification_title.dart';
import 'relay_settings.dart';
import 'device_graph.dart';
import 'home_responsive_layout.dart';
import 'home_device_widgets.dart';
import 'home_toolbar.dart';
import 'device_pair_dialog.dart';
import 'settings_page.dart';
import 'app_update.dart';
import 'desktop_platform.dart';

export 'home_responsive_layout.dart';
export 'presence_controller.dart' show PeerPresence;
export 'device_pair_dialog.dart' show isDeviceId, deviceIdFromQr;

part 'debug_driver.dart';

final _testHome = GlobalKey<_HomePageState>();
bool _driverMode = false;

Future<void> main(List<String> args) async {
  if (kDebugMode && args.contains('--driver-test')) {
    _registerDebugDriver();
  }
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  if (kDebugMode && args.contains('--peer-test')) {
    final role = args.firstWhere((a) => a.startsWith('--role=')).substring(7);
    final runId = args.firstWhere((a) => a.startsWith('--run=')).substring(6);
    try {
      await runPeerTest(role, runId);
      exit(0);
    } catch (e, stack) {
      stderr.writeln('$e\n$stack');
      exit(1);
    }
  }
  final profile =
      args
          .where((arg) => arg.startsWith('--device='))
          .firstOrNull
          ?.substring('--device='.length) ??
      'default';
  final settings = await SharedPreferences.getInstance();
  if (DesktopPlatform.isWindowsOrLinux) {
    await _restoreDesktopTraySetting(settings, profile);
  }
  final language =
      settings.getString('language_$profile') ??
      (kDebugMode && _driverMode ? 'zh' : 'system');
  final appearance = settings.getString('appearance_$profile') ?? 'system';
  final diagnosticsEnabled = settings.getBool('diagnostics_enabled') ?? true;
  setDiagnosticsEnabled(enabled: diagnosticsEnabled);
  runApp(
    VelaApp(
      profile: profile,
      initialLanguage: language,
      initialAppearance: appearance,
      initialDiagnosticsEnabled: diagnosticsEnabled,
    ),
  );
}

Future<void> _restoreDesktopTraySetting(
  SharedPreferences settings,
  String profile,
) async {
  const tray = BackgroundReceiving.desktopTray;
  Future<bool> apply() async {
    try {
      await tray.setEnabled(tray.enabled(settings, profile));
      return true;
    } catch (error) {
      debugPrint('Could not restore desktop tray setting: $error');
      return false;
    }
  }

  if (!await apply()) {
    WidgetsBinding.instance.addPostFrameCallback((_) => apply());
  }
}

class VelaApp extends StatefulWidget {
  const VelaApp({
    super.key,
    required this.profile,
    required this.initialLanguage,
    required this.initialAppearance,
    required this.initialDiagnosticsEnabled,
  });
  final String profile;
  final String initialLanguage;
  final String initialAppearance;
  final bool initialDiagnosticsEnabled;
  @override
  State<VelaApp> createState() => _VelaAppState();
}

class _VelaAppState extends State<VelaApp> {
  late String language = widget.initialLanguage;
  late String appearance = widget.initialAppearance;
  late bool diagnosticsEnabled = widget.initialDiagnosticsEnabled;
  final liveActivity = ValueNotifier<Widget?>(null);

  @override
  void dispose() {
    liveActivity.dispose();
    super.dispose();
  }

  Future<void> _changeDiagnosticsEnabled(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setBool('diagnostics_enabled', value)) {
      throw StateError('Could not save setting');
    }
    setDiagnosticsEnabled(enabled: value);
    if (mounted) setState(() => diagnosticsEnabled = value);
  }

  Future<void> _changeSetting(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString('${key}_${widget.profile}', value)) {
      throw StateError('Could not save setting');
    }
    if (mounted) {
      setState(() {
        if (key == 'language') {
          language = value;
        } else {
          appearance = value;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff5367ca);
    ThemeData theme(Brightness brightness) {
      final scheme = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      );
      return ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: brightness == Brightness.light
            ? const Color(0xfff8f9fd)
            : scheme.surface,
      );
    }

    return MaterialApp(
      title: 'Vela',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      locale: language == 'system' ? null : Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: appearance == 'light'
          ? ThemeMode.light
          : appearance == 'dark'
          ? ThemeMode.dark
          : ThemeMode.system,
      builder: (context, child) => Overlay.wrap(
        child: ValueListenableBuilder(
          valueListenable: liveActivity,
          builder: (context, notice, _) => Column(
            children: [
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: notice != null,
                  child: child!,
                ),
              ),
              ?notice,
            ],
          ),
        ),
      ),
      home: HomePage(
        key: _testHome,
        profile: widget.profile,
        language: language,
        appearance: appearance,
        changeSetting: _changeSetting,
        diagnosticsEnabled: diagnosticsEnabled,
        changeDiagnosticsEnabled: _changeDiagnosticsEnabled,
        showLiveActivity: (notice) => liveActivity.value = notice,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.profile,
    required this.language,
    required this.appearance,
    required this.changeSetting,
    required this.diagnosticsEnabled,
    required this.changeDiagnosticsEnabled,
    this.showLiveActivity,
  });
  final String profile;
  final String language;
  final String appearance;
  final Future<void> Function(String, String) changeSetting;
  final bool diagnosticsEnabled;
  final Future<void> Function(bool) changeDiagnosticsEnabled;
  final ValueChanged<Widget?>? showLiveActivity;
  @override
  State<HomePage> createState() => _HomePageState();
}

enum ContentProcessing { preparingFolder, restoringFolder, savingReceived }

class _DiagnosticEntry {
  _DiagnosticEntry(this.kind, this.monotonicMs, [this.peer, this.peerName])
    : time = DateTime.now();
  final DateTime time;
  final int monotonicMs;
  final String kind;
  final String? peer;
  final String? peerName;
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final updates = AppUpdateController(
    prepareInstall: _prepareUpdateInstall,
  );
  static const storage = AppRuntime.secureStorage;
  static const receivedStorage = ReceivedStorage();
  static const clipboardChannel = MethodChannel('vela/clipboard');
  static const shareChannel = MethodChannel('vela/share');
  static const backgroundChannel = MethodChannel('vela/background');
  ({bool enabled, bool autoAccept, Map<Object?, Object?> status})?
  _backgroundAvailability;
  int _backgroundStatusRequest = 0;
  static const offerActionsChannel = MethodChannel('vela/offer_actions');
  late final runtime = AppRuntime(
    profile: widget.profile,
    testIdentity: kDebugMode && _driverMode,
    recordDiagnostic: _recordDiagnostic,
    onStartupFailure: _showStartupFailure,
    onMembershipChanging: _invalidatePeerMembership,
    onStateChanged: _publishPeerState,
    onMembershipWriteFinished: presenceController.membershipWriteFinished,
  );
  VelaNode? get node => runtime.node;
  TransferJob? activeTransfer;
  FolderArchiveJob? folderJob;
  bool folderOperation = false;
  SharedPreferences? prefs;
  PairedDevices? get pairedDevices => runtime.devices;
  PeerState get peerState => pairedDevices?.state ?? PeerState();
  Map<String, String> get peers => peerState.peers;
  Map<String, String> get peerTypes => peerState.types;
  Timer? startupRetry;
  bool legacyNoticePending = false;
  bool legacyNoticeShowing = false;
  Future<void>? startup;
  int startupFailures = 0;
  bool shuttingDown = false;
  bool closingForUpdate = false;
  AppUpdateState? lastUpdateState;
  late final PresenceController presenceController = PresenceController(
    pairingActive: (id) => pairings.isActiveFor(id),
    canPersistInfo: () => !changingRelay,
    recordDiagnostic: _recordDiagnostic,
    removeUnpaired: _removeUnpaired,
  );
  Map<String, PeerPresence> get presence => presenceController.values;
  Set<String> get visiblePresenceChecks => presenceController.visibleChecks;
  bool get refreshingPresence => presenceController.probing;
  bool get checkingPeers => presenceController.checkingPeers;
  bool foreground = true;
  AppLifecycleState? presenceLifecycle = WidgetsBinding.instance.lifecycleState;
  bool presenceWindowHidden = false;
  int windowVisibilityRevision = 0;
  bool get presenceVisible =>
      isPresenceVisible(presenceLifecycle, windowHidden: presenceWindowHidden);
  bool get monitorPresence => shouldMonitorPresence(
    presenceLifecycle,
    windowHidden: presenceWindowHidden,
    monitorWhileHidden: DesktopPlatform.isDesktop,
    androidBackgroundReceive:
        Platform.isAndroid &&
        BackgroundReceiving.androidService.enabled(prefs, widget.profile),
  );
  IncomingOfferPrompt? incomingPrompt;
  final List<_DiagnosticEntry> diagnosticEvents = [];
  final Set<String> selectedPeers = {};
  bool selectingPeers = false;
  String deviceView = 'list';
  String deviceName = '设备';
  String systemDeviceName = '设备';
  String deviceType = 'other';
  String? error;
  bool contentOperationActive = false;
  bool _publishedLiveActivity = false;
  late final PairingSessions pairings = PairingSessions(
    currentDevices: () => mounted ? pairedDevices : null,
    localInfo: () => DeviceInfo(name: deviceName, deviceType: deviceType),
    onPairingStarted: (id) => presenceController.pairingStarted(id),
  );
  String? activePairingPeer;
  bool get outgoingPairingUiActive => activePairingPeer != null;
  bool get awaitingOfferDecision => incomingPrompt?.openedDialog ?? false;
  bool changingRelay = false;
  int incomingOffersPending = 0;
  int activeSendOperations = 0;
  String? activity;
  AppLocalizations get t => AppLocalizations.of(context)!;
  String? lastMessage;
  ({String message, String content, bool sent})? _sendReceipt;
  String? receivedPath;
  bool disposed = false;
  Timer? progressTimer;
  double? transferProgress;
  TransferRate? transferRate;
  Stopwatch? transferClock;
  bool cancelling = false;
  ContentProcessing? contentProcessing;
  bool get processingLocalContent => contentProcessing != null;
  String? get contentProcessingLabel => switch (contentProcessing) {
    ContentProcessing.preparingFolder => t.preparingFolder,
    ContentProcessing.restoringFolder => t.restoringFolder,
    ContentProcessing.savingReceived => t.savingFile,
    null => null,
  };
  String connectionRoute = '';
  bool hasTransferred = false;
  int transferredBytes = 0;
  int totalBytes = 0;
  int lastSystemTransferUpdate = 0;
  String? sendingTo;
  String? notificationContentName;
  String? notificationPeerType;
  String? notificationTransferId;
  PendingShare? pendingShare;
  bool _composingText = false;
  ({
    String peer,
    Object? revision,
    String message,
    PreparedTransfer content,
    SendRetry retry,
  })?
  _failedSend;
  final List<Uint8List> dropBookmarks = [];
  final List<String> promisedDropFiles = [];
  bool dropHover = false, processingDrop = false;
  late final historyStore = TransferHistoryStore(widget.profile);

  bool get _updateBusy =>
      !canRestartNode ||
      startup != null ||
      folderOperation ||
      processingDrop ||
      _failedSend != null ||
      shuttingDown;

  Future<void> _prepareUpdateInstall() async {
    if (_updateBusy) throw PlatformException(code: 'busy');
    closingForUpdate = true;
    shuttingDown = true;
    startupRetry?.cancel();
    presenceController.reset();
    try {
      await runtime.close();
    } catch (_) {
      closingForUpdate = false;
      shuttingDown = false;
      unawaited(_startNode());
      rethrow;
    }
  }

  void _updatesChanged() {
    if (!mounted) return;
    if (closingForUpdate && shuttingDown && !updates.installing) {
      closingForUpdate = false;
      shuttingDown = false;
      unawaited(_startNode());
    }
    if (updates.state == AppUpdateState.ready &&
        lastUpdateState != AppUpdateState.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || shuttingDown || updates.state != AppUpdateState.ready) {
          return;
        }
        final zh = Localizations.localeOf(context).languageCode == 'zh';
        _message(
          zh ? '更新已下载，可在设置中安装' : 'Update downloaded. Install it from settings.',
          actionLabel: t.settings,
          onAction: () => unawaited(_showSettings()),
        );
      });
    }
    lastUpdateState = updates.state;
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      _updateDesktopStatus('setTrayLabels', {
        'open': t.trayOpen,
        'quit': t.trayQuit,
      });
    }
  }

  @override
  void initState() {
    super.initState();
    updates.addListener(_updatesChanged);
    unawaited(updates.start());
    presenceController.addListener(_presenceChanged);
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      offerActionsChannel.setMethodCallHandler((call) async {
        final arguments = call.arguments;
        if (call.method == 'cancelTransfer' &&
            arguments == notificationTransferId &&
            contentOperationActive &&
            !cancelling) {
          _cancelTransfer();
        }
        if (call.method == 'decision' && arguments is Map) {
          incomingPrompt?.notificationDecision(
            arguments['id'],
            arguments['accepted'],
          );
        }
      });
    }
    if (Platform.isAndroid ||
        Platform.isMacOS ||
        DesktopPlatform.isWindowsOrLinux) {
      backgroundChannel.setMethodCallHandler((call) async {
        if (call.method == 'shutdown' && DesktopPlatform.isDesktop) {
          shuttingDown = true;
          startupRetry?.cancel();
          activeTransfer?.cancel();
          await folderJob?.cancel();
          if (_failedSend?.retry.take() case final session?) {
            await _releaseSendSession(session);
          }
          try {
            if (Platform.isMacOS) {
              await backgroundChannel.invokeMethod<void>(
                'setMacBackground',
                false,
              );
            }
          } catch (e) {
            debugPrint('Could not stop background receiving: $e');
          }
          presenceController.reset();
          await runtime.dispose();
          return;
        }
        if (call.method == 'networkChanged' || call.method == 'systemWake') {
          final resumed = call.method == 'systemWake';
          try {
            _recordDiagnostic(resumed ? 'systemWake' : 'networkChanged');
          } catch (_) {
            debugPrint('Network event: diagnostics unavailable');
          }
          if (node == null && startupRetry?.isActive == true) {
            startupRetry?.cancel();
            unawaited(_retryStartup());
          }
          await presenceController.handleNetworkEvent(
            resumed
                ? PresenceNetworkEvent.systemWake
                : PresenceNetworkEvent.configurationChanged,
          );
        }
        if (call.method == 'hidden') {
          windowVisibilityRevision++;
          final wasMonitoring = monitorPresence;
          foreground = false;
          presenceWindowHidden = true;
          if (wasMonitoring != monitorPresence)
            presenceController.requestMonitoring(enabled: monitorPresence);
        }
        if (call.method == 'visible') {
          unawaited(_refreshBackgroundAvailability());
          windowVisibilityRevision++;
          final wasMonitoring = monitorPresence;
          final wasHidden = !presenceVisible;
          presenceWindowHidden = false;
          foreground = true;
          unawaited(_showLegacyPairingNotice());
          if (wasMonitoring != monitorPresence)
            presenceController.requestMonitoring(enabled: monitorPresence);
          incomingPrompt?.becameVisible();
          if (shouldRefreshForVisibility(
            visible: presenceVisible,
            becameVisible: wasHidden,
            refreshing: refreshingPresence,
          )) {
            unawaited(
              (wasHidden
                  ? presenceController.requestPeerProbes()
                  : presenceController.readCurrentSnapshot()),
            );
          }
        }
      });
    }
    if (Platform.isAndroid || Platform.isMacOS) {
      shareChannel.setMethodCallHandler((call) async {
        if (call.method == 'available') {
          if (Platform.isAndroid) await _showPendingReceipt();
          await _takePendingShare();
        }
      });
      if (Platform.isAndroid) unawaited(_showPendingReceipt());
      unawaited(_takePendingShare());
    }
    progressTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!updates.installing) unawaited(updates.setBusy(_updateBusy));
      final job = activeTransfer;
      if (!mounted ||
          !contentOperationActive ||
          (job == null && !processingLocalContent)) {
        return;
      }
      final p = job?.progress();
      final routeChanged = p != null && p.path != connectionRoute;
      final done = p?.done.toInt() ?? 0;
      final total = p?.total.toInt() ?? 0;
      final value = processingLocalContent || total == 0
          ? null
          : (done / total).clamp(0.0, 1.0);
      final started = !processingLocalContent && done > 0 && !hasTransferred;
      final rateBytes = transferRateBytes(
        sending: sendingTo != null,
        transferred: done,
        udpBytesSent: p?.udpBytesSent.toInt() ?? 0,
      );
      if (started) {
        transferRate = TransferRate(initialBytes: rateBytes);
        transferClock = Stopwatch()..start();
      }
      final updatedRate =
          !started &&
          (transferRate?.update(
                rateBytes,
                transferClock?.elapsedMilliseconds ?? 0,
              ) ??
              false);
      if (!processingLocalContent &&
          (value != transferProgress ||
              updatedRate ||
              started ||
              routeChanged)) {
        setState(() {
          if (routeChanged) connectionRoute = p.path;
          transferProgress = value;
          transferredBytes = done;
          totalBytes = total;
          if (started) hasTransferred = true;
          if (sendingTo case final target?) {
            activity = hasTransferred
                ? t.sendingTo(target)
                : connectionRoute.isNotEmpty
                ? t.waitingForRecipient(target)
                : t.connectingTo(target);
          }
        });
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if (Platform.isAndroid && now - lastSystemTransferUpdate >= 1000) {
        lastSystemTransferUpdate = now;
        final speed = transferRate?.bytesPerSecond;
        final status = cancelling
            ? t.cancelling
            : processingLocalContent
            ? contentProcessingLabel!
            : sendingTo != null
            ? activity ?? t.notificationSending
            : t.receiving('').trim();
        final details =
            !cancelling &&
                !processingLocalContent &&
                hasTransferred &&
                total > 0
            ? '${(value! * 100).floor()}%${speed != null ? '\u2003\u2003${_size(speed.round())}/s' : ''}'
            : '';
        unawaited(
          backgroundChannel
              .invokeMethod<void>('transfer', {
                'title': notificationTitle(
                  notificationContentName ?? t.transferNotificationTitle,
                ),
                'channel': t.transferNotificationTitle,
                'text': details.isEmpty ? status : details,
                'sourceType': sendingTo != null
                    ? deviceType
                    : notificationPeerType,
                'destinationType': sendingTo != null
                    ? notificationPeerType
                    : deviceType,
                'shortText': cancelling
                    ? t.cancelling
                    : processingLocalContent
                    ? contentProcessingLabel!
                    : t.connectingShort,
                'id': notificationTransferId,
                'cancel': t.cancel,
                'cancelling': cancelling,
                'progress':
                    !processingLocalContent && hasTransferred && value != null
                    ? (value * 100).floor()
                    : null,
              })
              .catchError((Object e) {
                debugPrint('Could not update transfer notification: $e');
              }),
        );
      }
    });
    if (DesktopPlatform.isDesktop) unawaited(_syncInitialWindowVisibility());
    if (Platform.isMacOS) {
      unawaited(
        _restoreMacKeepAwake()
            .catchError((Object e) {
              debugPrint('Could not restore background receiving: $e');
            })
            .whenComplete(_refreshBackgroundAvailability),
      );
    }
    _startNode();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasMonitoring = monitorPresence;
    final wasVisible = presenceVisible;
    presenceLifecycle = state;
    if (wasMonitoring != monitorPresence)
      presenceController.requestMonitoring(enabled: monitorPresence);
    foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      unawaited(_refreshBackgroundAvailability());
      unawaited(_showLegacyPairingNotice());
      incomingPrompt?.becameVisible();
      if (Platform.isAndroid ||
          Platform.isMacOS ||
          DesktopPlatform.isWindowsOrLinux) {
        unawaited(
          backgroundChannel
              .invokeMethod<void>('clearOffer')
              .catchError((Object _) {}),
        );
      }
    }
    if ((!wasVisible || foreground) &&
        shouldRefreshForVisibility(
          visible: presenceVisible,
          becameVisible: !wasVisible,
          refreshing: refreshingPresence,
        )) {
      unawaited(
        (!wasVisible
            ? presenceController.requestPeerProbes()
            : presenceController.readCurrentSnapshot()),
      );
    }
  }

  TransferJob _beginTransfer({
    String? target,
    String? contentName,
    String? peerType,
  }) {
    if (shuttingDown || updates.installing) throw StateError(t.transferBusy);
    ScaffoldMessenger.of(context).clearSnackBars();
    final job = node!.newTransferJob();
    activeTransfer = job;
    _setTransferring(true);
    cancelling = false;
    contentProcessing = null;
    connectionRoute = '';
    hasTransferred = false;
    sendingTo = target;
    notificationContentName = contentName;
    notificationPeerType = peerType;
    notificationTransferId = DateTime.now().microsecondsSinceEpoch.toString();
    transferProgress = null;
    transferredBytes = 0;
    totalBytes = 0;
    transferRate = TransferRate();
    transferClock = Stopwatch()..start();
    lastSystemTransferUpdate = 0;
    return job;
  }

  void _setNodeStatus(String status) =>
      _updateDesktopStatus('setNodeStatus', status);

  void _setTransferring(bool transferring) =>
      _updateDesktopStatus('setTransferring', transferring);

  void _updateDesktopStatus(String method, Object value) {
    if (!DesktopPlatform.isDesktop) return;
    unawaited(
      backgroundChannel.invokeMethod<void>(method, value).catchError((
        Object e,
      ) {
        debugPrint('Could not update menu status: $e');
      }),
    );
  }

  void _cancelTransfer() {
    setState(() => cancelling = true);
    final archive = folderJob;
    if (folderOperation) {
      if (archive != null) unawaited(archive.cancel());
      if (Platform.isAndroid) {
        unawaited(
          const MethodChannel('vela/files')
              .invokeMethod<void>('cancelFolder')
              .catchError((Object _) {}),
        );
      }
      return;
    }
    activeTransfer?.cancel();
    if (Platform.isAndroid) {
      unawaited(receivedStorage.cancelSave().catchError((Object _) {}));
    }
  }

  void _finishSystemTransfer(
    String? message, {
    String? path,
    String? name,
    String? url,
    String? previewTextPath,
    String? batchId,
    String? openLabel,
    bool received = false,
  }) {
    if (!Platform.isAndroid) return;
    unawaited(
      backgroundChannel
          .invokeMethod<void>(
            message != null ? 'finishTransfer' : 'clearTransfer',
            {
              'text': message,
              'channel': t.transferNotificationTitle,
              'path': path,
              'name': name,
              'url': url,
              'previewTextPath': previewTextPath,
              'batchId': batchId,
              'open': openLabel ?? t.open,
              'received': received,
              'title': received ? t.notificationReceivedTitle : null,
              'shortText': t.notificationReceivedShort,
            },
          )
          .catchError((Object e) {
            debugPrint('Could not finish transfer notification: $e');
          }),
    );
  }

  Future<void> _releaseDrop() async {
    final bookmarks = List<Uint8List>.of(dropBookmarks);
    dropBookmarks.clear();
    final files = List<String>.of(promisedDropFiles);
    promisedDropFiles.clear();
    for (final bookmark in bookmarks) {
      try {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
      } catch (e) {
        debugPrint('Could not release dropped file: $e');
      }
    }
    for (final path in files) {
      try {
        await File(path).delete();
      } catch (e) {
        debugPrint('Could not remove temporary dropped file: $e');
      }
    }
  }

  Future<void> _receiveDrop(DropDoneDetails details) async {
    if (shuttingDown || updates.installing) return;
    if (mounted) setState(() => dropHover = false);
    if (processingDrop ||
        contentOperationActive ||
        outgoingPairingUiActive ||
        !mounted) {
      return;
    }
    if (pendingShare != null || _failedSend != null) {
      _message(t.dropAlreadyPending, kind: NoticeKind.error);
      return;
    }
    if (details.files.isEmpty) return;
    if (details.files.any((item) => item is! DropItemFile)) {
      _message(t.dropFilesOnly, kind: NoticeKind.error);
      return;
    }
    if (details.files.length > 100) {
      _message(t.tooManyFiles, kind: NoticeKind.error);
      return;
    }
    processingDrop = true;
    try {
      for (final item in details.files) {
        final bookmark = item.extraAppleBookmark;
        if (bookmark != null && bookmark.isNotEmpty) {
          if (await DesktopDrop.instance.startAccessingSecurityScopedResource(
            bookmark: bookmark,
          )) {
            dropBookmarks.add(bookmark);
          }
        }
        if (item.fromPromise) promisedDropFiles.add(item.path);
        if (!await File(item.path).exists()) {
          throw StateError('Dropped file unavailable');
        }
      }
      if (!mounted ||
          pendingShare != null ||
          _failedSend != null ||
          contentOperationActive ||
          outgoingPairingUiActive) {
        await _releaseDrop();
        return;
      }
      setState(
        () => pendingShare = PendingShare(
          paths: details.files.map((item) => item.path).toList(),
          drop: true,
        ),
      );
    } catch (e) {
      debugPrint('Could not receive dropped files: $e');
      await _releaseDrop();
      if (mounted) _message(t.fileUnavailable, kind: NoticeKind.error);
    } finally {
      processingDrop = false;
    }
  }

  Future<void> _showPendingReceipt() async {
    try {
      final batchId = await shareChannel.invokeMethod<String>(
        'takeReceivedBatch',
      );
      final path = batchId == null
          ? await shareChannel.invokeMethod<String>('takeTextPreview')
          : null;
      if (!mounted || (batchId == null && path == null)) return;
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      historyStore.load(preferences);
      final text = path == null ? null : await File(path).readAsString();
      final record = path == null
          ? null
          : historyStore.records.value
                .where(
                  (item) =>
                      item.received &&
                      item.kind.isText &&
                      item.fileReference == path,
                )
                .firstOrNull;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (batchId != null) {
          _showHistory(batchId: batchId);
        } else if (text != null) {
          unawaited(
            _showTextContent(text, kind: record?.kind, sender: record?.peer),
          );
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    } catch (e) {
      debugPrint('Could not view received content: $e');
      if (mounted) _message(t.historyMissing, kind: NoticeKind.error);
    }
  }

  Future<void> _takePendingShare() async {
    if (!mounted || disposed || shuttingDown || pendingShare != null) return;
    try {
      final share = await shareChannel.invokeMapMethod<String, dynamic>('take');
      if (mounted && share != null) {
        setState(() => pendingShare = PendingShare.fromMap(share));
        if (!_composingText &&
            !contentOperationActive &&
            !outgoingPairingUiActive &&
            !awaitingOfferDecision) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } catch (e) {
      debugPrint('Could not read shared content: $e');
    }
  }

  Future<void> _startNode() {
    if (!mounted || shuttingDown) return Future.value();
    if (startup != null) return startup!;
    startupRetry?.cancel();
    final attempt = _startNodeAttempt();
    startup = attempt;
    return attempt.whenComplete(() {
      if (identical(startup, attempt)) startup = null;
    });
  }

  Future<bool> _backgroundReceivingEnabled() async {
    final setting = BackgroundReceiving.current;
    if (setting == null) return false;
    return setting.enabled(
      await SharedPreferences.getInstance(),
      widget.profile,
    );
  }

  Future<void> _syncInitialWindowVisibility() async {
    final revision = windowVisibilityRevision;
    try {
      final windowShown = await backgroundChannel.invokeMethod<bool>(
        'getWindowVisible',
      );
      if (!mounted ||
          windowVisibilityRevision != revision ||
          windowShown != false) {
        return;
      }
      final wasMonitoring = monitorPresence;
      foreground = false;
      presenceWindowHidden = true;
      if (wasMonitoring != monitorPresence)
        presenceController.requestMonitoring(enabled: monitorPresence);
    } catch (e) {
      debugPrint('Could not read window visibility: $e');
    }
  }

  Future<void> _restoreMacKeepAwake() async {
    final enabled = await _backgroundReceivingEnabled();
    if (!mounted || shuttingDown) return;
    await BackgroundReceiving.macKeepAwake.setEnabled(enabled);
  }

  Future<void> _retryStartup() async {
    if (!mounted || shuttingDown || node != null) return;
    try {
      if (!await _backgroundReceivingEnabled() ||
          !mounted ||
          shuttingDown ||
          node != null) {
        return;
      }
      if (changingRelay) {
        _scheduleStartupRetry();
        return;
      }
      await _startNode();
    } catch (e) {
      debugPrint('Could not retry initialization: $e');
    }
  }

  void _scheduleStartupRetry() {
    if (!mounted ||
        shuttingDown ||
        node != null ||
        startupRetry?.isActive == true) {
      return;
    }
    final seconds = 1 << (startupFailures.clamp(1, 6) - 1);
    startupRetry = Timer(Duration(seconds: seconds), () {
      unawaited(_retryStartup());
    });
  }

  Future<void> _retryFromUI() async {
    if (!mounted || shuttingDown || node != null) return;
    if (error != null) setState(() => error = null);
    final pending = startup;
    if (pending != null) {
      await pending;
      if (identical(startup, pending)) startup = null;
    }
    if (mounted && !shuttingDown && node == null) await _startNode();
  }

  Future<void> _startNodeAttempt() async {
    _setNodeStatus('starting');
    if (Platform.isAndroid) {
      unawaited(
        backgroundChannel
            .invokeMethod<void>('nodeStarting')
            .catchError((Object _) {}),
      );
    }
    _recordDiagnostic('starting');
    try {
      final ready = await runtime.start();
      if (ready == null ||
          !mounted ||
          shuttingDown ||
          !identical(node, ready.node))
        return;
      final n = ready.node;
      final p = ready.preferences;
      historyStore.load(p);
      final storedView = p.getString('device_view_${widget.profile}');
      _recordDiagnostic('startup_complete_begin');
      setState(() {
        error = null;
        prefs = p;
        deviceName = ready.deviceName;
        systemDeviceName = ready.systemDeviceName;
        deviceType = ready.deviceType;
        deviceView = storedView == 'graph' ? 'graph' : 'list';
      });
      presenceController.attach(pairedDevices!);
      _recordDiagnostic('startup_complete_done');
      _recordDiagnostic('ready');
      startupFailures = 0;
      _setNodeStatus('ready');
      if (Platform.isAndroid) {
        unawaited(
          backgroundChannel
              .invokeMethod<void>('nodeReady', {'message': t.backgroundReady})
              .catchError((Object _) {})
              .whenComplete(_refreshBackgroundAvailability),
        );
      } else {
        unawaited(_refreshBackgroundAvailability());
      }
      if (ready.legacyStateDetected &&
          !(p.getBool('legacy_pairing_notice_${widget.profile}') ?? false)) {
        legacyNoticePending = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_showLegacyPairingNotice()),
        );
      }
      if (Platform.isAndroid) {
        unawaited(
          backgroundChannel
              .invokeMethod<void>('clearTransfer')
              .catchError((Object _) {}),
        );
        unawaited(
          backgroundChannel
              .invokeMethod<void>('clearOffer')
              .catchError((Object _) {}),
        );
        if (p.getBool('background_receive_${widget.profile}') ?? false) {
          unawaited(
            backgroundChannel
                .invokeMethod<bool>('resume', {'message': t.backgroundReady})
                .catchError((Object e) {
                  debugPrint('Could not resume background receiving: $e');
                  return false;
                })
                .whenComplete(_refreshBackgroundAvailability),
          );
        }
      }
      unawaited(n.waitUntilOnline());
      unawaited(_listenForIncomingRequests(n));
      try {
        await presenceController.syncMonitoring(enabled: monitorPresence);
      } catch (e) {
        debugPrint('Could not update device monitoring: $e');
        presenceController.requestMonitoring(enabled: monitorPresence);
      }
      unawaited(presenceController.requestPeerProbes());
    } catch (e) {
      if (mounted && error != e.toString()) _showStartupFailure(e);
      if (runtime.startupCleanupComplete &&
          mounted &&
          !shuttingDown &&
          node == null) {
        startupFailures++;
        try {
          if (await _backgroundReceivingEnabled()) _scheduleStartupRetry();
        } catch (e) {
          debugPrint('Could not check background receiving: $e');
        }
      }
    }
  }

  void _showStartupFailure(Object error) {
    _recordDiagnostic('startupFailed');
    debugPrint('Device initialization failed: $error');
    _setNodeStatus('failed');
    if (Platform.isAndroid) {
      unawaited(
        backgroundChannel
            .invokeMethod<void>('nodeFailed')
            .catchError((Object _) {}),
      );
    }
    if (mounted) setState(() => this.error = error.toString());
  }

  void _presenceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showLegacyPairingNotice() async {
    if (!legacyNoticePending ||
        legacyNoticeShowing ||
        !mounted ||
        !foreground ||
        prefs == null) {
      return;
    }
    legacyNoticeShowing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(t.devices),
          content: Text(t.legacyPairingsNotice),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.close),
            ),
          ],
        ),
      );
      if (mounted) {
        await prefs!.setBool('legacy_pairing_notice_${widget.profile}', true);
        legacyNoticePending = false;
      }
    } finally {
      legacyNoticeShowing = false;
    }
  }

  Future<void> _handlePair(
    VelaNode source,
    IncomingRequest offer,
    IncomingRequestInfo info,
  ) async {
    final devices = pairedDevices;
    if (devices == null ||
        !mounted ||
        !identical(devices.node, source) ||
        shuttingDown ||
        updates.installing) {
      await offer.decline();
      return;
    }
    final id = info.sender;
    final device = info.pairing!;
    try {
      final added = await pairings.receive(
        devices,
        offer,
        id,
        device,
        confirm: (closed) => showPeerConfirmation(
          context,
          peerClosed: closed,
          builder: (context) => AlertDialog(
            constraints: const BoxConstraints(maxWidth: 420),
            scrollable: true,
            title: Text(t.pairRequest),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(t.confirmOwnDevice),
                const SizedBox(height: 8),
                SelectableText(
                  t.deviceCodeShort(shortDeviceCode(id)),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.reject),
              ),
              FilledButton(
                key: const ValueKey('accept-pair'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(t.add),
              ),
            ],
          ),
        ),
      );
      if (added && mounted) {
        unawaited(presenceController.readCurrentSnapshot());
        _message(t.addedPeer(device.name), kind: NoticeKind.success);
      }
    } catch (e) {
      debugPrint('Could not send pairing reply: $e');
      if (mounted) _message(t.pairFailed, kind: NoticeKind.error);
    }
  }

  Future<void> _listenForIncomingRequests(VelaNode source) async {
    final offers =
        StreamController<({IncomingRequest offer, IncomingRequestInfo info})>();
    var queued = 0;
    unawaited(() async {
      try {
        while (!disposed && identical(node, source)) {
          final offer = await source.nextRequest();
          if (!identical(node, source) ||
              changingRelay ||
              shuttingDown ||
              updates.installing) {
            unawaited(offer.decline());
            continue;
          }
          final info = offer.info();
          if (info.pairing != null) {
            unawaited(_handlePair(source, offer, info));
          } else if (queued < 16) {
            queued++;
            incomingOffersPending++;
            offers.add((offer: offer, info: info));
          } else {
            unawaited(offer.decline());
          }
        }
      } catch (e) {
        debugPrint('Offer listener stopped: $e');
      } finally {
        await offers.close();
      }
    }());

    await for (final request in offers.stream) {
      queued--;
      try {
        if (mounted && !disposed && identical(node, source)) {
          await _receiveOffer(source, request.offer, request.info);
        }
      } finally {
        incomingOffersPending--;
      }
    }
  }

  Future<void> _receiveOffer(
    VelaNode source,
    IncomingRequest offer,
    IncomingRequestInfo info,
  ) async {
    TransferJob? job;
    IncomingOfferPrompt? prompt;
    var receivedFromPeer = false;
    void releaseJob() {
      final ownedJob = job;
      if (ownedJob == null) return;
      job = null;
      if (!receivedFromPeer) ownedJob.cancel();
      if (!identical(activeTransfer, ownedJob)) return;
      activeTransfer = null;
      contentProcessing = null;
      if (mounted) {
        setState(() {
          contentOperationActive = false;
          activity = null;
        });
      }
      _setTransferring(false);
    }

    bool currentNode() => mounted && !disposed && identical(node, source);
    try {
      while (contentOperationActive && currentNode()) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (!currentNode()) return;
      final devices = pairedDevices!;
      final sender = info.sender;
      final pairingRevision = devices.pairingRevisionFor(sender);
      bool stillAuthorized() =>
          identical(pairedDevices, devices) &&
          devices.state.containsDevice(sender) &&
          devices.isCurrentPairingRevision(sender, pairingRevision);
      if (!stillAuthorized()) {
        await offer.decline();
        return;
      }
      unawaited(presenceController.readCurrentSnapshot());
      String senderName() => devices.state.containsDevice(sender)
          ? devices.state.displayName(sender)
          : t.device;
      final kind = TransferKind.fromWire(info.kind);
      final contentName = switch (kind) {
        TransferKind.typedText => t.textContent,
        TransferKind.text => t.clipboardText,
        TransferKind.image => t.clipboardImage,
        TransferKind.batch => t.filesCount(info.files.length),
        _ => info.name,
      };
      final autoAccept =
          prefs?.getBool('auto_accept_${widget.profile}') ?? false;
      final appForeground = Platform.isAndroid || DesktopPlatform.isDesktop
          ? await backgroundChannel.invokeMethod<bool>('isVisible') ??
                foreground
          : true;
      if (!mounted || !identical(node, source)) return;
      prompt = IncomingOfferPrompt(
        backgroundChannel,
        notificationId: !appForeground && !autoAccept && Platform.isAndroid
            ? DateTime.now().microsecondsSinceEpoch.toString()
            : null,
      );
      incomingPrompt = prompt;
      final PeerDecision decision;
      try {
        decision = await prompt.confirm(
          context,
          offer: offer,
          senderName: senderName,
          contentName: contentName,
          batchFiles: kind == TransferKind.batch ? info.files : const [],
          size: _size(info.size.toInt()),
          inBackground: !appForeground,
          autoAccept: autoAccept,
          focusWindow:
              Platform.isMacOS &&
              (prefs?.getBool('mac_focus_on_offer_${widget.profile}') ?? true),
        );
      } finally {
        if (identical(incomingPrompt, prompt)) incomingPrompt = null;
      }
      if (!mounted || !identical(node, source)) return;
      if (decision == PeerDecision.connectionClosed) {
        if (prompt.openedDialog) _message(t.transferCancelled);
        return;
      }
      if (decision == PeerDecision.declined) {
        await offer.decline();
        return;
      }
      while (contentOperationActive && currentNode()) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (!currentNode()) return;
      if (!stillAuthorized()) {
        await offer.decline();
        return;
      }
      final receivingJob = _beginTransfer(
        contentName: contentName,
        peerType: peerTypes[sender],
      );
      final batchId = kind == TransferKind.batch
          ? notificationTransferId
          : null;
      job = receivingJob;
      setState(() {
        contentOperationActive = true;
        activity = t.receiving(contentName);
        receivedPath = null;
      });
      final received = await receiveAcceptedContent(
        offer: offer,
        job: receivingJob,
        profile: widget.profile,
        kind: kind,
        offeredName: info.name,
        contentName: contentName,
        senderName: senderName,
        batchId: batchId,
        history: historyStore,
        storage: receivedStorage,
        stillAuthorized: stillAuthorized,
        onTransportComplete: (savingFromStaging) {
          receivedFromPeer = true;
          if (savingFromStaging && mounted) {
            setState(() {
              contentProcessing = ContentProcessing.savingReceived;
              activity = t.savingFile;
              transferProgress = null;
            });
          }
        },
        onSaved: () => contentProcessing = null,
        isCancelled: () => cancelling,
      );
      if (received == null) return;
      releaseJob();
      _recordDiagnostic('received', sender);
      if (mounted) {
        final message = _showReceivedContent(
          kind,
          info.name,
          received.files,
          received.content,
          sender: senderName(),
          batchId: batchId,
          savedPrivately: received.savedPrivately,
        );
        await prompt.completed(message, foreground: foreground);
      }
    } catch (error) {
      if (!identical(node, source) || disposed || !mounted) return;
      debugPrint('Receive failed: $error');
      final cancelled =
          cancelling ||
          classifyTransferFailure(error) == TransferFailure.cancelled ||
          (error is PlatformException && error.code == 'cancelled');
      final message = cancelled
          ? t.transferCancelled
          : transferErrorMessage(error, t);
      if (job != null) {
        releaseJob();
        _recordDiagnostic(
          cancelled ? 'receiveCancelled' : 'receiveFailed',
          info.sender,
        );
        _finishSystemTransfer(message);
      }
      _message(message, kind: cancelled ? NoticeKind.info : NoticeKind.error);
      await Future<void>.delayed(const Duration(seconds: 1));
    } finally {
      releaseJob();
      await prompt?.clearNotification();
    }
  }

  String _showReceivedContent(
    TransferKind kind,
    String offeredName,
    List<SavedReceivedFile> files,
    ReceivedContent content, {
    required String sender,
    required String? batchId,
    required bool savedPrivately,
  }) {
    final first = files.first;
    final message = !content.historySaved
        ? t.historySaveFailed
        : savedPrivately && content.clipboardFailed
        ? '${t.savedPrivately} ${t.writeClipboardFailed}'
        : savedPrivately
        ? t.savedPrivately
        : content.clipboardFailed
        ? t.writeClipboardFailed
        : switch (kind) {
            TransferKind.typedText => t.textReceived,
            TransferKind.batch => t.filesReceived(files.length),
            TransferKind.file => t.received(first.name),
            _ => t.clipboardReceived,
          };
    final openable =
        kind == TransferKind.file ||
        kind == TransferKind.clipboardFile ||
        kind == TransferKind.image;
    final openLabel = batchId != null
        ? t.viewReceivedBatch
        : content.link != null
        ? t.openLink
        : content.text != null
        ? t.viewText
        : t.openFile;
    final historyKind = kind.historyKind(offeredName);
    final restoreFolder = historyKind.canRestoreFolder;
    final folder = !kind.isFile || savedPrivately || restoreFolder
        ? null
        : Platform.isAndroid
        ? (first.folderLabel ?? t.downloadsFolder)
        : File(first.reference).parent.path;
    setState(() {
      activity = message;
      receivedPath = openable ? first.reference : null;
    });
    _finishSystemTransfer(
      message,
      path: openable ? first.reference : null,
      name: first.name,
      url: content.link,
      previewTextPath: content.text != null && content.link == null
          ? first.reference
          : null,
      batchId: content.historySaved ? batchId : null,
      openLabel: openLabel,
      received: true,
    );
    _message(
      message,
      detail: folder == null ? null : t.receivedSavedTo(folder),
      kind: content.historySaved && !savedPrivately && !content.clipboardFailed
          ? NoticeKind.success
          : NoticeKind.info,
      actionLabel: restoreFolder ? t.restoreFolder : openLabel,
      onAction: restoreFolder
          ? () => _restoreFolder(first.reference)
          : batchId != null
          ? () => _showHistory(batchId: batchId)
          : content.link != null
          ? () => _openLink(content.link!)
          : content.text != null
          ? () => _showTextContent(
              content.text!,
              kind: historyKind,
              sender: sender,
            )
          : () => _openReceived(first.reference),
    );
    return message;
  }

  void _invalidatePeerMembership(PeerState updated, Set<String> changed) {
    presenceController.membershipChanging(changed);
    for (final id in changed) {
      if (!updated.containsDevice(id)) pairings.cancel(id);
    }
  }

  void _publishPeerState(PeerState state, Set<String> changed) {
    presenceController.membershipPublished(state, changed);
    if (mounted)
      setState(
        () => selectedPeers.removeWhere((id) => !state.containsDevice(id)),
      );
  }

  void _recordDiagnostic(String kind, [String? peer]) {
    if (!widget.diagnosticsEnabled) return;
    final name = peer == null || !peers.containsKey(peer)
        ? null
        : peerState.displayName(peer);
    final event = _DiagnosticEntry(
      kind,
      diagnosticsMonotonicMs().toInt(),
      peer,
      name,
    );
    diagnosticEvents.add(event);
    if (diagnosticEvents.length > 2000) diagnosticEvents.removeAt(0);
    debugPrint(
      'VelaDiag epoch_ms=${event.time.millisecondsSinceEpoch} mono_ms=${event.monotonicMs} event=$kind${peer == null ? '' : ' peer=$peer'}',
    );
  }

  Future<void> _removeUnpaired(
    VelaNode source,
    String id,
    Object pairingRevision,
  ) => pairings.serialize(id, () async {
    final devices = pairedDevices;
    if (!mounted || devices == null || !identical(devices.node, source)) return;
    final name = devices.state.displayName(id);
    try {
      final removed = await devices.removeIfUnpaired(
        id,
        pairingRevision,
        pairingActive: () => pairings.isActiveFor(id),
      );
      if (mounted && removed) _message(t.peerUnpaired(name));
    } catch (error) {
      debugPrint('Could not update unpaired device: $error');
    }
  });

  Future<void> _addDevice({String initialCode = ''}) async {
    if (shuttingDown || updates.installing) return;
    if (outgoingPairingUiActive || contentOperationActive || changingRelay) {
      return;
    }
    final id = await showDialog<String>(
      context: context,
      builder: (_) => AddDeviceDialog(initialCode: initialCode),
    );
    if (id == null || node == null || changingRelay || !mounted) return;
    if (id == node!.id()) {
      _message(
        t.cannotAddSelf,
        kind: NoticeKind.error,
        actionLabel: t.retry,
        onAction: () => _addDevice(initialCode: id),
      );
      return;
    }
    if (pairings.isActiveFor(id)) {
      _message(t.pairConflict, kind: NoticeKind.error);
      return;
    }
    final devices = pairedDevices;
    if (devices == null || shuttingDown || updates.installing) return;
    setState(() => activePairingPeer = id);
    try {
      final peer = await pairings.request(devices, id);
      if (peer != null && mounted) {
        _message(t.addedPeer(peer.name), kind: NoticeKind.success);
      }
    } catch (e) {
      debugPrint('Pairing failed: $e');
      if (mounted) {
        final declined =
            classifyTransferFailure(e) == TransferFailure.pairingDeclined;
        _message(
          declined ? t.pairDeclined : t.pairFailed,
          kind: NoticeKind.error,
          actionLabel: declined ? null : t.retry,
          onAction: declined ? null : () => _addDevice(initialCode: id),
        );
      }
    } finally {
      if (mounted) {
        setState(() => activePairingPeer = null);
        unawaited(presenceController.readCurrentSnapshot());
      }
    }
  }

  void _cancelPairing() {
    final id = activePairingPeer;
    if (id == null) return;
    pairings.cancelOutgoing(id);
  }

  Future<void> _confirmAndRemovePeer(String id) async {
    if (!peers.containsKey(id)) return;
    final name = peerState.displayName(id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t.removeDeviceQuestion),
        content: Text(t.removeDeviceBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await pairedDevices!.remove(id);
    _message(t.deviceRemoved);
  }

  void _togglePeerSelection(String id) {
    setState(() {
      selectingPeers = true;
      if (!selectedPeers.add(id)) selectedPeers.remove(id);
    });
  }

  Future<void> _removeSelectedPeers() async {
    final ids = selectedPeers.where(peers.containsKey).toList();
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t.removeDevicesQuestion(ids.length)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.removeDevicesBody),
            const SizedBox(height: 12),
            for (final id in ids) Text(peerState.displayName(id)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await pairedDevices!.update((state) {
        for (final id in ids) {
          state = state.remove(id);
        }
        return state;
      });
      if (mounted) {
        setState(() {
          selectedPeers.clear();
          selectingPeers = false;
        });
        _message(t.deviceRemoved);
      }
    } catch (e) {
      debugPrint('Could not remove devices: $e');
      if (mounted) _message(t.storageFailed, kind: NoticeKind.error);
    }
  }

  String _presenceLabel(String id) => visiblePresenceChecks.contains(id)
      ? t.checking
      : switch (presence[id]) {
          PeerPresence.reachable => t.reachable,
          PeerPresence.unavailable => t.unreachable,
          null => t.unknown,
        };

  Widget _presenceIcon(String id) {
    final checking = visiblePresenceChecks.contains(id);
    final value = checking ? null : presence[id];
    final label = _presenceLabel(id);
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Icon(
          switch (value) {
            PeerPresence.reachable => Icons.check_circle_rounded,
            PeerPresence.unavailable => Icons.error_outline_rounded,
            null => Icons.circle_outlined,
          },
          key: checking ? const ValueKey('device-presence-check') : null,
          size: 12,
          color: switch (value) {
            PeerPresence.reachable => Colors.green,
            PeerPresence.unavailable => colors.error,
            null => colors.onSurfaceVariant,
          },
        ),
      ),
    );
  }

  IconData _iconForType(String? type) => switch (type) {
    'mobile' => Icons.phone_android_rounded,
    'tablet' => Icons.tablet_android_rounded,
    'desktop' => Icons.computer_rounded,
    _ => Icons.devices_other_rounded,
  };
  IconData _deviceIcon(String id) => _iconForType(peerTypes[id]);

  Future<void> _toggleDeviceView(bool showingGraph) async {
    final next = showingGraph ? 'list' : 'graph';
    setState(() => deviceView = next);
    try {
      if (!await prefs!.setString('device_view_${widget.profile}', next)) {
        throw StateError('Could not save view');
      }
    } catch (_) {
      if (mounted) _message(t.storageFailed, kind: NoticeKind.error);
    }
  }

  String _sendDeviceName(String id) {
    final name = peerState.displayName(id);
    final code = peerState.distinguishingCode(id);
    return code == null ? name : '$name · $code';
  }

  Future<String?> _choosePeer(
    String contentName, {
    PreparedTransfer? prepared,
    PendingShare? share,
    List<String> sharedNames = const [],
  }) async {
    if (peers.isEmpty) return null;
    final largeText = HomeSendButton.usesLargeLabels(context);
    final summary = t.pendingContent(contentName);
    final textPreview =
        prepared?.textPreview ?? prepared?.share?.text ?? share?.text;
    final imagePreview = prepared?.kind == TransferKind.image;
    final paths = prepared?.paths ?? const <String>[];
    final fileNames = paths.length > 1
        ? paths.map((path) => File(path).uri.pathSegments.last)
        : sharedNames;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListenableBuilder(
          listenable: presenceController,
          builder: (context, _) => ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              t.chooseDevice,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: t.cancel,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (textPreview != null ||
                  imagePreview ||
                  fileNames.isNotEmpty ||
                  contentName.length > 40)
                ExpansionTile(
                  title: Text(t.reviewSendContent),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 24),
                  childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (textPreview != null)
                      Text(_textPreview(textPreview, 240))
                    else if (imagePreview)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: Image.file(
                          File(paths.single),
                          cacheWidth: 480,
                          semanticLabel: t.clipboardImage,
                          errorBuilder: (_, _, _) => Text(t.fileUnavailable),
                        ),
                      )
                    else if (fileNames.isEmpty)
                      Text(contentName)
                    else
                      for (final name in fileNames) Text(name),
                  ],
                ),
              for (final peer in peers.keys)
                ListTile(
                  key: ValueKey('send-recipient-$peer'),
                  leading: largeText ? null : Icon(_deviceIcon(peer)),
                  title: Text(t.sendToDevice(peerState.displayName(peer))),
                  subtitle: Text(switch (peerState.distinguishingCode(peer)) {
                    final code? =>
                      '${t.deviceCodeShort(code)}\n${_presenceLabel(peer)}',
                    null => _presenceLabel(peer),
                  }),
                  trailing: largeText ? null : const Icon(Icons.send_rounded),
                  onTap: () => Navigator.pop(context, peer),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseAndSend({
    bool clipboard = false,
    bool media = false,
  }) async {
    if (_sendUnavailable) return;
    if (media) {
      try {
        final uris =
            await const MethodChannel('vela/files')
                .invokeListMethod<String>('pickMedia') ??
            [];
        if (!mounted || uris.isEmpty) return;
        if (uris.length > 100) {
          _message(t.tooManyFiles, kind: NoticeKind.error);
          return;
        }
        final share = PendingShare(uris: uris);
        await _chooseAndSendShare(share);
      } catch (e) {
        debugPrint('Media selection failed: $e');
        if (mounted) _message(t.mediaPickFailed, kind: NoticeKind.error);
      }
    } else {
      await _prepareAndSend(
        clipboard ? _prepareClipboard : _pickFiles,
        clipboard: clipboard,
      );
    }
  }

  Future<void> _composeAndSendText() async {
    _composingText = true;
    final ({String peer, String text})? selection;
    try {
      selection = await showDialog<({String peer, String text})>(
        context: context,
        builder: (_) => _TextComposeDialog(
          devices: {
            for (final id in peers.keys)
              id: (name: _sendDeviceName(id), status: _presenceLabel(id)),
          },
          isPaired: (id) => peers.containsKey(id),
        ),
      );
    } finally {
      _composingText = false;
    }
    if (selection != null && mounted && peers.containsKey(selection.peer)) {
      await _sendShare(
        selection.peer,
        PendingShare(text: selection.text, typed: true),
      );
    }
  }

  Future<void> _chooseAndSendFolder() async {
    if (_sendUnavailable) return;
    String? source;
    try {
      source = Platform.isAndroid
          ? await const MethodChannel('vela/files')
                .invokeMethod<String>('pickFolder')
          : await FilePicker.getDirectoryPath();
    } catch (e) {
      debugPrint('Could not choose folder: $e');
      if (mounted) _message(t.folderPrepareFailed, kind: NoticeKind.error);
      return;
    }
    if (source == null || !mounted) return;
    final folderName = Platform.isAndroid
        ? (await _sharedItemNames([source])).firstOrNull ?? t.folder
        : Directory(source).uri.pathSegments
                  .where((part) => part.isNotEmpty)
                  .lastOrNull ??
              t.folder;
    if (!mounted) return;
    final id = await _choosePeer(folderName);
    if (!mounted ||
        id == null ||
        !peers.containsKey(id) ||
        shuttingDown ||
        updates.installing) {
      return;
    }
    if (_sendUnavailable) {
      _message(t.transferBusy, kind: NoticeKind.error);
      return;
    }
    String? archive;
    String? stagedFolder;
    var preparing = true;
    try {
      setState(() {
        contentOperationActive = true;
        cancelling = false;
        contentProcessing = ContentProcessing.preparingFolder;
        activity = t.preparingFolder;
      });
      folderOperation = true;
      _setTransferring(true);
      if (Platform.isAndroid) {
        final staged = await const MethodChannel('vela/files')
            .invokeMapMethod<String, String>('stageFolder', {'tree': source});
        if (staged == null) throw StateError('Could not read selected folder');
        stagedFolder = staged['temporary'];
        source = staged['path'];
        if (source == null || cancelling) {
          throw StateError('folder operation cancelled');
        }
      }
      final job = await newFolderArchiveJob();
      folderJob = job;
      if (!mounted || shuttingDown || cancelling) {
        await job.cancel();
        if (mounted && cancelling) _message(t.transferCancelled);
        return;
      }
      final temporary = await getTemporaryDirectory();
      archive = await job.pack(source: source, outputDir: temporary.path);
      folderJob = null;
      folderOperation = false;
      if (mounted && cancelling) {
        _message(t.transferCancelled);
        return;
      }
      if (!mounted || cancelling || node == null) return;
      setState(() {
        contentOperationActive = false;
        contentProcessing = null;
        activity = null;
      });
      preparing = false;
      _setTransferring(false);
      final path = archive;
      archive = null;
      await _send(
        id,
        _sendDeviceName(id),
        _createSendSession(
          PreparedTransfer(
            paths: [path],
            ownedTemporaryPaths: [path],
            displayName: folderName,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Could not prepare folder: $e');
      if (mounted) {
        _message(
          cancelling ? t.transferCancelled : t.folderPrepareFailed,
          kind: cancelling ? NoticeKind.info : NoticeKind.error,
        );
      }
    } finally {
      folderJob = null;
      folderOperation = false;
      if (archive != null) {
        try {
          await File(archive).delete();
        } catch (e) {
          debugPrint('Could not remove folder archive: $e');
        }
      }
      if (stagedFolder != null) {
        try {
          await Directory(stagedFolder).delete(recursive: true);
        } catch (e) {
          debugPrint('Could not remove temporary folder: $e');
        }
      }
      if (preparing) {
        if (mounted) {
          setState(() {
            contentOperationActive = false;
            contentProcessing = null;
            activity = null;
          });
        }
        _setTransferring(false);
      }
    }
  }

  Future<void> _restoreFolder(String archive) async {
    if (contentOperationActive || shuttingDown || updates.installing) {
      _message(t.transferBusy, kind: NoticeKind.error);
      return;
    }
    String? tree;
    if (Platform.isAndroid) {
      try {
        tree = await const MethodChannel('vela/files')
            .invokeMethod<String>('pickFolder', {'write': true});
      } catch (e) {
        debugPrint('Could not choose destination: $e');
        if (mounted) _message(t.folderRestoreFailed, kind: NoticeKind.error);
        return;
      }
      if (tree == null || !mounted) return;
    }
    if (shuttingDown || updates.installing) return;
    String? stagedArchive;
    Directory? restoredTemp;
    try {
      setState(() {
        contentOperationActive = true;
        cancelling = false;
        contentProcessing = ContentProcessing.restoringFolder;
        activity = t.restoringFolder;
      });
      folderOperation = true;
      _setTransferring(true);
      var source = archive;
      var outputDir = File(archive).parent.path;
      if (Platform.isAndroid) {
        final staged = await const MethodChannel('vela/files')
            .invokeMapMethod<String, String>('stageFolderArchive', {
              'path': archive,
            });
        if (staged == null ||
            staged['path'] == null ||
            staged['temporary'] == null) {
          throw StateError('Could not read archive');
        }
        stagedArchive = staged['temporary'];
        source = staged['path']!;
        restoredTemp = await (await getTemporaryDirectory()).createTemp(
          'vela-restore-',
        );
        outputDir = restoredTemp.path;
        if (cancelling) throw StateError('folder operation cancelled');
      }
      final job = await newFolderArchiveJob();
      folderJob = job;
      if (!mounted || shuttingDown || cancelling) {
        await job.cancel();
        if (mounted && cancelling) _message(t.transferCancelled);
        return;
      }
      final restored = await job.restore(archive: source, outputDir: outputDir);
      folderJob = null;
      if (cancelling) throw StateError('folder operation cancelled');
      final path = Platform.isAndroid
          ? await const MethodChannel('vela/files').invokeMethod<String>(
              'saveFolder',
              {'tree': tree, 'path': restored},
            )
          : restored;
      if (path == null) throw StateError('Could not save folder');
      if (mounted) {
        _message(
          t.folderRestored,
          kind: NoticeKind.success,
          actionLabel: t.open,
          onAction: () => _openReceived(path),
        );
      }
    } catch (e) {
      debugPrint('Could not restore folder: $e');
      if (mounted) {
        _message(
          cancelling ? t.transferCancelled : t.folderRestoreFailed,
          kind: cancelling ? NoticeKind.info : NoticeKind.error,
        );
      }
    } finally {
      if (stagedArchive != null) {
        try {
          await Directory(stagedArchive).delete(recursive: true);
        } catch (e) {
          debugPrint('Could not remove temporary archive: $e');
        }
      }
      if (restoredTemp != null) {
        try {
          await restoredTemp.delete(recursive: true);
        } catch (e) {
          debugPrint('Could not remove temporary folder: $e');
        }
      }
      folderJob = null;
      folderOperation = false;
      if (mounted) {
        setState(() {
          contentOperationActive = false;
          contentProcessing = null;
          activity = null;
        });
      }
      _setTransferring(false);
    }
  }

  Future<String?> _editName(String title, String current, {String? hint}) =>
      showDialog<String>(
        context: context,
        builder: (_) => NameDialog(title: title, current: current, hint: hint),
      );

  Future<void> _showDeviceDetails(String id) async {
    if (!peers.containsKey(id)) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => SafeArea(
        child: ListTileTheme(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          minLeadingWidth: 24,
          horizontalTitleGap: 16,
          child: ListenableBuilder(
            listenable: presenceController,
            builder: (context, _) => ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: Icon(_deviceIcon(id)),
                  title: Text(peerState.displayName(id)),
                  subtitle: Semantics(
                    liveRegion: true,
                    child: Text(_presenceLabel(id)),
                  ),
                  trailing: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(child: _presenceIcon(id)),
                  ),
                ),
                if (peers.containsKey(id) &&
                    presence[id] != PeerPresence.reachable &&
                    !visiblePresenceChecks.contains(id))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.deviceRecheckHint),
                        TextButton.icon(
                          onPressed: () => presenceController.requestPeerProbes(
                            userInitiated: true,
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(t.refreshDevices),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.fingerprint_rounded),
                  title: Text(t.deviceCode),
                  subtitle: Text(
                    shortDeviceCode(id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      tooltip: t.copyDeviceCode,
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () => Navigator.pop(context, 'copy'),
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(t.renameDevice),
                  subtitle: Text(t.deviceAliasHint),
                  onTap: () => Navigator.pop(context, 'rename'),
                ),
                if (peers[id] case final original?
                    when peerState.aliases.containsKey(id))
                  ListTile(
                    leading: const Icon(Icons.restore_rounded),
                    title: Text(t.useDeviceName),
                    subtitle: Text(original),
                    onTap: () => Navigator.pop(context, 'reset'),
                  ),
                ListTile(
                  leading: const Icon(Icons.link_off_rounded),
                  title: Text(t.removeDevice),
                  onTap: () => Navigator.pop(context, 'remove'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || !peers.containsKey(id)) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: id));
      if (mounted) _message(t.deviceCodeCopied, kind: NoticeKind.success);
      return;
    }
    if (action == 'remove') {
      await _confirmAndRemovePeer(id);
      return;
    }
    if (action == 'reset') {
      await pairedDevices!.setAlias(id, null);
      return;
    }
    if (action == 'rename') {
      final name = await _editName(
        t.renameDevice,
        peerState.displayName(id),
        hint: t.deviceAliasHint,
      );
      if (name != null && mounted) {
        await pairedDevices!.setAlias(id, name);
      }
    }
  }

  Future<DiagnosticsSnapshot> _diagnosticsSnapshot() async {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final currentNode = node;
    final entries = <(int, DateTime, String)>[];
    for (final event in diagnosticEvents) {
      final peerName =
          event.peerName ??
          (event.peer != null && peers.containsKey(event.peer)
              ? peerState.displayName(event.peer!)
              : t.device);
      final label = switch (event.kind) {
        'starting' => chinese ? '应用启动中' : 'App starting',
        'ready' => chinese ? '应用已就绪' : 'App ready',
        'startupFailed' => chinese ? '应用启动失败' : 'App failed to start',
        'networkChanged' =>
          chinese ? '网络已变化，正在检查设备' : 'Network changed; checking devices',
        'systemWake' =>
          chinese ? '恢复运行，正在检查设备' : 'App resumed; checking devices',
        'manualRefresh' => chinese ? '正在刷新设备状态' : 'Refreshing device status',
        'online' => chinese ? '$peerName 已连接' : '$peerName connected',
        'offline' => chinese ? '$peerName 暂时无法连接' : '$peerName is unavailable',
        'sent' => chinese ? '$peerName：发送完成' : '$peerName: sent',
        'sendFailed' => chinese ? '$peerName：发送失败' : '$peerName: send failed',
        'sendCancelled' =>
          chinese ? '$peerName：发送已取消' : '$peerName: send cancelled',
        'received' => chinese ? '$peerName：接收完成' : '$peerName: received',
        'receiveFailed' =>
          chinese ? '$peerName：接收失败' : '$peerName: receive failed',
        'receiveCancelled' =>
          chinese ? '$peerName：接收已取消' : '$peerName: receive cancelled',
        _ => null,
      };
      if (label != null) entries.add((event.monotonicMs, event.time, label));
    }
    if (currentNode != null) {
      entries.addAll(
        describeConnectionEvents(currentNode.diagnosticsEvents(), {
          for (final id in peers.keys) id: peerState.displayName(id),
        }, chinese: chinese),
      );
    }
    entries.sort((a, b) => a.$1.compareTo(b.$1));
    final recent = entries.length > 2000
        ? entries.sublist(entries.length - 2000)
        : entries;
    return DiagnosticsSnapshot(
      nodeReady: currentNode != null,
      peerCount: peers.length,
      reachableCount: peers.keys
          .where((id) => presence[id] == PeerPresence.reachable)
          .length,
      relayCount: currentNode?.diagnosticsTotalRelayCount() ?? 0,
      readyRelayCount: currentNode?.diagnosticsConnectedRelayCount(),
      events: [
        for (final event in recent)
          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(event.$2.toLocal())}  ${event.$3}',
      ],
    );
  }

  Future<void> _showDiagnostics() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => DiagnosticsPage(
        load: _diagnosticsSnapshot,
        retryStartup: _retryFromUI,
        refreshDevices: () =>
            presenceController.requestPeerProbes(userInitiated: true),
        clear: () async {
          diagnosticEvents.clear();
          node?.clearDiagnostics();
        },
        initialEnabled: widget.diagnosticsEnabled,
        setEnabled: widget.changeDiagnosticsEnabled,
      ),
    ),
  );

  Future<void> _backgroundPresenceChanged() async {
    if (!await _backgroundReceivingEnabled()) {
      startupRetry?.cancel();
    } else if (node == null && startup == null) {
      unawaited(_retryStartup());
    }
    if (mounted) {
      await presenceController.syncMonitoring(enabled: monitorPresence);
    }
  }

  BackgroundReceiving? get _backgroundSetting =>
      BackgroundReceiving.forOS(defaultTargetPlatform.name.toLowerCase());

  Future<void> _refreshBackgroundAvailability() async {
    final setting = _backgroundSetting;
    final preferences = prefs;
    if (!mounted || setting == null || preferences == null) return;
    final request = ++_backgroundStatusRequest;
    Map<Object?, Object?> status;
    try {
      status = await setting.readStatus();
    } catch (_) {
      status = {};
    }
    if (!mounted || request != _backgroundStatusRequest) return;
    setState(() {
      _backgroundAvailability = status.isEmpty
          ? null
          : (
              enabled: setting.enabled(preferences, widget.profile),
              autoAccept:
                  preferences.getBool('auto_accept_${widget.profile}') ?? false,
              status: status,
            );
    });
  }

  Future<void> _showBackgroundSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BackgroundSettingsPage(
          profile: widget.profile,
          onChanged: _backgroundPresenceChanged,
        ),
      ),
    );
    await _refreshBackgroundAvailability();
  }

  Future<void> _showSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          profile: widget.profile,
          language: widget.language,
          appearance: widget.appearance,
          deviceName: deviceName,
          systemDeviceName: systemDeviceName,
          changeSetting: widget.changeSetting,
          relaySettings: _showRelaySettings,
          diagnostics: _showDiagnostics,
          backgroundChanged: _backgroundPresenceChanged,
          updates: updates,
          rename: (name) async {
            if (!await prefs!.setString(
              'device_name_${widget.profile}',
              name,
            )) {
              throw StateError('save failed');
            }
            await node!.setDeviceInfo(name: name, deviceType: deviceType);
            if (mounted) setState(() => deviceName = name);
          },
        ),
      ),
    );
    await _refreshBackgroundAvailability();
  }

  String _relayTokenKey(String url) => runtime.relayTokenKey(url);

  bool get canRestartNode =>
      !changingRelay &&
      !contentOperationActive &&
      activeSendOperations == 0 &&
      !outgoingPairingUiActive &&
      !awaitingOfferDecision &&
      incomingOffersPending == 0 &&
      !pairings.isActive;

  Future<T> _withRelayChange<T>(Future<T> Function() change) async {
    if (!canRestartNode || shuttingDown || updates.installing) {
      throw RelayBusyException();
    }
    changingRelay = true;
    try {
      await pairedDevices?.idle;
      return await change();
    } finally {
      changingRelay = false;
      if (node == null && startupRetry?.isActive == true) {
        startupRetry?.cancel();
        unawaited(_retryStartup());
      }
      final current = node;
      if (mounted && current != null) {
        presenceController.resumeInfoUpdates();
      }
    }
  }

  Future<void> _restartForRelayChange() async {
    await startup;
    if (!mounted || shuttingDown) return;
    _setNodeStatus('starting');
    presenceController.reset();
    final closing = runtime.close();
    setState(() {});
    await closing;
    if (mounted) await _startNode();
    if (mounted && node == null) throw StateError('Restart failed');
  }

  Future<void> _showRelaySettings() async {
    final preferences = prefs!;
    final current =
        preferences.getStringList('custom_relays_${widget.profile}') ??
        <String>[];
    Future<void> restoreNode() async {
      if (mounted && node == null) {
        await runtime.close();
        await _startNode();
      }
    }

    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RelaySettingsPage(
          relays: current,
          enabled:
              preferences.getBool('custom_relays_enabled_${widget.profile}') ??
              true,
          setEnabled: (enabled) => _withRelayChange(() async {
            final previous =
                preferences.getBool(
                  'custom_relays_enabled_${widget.profile}',
                ) ??
                true;
            var saved = false;
            try {
              if (!await preferences.setBool(
                'custom_relays_enabled_${widget.profile}',
                enabled,
              )) {
                throw StateError('Save failed');
              }
              saved = true;
              await _restartForRelayChange();
            } catch (_) {
              if (saved) {
                try {
                  if (!await preferences.setBool(
                    'custom_relays_enabled_${widget.profile}',
                    previous,
                  )) {
                    throw StateError('Restore failed');
                  }
                  await restoreNode();
                } catch (e) {
                  debugPrint('Could not restore relay settings: $e');
                }
              }
              rethrow;
            }
          }),
          test: (url, token) => testRelay(url: url, token: token),
          add: (url, token) => _withRelayChange(() async {
            final normalized = Uri.parse(url).replace(path: '/').toString();
            if (current.contains(normalized)) {
              throw StateError('Duplicate relay');
            }
            final canonical = normalized;
            var saved = false;
            try {
              if (token != null) {
                await storage.write(
                  key: _relayTokenKey(canonical),
                  value: token,
                );
              }
              if (!await preferences.setStringList(
                'custom_relays_${widget.profile}',
                [...current, canonical],
              )) {
                throw StateError('Save failed');
              }
              saved = true;
              if (preferences.getBool(
                    'custom_relays_enabled_${widget.profile}',
                  ) ??
                  true) {
                await _restartForRelayChange();
              }
              current.add(canonical);
            } catch (_) {
              try {
                if (saved &&
                    !await preferences.setStringList(
                      'custom_relays_${widget.profile}',
                      current,
                    )) {
                  throw StateError('Restore failed');
                }
                await storage.delete(key: _relayTokenKey(canonical));
                await restoreNode();
              } catch (e) {
                debugPrint('Could not restore relay settings: $e');
              }
              rethrow;
            }
            return canonical;
          }),
          readToken: (url) => storage.read(key: _relayTokenKey(url)),
          update: (oldUrl, url, token) => _withRelayChange(() async {
            final normalized = Uri.parse(url).replace(path: '/').toString();
            if (normalized != oldUrl && current.contains(normalized)) {
              throw StateError('Duplicate relay');
            }
            final oldToken = await storage.read(key: _relayTokenKey(oldUrl));
            final canonical = normalized;
            var saved = false;
            try {
              if (token == null) {
                await storage.delete(key: _relayTokenKey(canonical));
              } else {
                await storage.write(
                  key: _relayTokenKey(canonical),
                  value: token,
                );
              }
              final next = current
                  .map((item) => item == oldUrl ? canonical : item)
                  .toList();
              if (!await preferences.setStringList(
                'custom_relays_${widget.profile}',
                next,
              )) {
                throw StateError('Save failed');
              }
              saved = true;
              if (preferences.getBool(
                    'custom_relays_enabled_${widget.profile}',
                  ) ??
                  true) {
                await _restartForRelayChange();
              }
            } catch (_) {
              try {
                if (saved &&
                    !await preferences.setStringList(
                      'custom_relays_${widget.profile}',
                      current,
                    )) {
                  throw StateError('Restore failed');
                }
                if (canonical == oldUrl) {
                  if (oldToken == null) {
                    await storage.delete(key: _relayTokenKey(oldUrl));
                  } else {
                    await storage.write(
                      key: _relayTokenKey(oldUrl),
                      value: oldToken,
                    );
                  }
                } else {
                  await storage.delete(key: _relayTokenKey(canonical));
                }
                await restoreNode();
              } catch (e) {
                debugPrint('Could not restore relay settings: $e');
              }
              rethrow;
            }
            if (canonical != oldUrl) {
              try {
                await storage.delete(key: _relayTokenKey(oldUrl));
              } catch (_) {
                debugPrint('Could not delete an unused relay token');
              }
            }
            current[current.indexOf(oldUrl)] = canonical;
            return canonical;
          }),
          remove: (url) => _withRelayChange(() async {
            final next = current.where((item) => item != url).toList();
            if (!await preferences.setStringList(
              'custom_relays_${widget.profile}',
              next,
            )) {
              throw StateError('Save failed');
            }
            try {
              if (preferences.getBool(
                    'custom_relays_enabled_${widget.profile}',
                  ) ??
                  true) {
                await _restartForRelayChange();
              }
            } catch (_) {
              try {
                if (!await preferences.setStringList(
                  'custom_relays_${widget.profile}',
                  current,
                )) {
                  throw StateError('Restore failed');
                }
                await restoreNode();
              } catch (e) {
                debugPrint('Could not restore relay settings: $e');
              }
              rethrow;
            }
            current.remove(url);
            try {
              await storage.delete(key: _relayTokenKey(url));
            } catch (_) {
              debugPrint('Could not delete an unused relay token');
            }
          }),
        ),
      ),
    );
  }

  void _showMyDeviceDialog() {
    final id = node!.id();
    String? copyStatus;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(t.deviceCode),
          scrollable: true,
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.showDeviceCode),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox.square(
                    dimension: 192,
                    child: QrImageView(
                      data: 'vela:1:$id',
                      backgroundColor: Colors.white,
                      semanticsLabel: t.deviceCode,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: id.substring(0, 8),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: id.substring(8, id.length - 8)),
                      TextSpan(
                        text: id.substring(id.length - 8),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  key: const ValueKey('device-id'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
                if (copyStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(copyStatus!),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.close),
            ),
            FilledButton.icon(
              onPressed: () async {
                String message;
                try {
                  await Clipboard.setData(ClipboardData(text: id));
                  message = t.deviceCodeCopied;
                } catch (_) {
                  message = t.copyDeviceCodeFailed;
                }
                if (context.mounted) update(() => copyStatus = message);
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(t.copyDeviceCode),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _prepareAndSend(
    Future<PreparedTransfer?> Function() prepare, {
    String? id,
    bool clipboard = false,
    PendingShare? share,
  }) async {
    if (_sendUnavailable || activeSendOperations != 0) {
      return;
    }
    setState(() => activeSendOperations++);
    try {
      PreparedTransfer? content;
      try {
        content = await prepare();
      } catch (e) {
        debugPrint('Could not prepare content: $e');
        if (mounted) {
          _message(
            sendErrorMessage(
              e,
              transferStarted: false,
              clipboard: clipboard,
              shared: share != null,
              translations: t,
            ),
            kind: NoticeKind.error,
          );
        }
      }
      if (content == null) return;
      final target =
          id ??
          (mounted
              ? await _choosePeer(
                  _preparedContentName(content),
                  prepared: content,
                )
              : null);
      if (target == null || !mounted || !peers.containsKey(target)) {
        await _cleanupPrepared(content);
        return;
      }
      await _send(target, _sendDeviceName(target), _createSendSession(content));
    } finally {
      if (mounted) {
        setState(() => activeSendOperations--);
      } else {
        activeSendOperations--;
      }
    }
  }

  Future<PreparedTransfer?> _pickFiles() async {
    final picked = await FilePicker.pickFiles();
    if (picked.any((file) => file.path == null)) {
      throw StateError(t.fileUnavailable);
    }
    final paths = picked.map((file) => file.path!).toList();
    if (paths.isEmpty) return null;
    if (paths.length > 100) throw StateError(t.tooManyFiles);
    return PreparedTransfer(paths: paths);
  }

  Future<PreparedTransfer> _writeTemporaryContent(
    List<int> bytes,
    TransferKind kind, {
    bool clipboard = false,
    PendingShare? share,
    String? textPreview,
  }) async {
    final dir = await getTemporaryDirectory();
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}/vela_${DateTime.now().microsecondsSinceEpoch}.${kind == TransferKind.image ? 'png' : 'txt'}',
    );
    try {
      await file.writeAsBytes(bytes, flush: true);
      return PreparedTransfer(
        paths: [file.path],
        ownedTemporaryPaths: [file.path],
        kind: kind,
        fromClipboard: clipboard,
        share: share,
        textPreview: textPreview,
      );
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<PreparedTransfer> _materializeUris(
    List<String> uris, {
    TransferKind kind = TransferKind.file,
    bool clipboard = false,
    PendingShare? share,
  }) async {
    final paths = <String>[];
    try {
      for (final uri in uris) {
        final path = await clipboardChannel.invokeMethod<String>(
          'materialize',
          {'uri': uri},
        );
        if (path == null) {
          throw StateError(
            clipboard ? t.readClipboardFailed : t.readSharedFailed,
          );
        }
        paths.add(path);
      }
      return PreparedTransfer(
        paths: paths,
        ownedTemporaryPaths: paths,
        kind: kind,
        fromClipboard: clipboard,
        share: share,
      );
    } catch (_) {
      if (paths.isNotEmpty) {
        await _cleanupPrepared(
          PreparedTransfer(paths: paths, ownedTemporaryPaths: paths),
        );
      }
      rethrow;
    }
  }

  Future<PreparedTransfer> _prepareShare(PendingShare share) {
    if (share.paths != null) {
      return Future.value(PreparedTransfer(paths: share.paths!, share: share));
    }
    if (share.uris case final uris?) {
      return _materializeUris(uris, share: share);
    }
    return _writeTemporaryContent(
      utf8.encode(share.text!),
      share.typed ? TransferKind.typedText : TransferKind.text,
      share: share,
    );
  }

  Future<PreparedTransfer> _prepareClipboard() async {
    final image = Platform.isAndroid ? await Pasteboard.image : null;
    final files = image == null
        ? (Platform.isAndroid
              ? await clipboardChannel.invokeListMethod<String>('files') ??
                    <String>[]
              : await Pasteboard.files())
        : <String>[];
    if (files.isNotEmpty) {
      if (files.length != 1) throw StateError(t.singleClipboardFile);
      if (Platform.isAndroid && files.single.startsWith('content:')) {
        return _materializeUris(
          files,
          kind: TransferKind.clipboardFile,
          clipboard: true,
        );
      }
      return PreparedTransfer(
        paths: files,
        kind: TransferKind.clipboardFile,
        fromClipboard: true,
      );
    }
    final clipboardImage = Platform.isAndroid ? image : await Pasteboard.image;
    if (clipboardImage != null) {
      return _writeTemporaryContent(
        clipboardImage,
        TransferKind.image,
        clipboard: true,
      );
    }
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty) throw StateError(t.emptyClipboard);
    return _writeTemporaryContent(
      utf8.encode(text),
      TransferKind.text,
      clipboard: true,
      textPreview: _textPreview(text, 240),
    );
  }

  String _fileContentName(List<String> paths) => paths.length > 1
      ? t.filesCount(paths.length)
      : File(paths.single).uri.pathSegments.last;

  String _sharedContentName(PendingShare share) =>
      switch ((share.paths, share.uris)) {
        (final paths?, _) => _fileContentName(paths),
        (_, final uris?) => t.filesCount(uris.length),
        _ => t.textContent,
      };

  String _preparedContentName(PreparedTransfer content) =>
      content.displayName ??
      switch (content.kind) {
        TransferKind.text => t.clipboardText,
        TransferKind.typedText => t.textContent,
        TransferKind.image => t.clipboardImage,
        _ => _fileContentName(content.paths),
      };

  String _sendReceiptContent(PreparedTransfer content) {
    final preview = (content.share?.text ?? content.textPreview)?.trim();
    if (preview != null && preview.isNotEmpty) {
      return _textPreview(preview, 160);
    }
    if (content.paths.length > 1) {
      return '${File(content.paths.first).uri.pathSegments.last} · ${t.filesCount(content.paths.length)}';
    }
    return _preparedContentName(content);
  }

  String _textPreview(String text, int limit) {
    final runes = text.trim().runes.take(limit + 1).toList();
    return runes.length <= limit
        ? String.fromCharCodes(runes)
        : '${String.fromCharCodes(runes.take(limit))}…';
  }

  Future<List<String>> _sharedItemNames(List<String> uris) async {
    try {
      final names = await const MethodChannel('vela/files')
          .invokeListMethod<String?>('itemNames', {'sources': uris});
      return names?.whereType<String>().toList() ?? [];
    } catch (e) {
      debugPrint('Could not read shared item names: $e');
      return [];
    }
  }

  Future<void> _chooseAndSendShare(PendingShare share) async {
    if (_sendUnavailable || activeSendOperations != 0) return;
    setState(() => activeSendOperations++);
    final String? id;
    try {
      final names = switch ((share.paths, share.uris)) {
        (final paths?, _) when paths.length > 1 =>
          paths.map((path) => File(path).uri.pathSegments.last).toList(),
        (_, final uris?) => await _sharedItemNames(uris),
        _ => const <String>[],
      };
      if (!mounted) return;
      id = await _choosePeer(
        _sharedContentName(share),
        share: share,
        sharedNames: names,
      );
    } finally {
      if (mounted) {
        setState(() => activeSendOperations--);
      } else {
        activeSendOperations--;
      }
    }
    if (id != null && mounted) await _sendShare(id, share);
  }

  Future<void> _sendShare(String id, PendingShare share) =>
      _prepareAndSend(() => _prepareShare(share), id: id, share: share);

  Future<void> _cleanupPrepared(PreparedTransfer content) async {
    try {
      await content.deleteOwnedTemporaryFiles();
    } catch (e) {
      debugPrint('Could not remove temporary content: $e');
    }
  }

  Future<void> _releaseShare(PendingShare share) async {
    if (share.drop) await _releaseDrop();
    if (Platform.isMacOS && share.stage != null) {
      try {
        await shareChannel.invokeMethod<void>('cleanup', {
          'stage': share.stage,
        });
      } catch (e) {
        debugPrint('Could not remove shared content: $e');
      }
    }
    if (share.drop || share.stage != null) await _takePendingShare();
  }

  SendSession _createSendSession(PreparedTransfer content) => SendSession(
    content,
    releaseSource: content.share == null
        ? null
        : () => _releaseShare(content.share!),
  );

  Future<void> _discardPreparedSendFiles(SendSession session) async {
    try {
      await session.discardPreparedFiles();
    } catch (e) {
      debugPrint('Could not remove temporary content: $e');
    }
  }

  Future<void> _releaseSendSession(SendSession session) async {
    try {
      await session.release();
    } catch (error) {
      debugPrint('Could not release send content: $error');
    }
  }

  bool _canSendTo(String id, Object? revision) =>
      peers.containsKey(id) &&
      (pairedDevices?.isCurrentPairingRevision(id, revision) ?? false);

  bool get _sendUnavailable => _failedSend != null || !_canResumeSend;

  Future<void> _discardFailedSend(SendRetry retry) async {
    if (!identical(_failedSend?.retry, retry)) return;
    final session = retry.take();
    if (session == null) return;
    setState(() {
      _failedSend = null;
      if (identical(pendingShare, session.content.share)) pendingShare = null;
    });
    await _releaseSendSession(session);
  }

  bool get _canResumeSend =>
      node != null &&
      !_deviceActionsBlocked &&
      !changingRelay &&
      !shuttingDown &&
      !updates.installing;

  Future<void> _resumeFailedSend({bool chooseDevice = false}) async {
    final failed = _failedSend;
    if (failed == null || !_canResumeSend) return;
    final target = chooseDevice
        ? await _choosePeer(
            _preparedContentName(failed.content),
            prepared: failed.content,
          )
        : failed.peer;
    if (target == null ||
        !mounted ||
        !_canResumeSend ||
        !identical(_failedSend?.retry, failed.retry) ||
        !peers.containsKey(target) ||
        (!chooseDevice && !_canSendTo(target, failed.revision))) {
      return;
    }
    final session = failed.retry.take();
    if (session == null) return;
    setState(() => _failedSend = null);
    await _send(target, _sendDeviceName(target), session);
  }

  Future<void> _send(String id, String name, SendSession session) async {
    final content = session.content;
    final share = content.share;
    final revision = pairedDevices?.pairingRevisionFor(id);
    var transferStarted = false;
    TransferJob? sendingJob;
    var sendCompleted = false;
    var declined = false;
    String? resultMessage;
    var resultKind = NoticeKind.success;
    SendRetry? retry;
    activeSendOperations++;
    try {
      if (!mounted) return;
      if (_sendUnavailable) {
        throw StateError(t.transferBusy);
      }
      if (!_canSendTo(id, revision)) throw StateError(t.sendDeviceChanged);
      final path = content.paths.first;
      if (!await File(path).exists()) throw StateError(t.fileUnavailable);
      if (!mounted) return;
      if (_sendUnavailable) {
        throw StateError(t.transferBusy);
      }
      if (!_canSendTo(id, revision)) throw StateError(t.sendDeviceChanged);
      final contentName = _preparedContentName(content);
      sendingJob = _beginTransfer(
        target: name,
        contentName: contentName,
        peerType: peerTypes[id],
      );
      setState(() {
        contentOperationActive = true;
        activity = t.connectingTo(name);
        _sendReceipt = null;
        receivedPath = null;
      });
      transferStarted = true;
      if (content.paths.length > 1) {
        await sendingJob.sendFiles(peerId: id, paths: content.paths);
      } else {
        await sendingJob.sendFile(
          peerId: id,
          path: path,
          kind: content.kind.wireName,
        );
      }
      sendCompleted = true;
      _recordDiagnostic('sent', id);
      if (mounted) {
        final message = t.sentTo(name);
        setState(() {
          hasTransferred = true;
          activity = message;
          _sendReceipt = (
            message: message,
            content: _sendReceiptContent(content),
            sent: true,
          );
          if (identical(pendingShare, share)) pendingShare = null;
        });
        unawaited(presenceController.readCurrentSnapshot());
        resultMessage = message;
      }
      await _releaseSendSession(session);
    } catch (e) {
      debugPrint('Send failed: $e');
      if (mounted) {
        setState(() => activity = null);
        final failure = classifyTransferFailure(e);
        final cancelled = cancelling || failure == TransferFailure.cancelled;
        declined =
            !cancelled &&
            transferStarted &&
            failure == TransferFailure.declined;
        if (transferStarted) {
          _recordDiagnostic(cancelled ? 'sendCancelled' : 'sendFailed', id);
        }
        resultMessage = cancelled
            ? t.transferCancelled
            : declined
            ? t.sendDeclinedBy(name)
            : sendErrorMessage(
                e,
                transferStarted: transferStarted,
                clipboard: content.fromClipboard,
                shared: share != null,
                translations: t,
              );
        resultKind = cancelled ? NoticeKind.info : NoticeKind.error;
        if (declined) {
          setState(() {
            _sendReceipt = (
              message: resultMessage!,
              content: _sendReceiptContent(content),
              sent: false,
            );
            if (identical(pendingShare, share)) pendingShare = null;
          });
        } else if (!cancelled &&
            transferStarted &&
            !sendCompleted &&
            !shuttingDown) {
          retry = session.allowRetry();
        }
      }
    } finally {
      activeSendOperations--;
      if (!sendCompleted) sendingJob?.cancel();
      if (identical(activeTransfer, sendingJob)) activeTransfer = null;
      if (transferStarted) _setTransferring(false);
      if (declined) {
        await _releaseSendSession(session);
      } else if (retry == null && !sendCompleted) {
        await _discardPreparedSendFiles(session);
      }
      if (mounted) {
        final retryOffer = retry;
        if (transferStarted) {
          setState(() {
            contentOperationActive = false;
            if (retryOffer != null) {
              _failedSend = (
                peer: id,
                revision: revision,
                message: resultMessage!,
                content: content,
                retry: retryOffer,
              );
            }
          });
          _finishSystemTransfer(resultMessage);
        }
        if (resultMessage != null) {
          if (!sendCompleted && !declined && retryOffer == null) {
            _message(resultMessage, kind: resultKind);
          } else {
            lastMessage = resultMessage;
          }
        }
      } else if (retry != null) {
        await _releaseSendSession(session);
      }
    }
  }

  Future<void> _removeHistory(
    Iterable<TransferRecord> records, {
    bool deleteFiles = false,
  }) async {
    final failed = await historyStore.remove(
      records,
      deleteFiles: deleteFiles,
      deleteFile: receivedStorage.delete,
    );
    if (failed) throw StateError(t.deleteFilesFailed);
  }

  Future<void> _openLink(String url) async {
    try {
      await const MethodChannel('vela/files')
          .invokeMethod<void>('openUrl', {'url': url});
    } catch (_) {
      if (mounted) _message(t.openLinkFailed, kind: NoticeKind.error);
    }
  }

  Future<void> _showTextContent(
    String text, {
    HistoryKind? kind,
    String? sender,
  }) async {
    final link = detectHttpLink(text);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    kind == HistoryKind.text ? t.historyText : t.textContent,
                  ),
                  if (sender != null)
                    Text(
                      t.historyReceivedFrom(sender),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: t.close,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (link != null && (Platform.isAndroid || Platform.isMacOS)) ...[
                Flexible(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 40),
                    ),
                    onPressed: () => _openLink(link),
                    child: Text(
                      t.openLink,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 40),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    Navigator.pop(context);
                    _message(t.historyCopied, kind: NoticeKind.success);
                  },
                  child: Text(
                    t.historyCopy,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openHistory(TransferRecord record) async {
    final reference = record.fileReference;
    if (reference == null || !await _receivedExists(reference)) {
      _message(t.historyMissing, kind: NoticeKind.error);
      return;
    }
    if (record.kind.canRestoreFolder) {
      await _restoreFolder(reference);
      return;
    }
    if (!record.kind.isText) {
      await _openReceived(reference);
      return;
    }
    try {
      final text = await File(reference).readAsString();
      if (!mounted) return;
      await _showTextContent(text, kind: record.kind, sender: record.peer);
    } catch (_) {
      if (mounted) _message(t.openFailed, kind: NoticeKind.error);
    }
  }

  Future<void> _exportHistory(TransferRecord record) async {
    final reference = record.fileReference;
    if (reference == null || !await _receivedExists(reference)) {
      _message(t.historyMissing, kind: NoticeKind.error);
      return;
    }
    try {
      if (await receivedStorage.export(reference, record.name)) {
        _message(t.savedFile, kind: NoticeKind.success);
      }
    } catch (e) {
      debugPrint('Export failed: $e');
      if (mounted) _message(t.saveFileFailed, kind: NoticeKind.error);
    }
  }

  void _showHistory({String? batchId}) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TransferHistoryPage(
          records: historyStore.records,
          batchId: batchId,
          open: _openHistory,
          export: _exportHistory,
          remove: _removeHistory,
          openFolder: () => receivedStorage.openFolder(),
          reveal: (record) async {
            final reference = record.fileReference;
            if (reference == null || !await _receivedExists(reference)) {
              throw StateError(t.historyMissing);
            }
            await receivedStorage.openFolder(reference: reference);
          },
        ),
      ),
    );
  }

  void _message(
    String message, {
    NoticeKind kind = NoticeKind.info,
    String? detail,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    lastMessage = message;
    if (mounted) {
      showNotice(
        context,
        message,
        kind: kind,
        detail: detail,
        actionLabel: actionLabel,
        onAction: onAction,
      );
    }
  }

  Future<bool> _receivedExists(String reference) async {
    try {
      return await receivedStorage.exists(reference);
    } catch (_) {
      return false;
    }
  }

  Future<void> _openReceived(String reference) async {
    try {
      await receivedStorage.open(reference);
    } on PlatformException catch (e) {
      _message(
        e.code == 'no_app' ? t.openNoApp : t.openFailed,
        kind: NoticeKind.error,
      );
    } catch (e) {
      debugPrint('Open failed: $e');
      _message(t.openFailed, kind: NoticeKind.error);
    }
  }

  @override
  void dispose() {
    updates.removeListener(_updatesChanged);
    updates.dispose();
    if (folderJob != null) unawaited(folderJob!.cancel());
    if (Platform.isMacOS) {
      unawaited(
        backgroundChannel
            .invokeMethod<void>('setMacBackground', false)
            .catchError((Object e) {
              debugPrint('Could not stop background receiving: $e');
            }),
      );
    }
    if (dropBookmarks.isNotEmpty || promisedDropFiles.isNotEmpty) {
      unawaited(_releaseDrop());
    }
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid || Platform.isMacOS) {
      shareChannel.setMethodCallHandler(null);
    }
    if (Platform.isAndroid ||
        Platform.isMacOS ||
        DesktopPlatform.isWindowsOrLinux) {
      backgroundChannel.setMethodCallHandler(null);
    }
    if (Platform.isAndroid) offerActionsChannel.setMethodCallHandler(null);
    progressTimer?.cancel();
    startupRetry?.cancel();
    presenceController.removeListener(_presenceChanged);
    presenceController.dispose();
    disposed = true;
    if (_failedSend?.retry.take() case final session?) {
      unawaited(_releaseSendSession(session));
    }
    unawaited(runtime.dispose());
    super.dispose();
  }

  void _clearDeviceSelection() => setState(() {
    selectedPeers.clear();
    selectingPeers = false;
  });

  Widget _buildHomeToolbar(
    bool showingGraph,
    String? status, {
    required bool allowGraph,
  }) => HomeToolbar(
    selection: selectingPeers
        ? Row(
            children: [
              IconButton(
                tooltip: t.cancel,
                onPressed: _clearDeviceSelection,
                icon: const Icon(Icons.close_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.selectedCount(selectedPeers.length),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: t.selectAll,
                onPressed: () =>
                    setState(() => selectedPeers.addAll(peers.keys)),
                icon: const Icon(Icons.select_all_rounded),
              ),
              IconButton(
                tooltip: t.removeDevice,
                onPressed: _deviceActionsBlocked || selectedPeers.isEmpty
                    ? null
                    : _removeSelectedPeers,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          )
        : null,
    addDevice: peers.isEmpty
        ? null
        : HomeToolbarAction(
            'add',
            t.addDevice,
            Icons.add_rounded,
            node == null || _deviceActionsBlocked ? null : _addDevice,
            key: const ValueKey('add-device'),
          ),
    actions: [
      if (peers.isNotEmpty) ...[
        HomeToolbarAction(
          'refresh',
          checkingPeers ? t.checking : t.refreshDevices,
          Icons.refresh_rounded,
          checkingPeers
              ? null
              : () => presenceController.requestPeerProbes(userInitiated: true),
          key: const ValueKey('refresh-devices'),
          buttonIcon: checkingPeers
              ? const SizedBox(
                  key: ValueKey('manual-refresh-progress'),
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
      ],
    ],
    viewMode: peers.isEmpty || !allowGraph
        ? null
        : HomeToolbarAction(
            'view',
            showingGraph ? t.showList : t.showGraph,
            showingGraph ? Icons.view_list_rounded : Icons.hub_outlined,
            () => _toggleDeviceView(showingGraph),
            key: const ValueKey('toggle-device-view'),
          ),
    menuActions: [
      if (status != null)
        HomeToolbarAction(
          'background',
          '${t.localBackgroundReceiving}\n$status',
          Icons.move_to_inbox_outlined,
          _showBackgroundSettings,
        ),
      if (peers.isNotEmpty)
        HomeToolbarAction(
          'select',
          t.selectDevices,
          Icons.checklist_rounded,
          _deviceActionsBlocked
              ? null
              : () => setState(() => selectingPeers = true),
          key: const ValueKey('select-devices'),
        ),
      if (node != null && peers.isNotEmpty)
        HomeToolbarAction(
          'device',
          t.showMyCode,
          Icons.qr_code_rounded,
          _showMyDeviceDialog,
          key: const ValueKey('show-device-code'),
        ),
    ],
    received: node == null
        ? null
        : HomeToolbarAction(
            'history',
            t.transferHistory,
            Icons.history_rounded,
            _showHistory,
            key: const ValueKey('transfer-history'),
          ),
    onSettings: node == null ? null : _showSettings,
  );

  bool get _deviceActionsBlocked =>
      contentOperationActive || outgoingPairingUiActive;

  List<HomeSendButton> _sendButtons() {
    final enabled =
        !_sendUnavailable &&
        activeSendOperations == 0 &&
        !selectingPeers &&
        pendingShare == null;
    return [
      HomeSendButton(
        key: const ValueKey('send-file'),
        label: t.files,
        icon: Icons.insert_drive_file_outlined,
        onPressed: enabled ? () => _chooseAndSend() : null,
      ),
      HomeSendButton(
        key: const ValueKey('send-folder'),
        label: t.folder,
        icon: Icons.folder_outlined,
        onPressed: enabled ? _chooseAndSendFolder : null,
      ),
      if (Platform.isAndroid)
        HomeSendButton(
          key: const ValueKey('send-media'),
          label: t.media,
          icon: Icons.photo_library_outlined,
          onPressed: enabled ? () => _chooseAndSend(media: true) : null,
        ),
      HomeSendButton(
        key: const ValueKey('send-text'),
        label: t.textContent,
        icon: Icons.edit_outlined,
        onPressed: enabled ? _composeAndSendText : null,
      ),
      HomeSendButton(
        key: const ValueKey('send-clipboard'),
        label: t.clipboard,
        icon: Icons.content_paste_go_rounded,
        onPressed: enabled ? () => _chooseAndSend(clipboard: true) : null,
      ),
    ];
  }

  void _tapDevice(String id) {
    if (selectingPeers) {
      _togglePeerSelection(id);
    } else {
      _showDeviceDetails(id);
    }
  }

  List<Widget> _deviceSlivers(bool showingGraph, {required bool largeText}) {
    final colors = Theme.of(context).colorScheme;
    return [
      if (showingGraph)
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final height =
                (constraints.viewportMainAxisExtent -
                        constraints.precedingScrollExtent -
                        32)
                    .clamp(100.0, double.infinity);
            return SliverToBoxAdapter(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      (constraints.viewportMainAxisExtent -
                              constraints.precedingScrollExtent)
                          .clamp(0.0, double.infinity),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DeviceGraph(
                          availableHeight: height,
                          minimumScale: .5,
                          peers: peers.keys.toList(),
                          selfName: deviceName,
                          selfLabel: t.myDevice,
                          selfIcon: _iconForType(deviceType),
                          name: peerState.displayName,
                          icon: _deviceIcon,
                          presence: _presenceIcon,
                          selected: selectedPeers,
                          selecting: selectingPeers,
                          onSelfTap: _showMyDeviceDialog,
                          enabled: !_deviceActionsBlocked,
                          onTap: _tapDevice,
                          onLongPress: _togglePeerSelection,
                        ),
                        Text(
                          t.graphPairedDevicesHint,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        )
      else
        SliverPadding(
          padding: EdgeInsets.zero,
          sliver: SliverList.builder(
            itemCount: peers.length,
            itemBuilder: (context, index) {
              final id = peers.keys.elementAt(index);
              final name = peerState.displayName(id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: selectedPeers.contains(id)
                      ? colors.secondaryContainer
                      : colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  child: ListTile(
                    key: ValueKey('peer-$id'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    leading: largeText
                        ? null
                        : Icon(_deviceIcon(id), color: colors.primary),
                    title: Text(
                      name,
                      maxLines: largeText ? null : 1,
                      overflow: largeText ? null : TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(_presenceLabel(id)),
                    trailing: selectingPeers
                        ? Semantics(
                            label: peerState.displayName(id),
                            child: Checkbox(
                              value: selectedPeers.contains(id),
                              onChanged: _deviceActionsBlocked
                                  ? null
                                  : (_) => _togglePeerSelection(id),
                            ),
                          )
                        : largeText
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ExcludeSemantics(child: _presenceIcon(id)),
                              const SizedBox(width: 14),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                    onLongPress: _deviceActionsBlocked
                        ? null
                        : () => _togglePeerSelection(id),
                    onTap: _deviceActionsBlocked ? null : () => _tapDevice(id),
                  ),
                ),
              );
            },
          ),
        ),
      if (!showingGraph) const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ];
  }

  Widget _buildDeviceViewport(BuildContext context, BoxConstraints viewport) {
    final colors = Theme.of(context).colorScheme;
    final wide = viewport.maxWidth >= 700;
    final largeText = HomeSendButton.usesLargeLabels(context);
    final compactHeader = wide && viewport.maxHeight < 500 && !Platform.isMacOS;
    final headerTop = Platform.isMacOS
        ? 44.0
        : compactHeader
        ? 4.0
        : 24.0;
    final headerBottom = compactHeader ? 4.0 : 12.0;
    final showingGraph = deviceView == 'graph' && !largeText;
    final background = _backgroundSetting;
    final availability = _backgroundAvailability;
    final backgroundStatus =
        background != null &&
            availability != null &&
            node != null &&
            error == null &&
            peers.isNotEmpty
        ? background.statusText(
            t,
            availability.enabled,
            availability.status,
            autoAccept: availability.autoAccept,
          )
        : null;
    final showBackgroundStatus = viewport.maxHeight >= 500;

    final actions = _sendButtons();
    final minimumActionWidth = largeText
        ? HomeSendButton.minimumLargeLabelWidth(context, actions)
        : null;
    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, headerTop, 24, headerBottom),
          sliver: SliverToBoxAdapter(
            child: _buildHomeToolbar(
              showingGraph,
              showBackgroundStatus ? null : backgroundStatus,
              allowGraph: !largeText,
            ),
          ),
        ),
        if (showBackgroundStatus && backgroundStatus != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            sliver: SliverToBoxAdapter(
              child: ListTile(
                key: const ValueKey('local-background-availability'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                tileColor: colors.surfaceContainerLow,
                title: Text(t.localBackgroundReceiving),
                subtitle: Text(backgroundStatus),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _showBackgroundSettings,
              ),
            ),
          ),
        if (node != null &&
            error == null &&
            peers.isNotEmpty &&
            pendingShare == null &&
            !showingGraph &&
            viewport.maxHeight >= 520)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            sliver: SliverToBoxAdapter(
              child: Semantics(
                header: true,
                child: Text(
                  t.sendContentGroup,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
          ),
        if (error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.startupFailed, style: TextStyle(color: colors.error)),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(onPressed: _retryFromUI, child: Text(t.retry)),
                      TextButton(
                        onPressed: _showDiagnostics,
                        child: Text(t.diagnostics),
                      ),
                      if (Platform.isAndroid ||
                          Platform.isMacOS ||
                          DesktopPlatform.isWindowsOrLinux)
                        TextButton(
                          onPressed: _showBackgroundSettings,
                          child: Text(t.backgroundReceiving),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          )
        else if (node == null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Semantics(liveRegion: true, child: Text(t.startingVela)),
                ],
              ),
            ),
          )
        else if (peers.isEmpty)
          EmptyDevicesSliver(
            onAddDevice: _deviceActionsBlocked ? null : _addDevice,
            onShowCode: _showMyDeviceDialog,
          )
        else
          SliverLayoutBuilder(
            builder: (context, constraints) => SliverToBoxAdapter(
              child: SizedBox(
                height: math.max(
                  HomeResponsiveLayout.minimumHeight(
                    wide: wide,
                    count: actions.length,
                    largeText: largeText,
                    width: viewport.maxWidth - 48,
                    minimumActionWidth: minimumActionWidth,
                  ),
                  constraints.viewportMainAxisExtent -
                      constraints.precedingScrollExtent,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: HomeResponsiveLayout(
                    wide: wide,
                    largeText: largeText,
                    minimumActionWidth: minimumActionWidth,
                    centerActions: showingGraph,
                    actions: actions,
                    devices: CustomScrollView(
                      key: const ValueKey('home-devices'),
                      physics: const ClampingScrollPhysics(),
                      slivers: _deviceSlivers(
                        showingGraph,
                        largeText: largeText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool get _hasLiveActivity =>
      outgoingPairingUiActive || (contentOperationActive && activity != null);

  Widget? _buildActivityNotice() {
    final colors = Theme.of(context).colorScheme;
    return _hasLiveActivity
        ? ActivityNotice(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              cancelling
                                  ? t.cancelling
                                  : contentOperationActive && activity != null
                                  ? activity!
                                  : t.connectingPair,
                              key: const ValueKey('activity-status'),
                              maxLines: contentOperationActive ? 2 : null,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (activeTransfer != null &&
                              sendingTo != null &&
                              notificationContentName != null)
                            Text(
                              notificationContentName!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    if (contentOperationActive && connectionRoute.isNotEmpty)
                      Tooltip(
                        message: connectionRoute == 'direct'
                            ? t.directConnection
                            : t.relayConnection,
                        child: Icon(
                          connectionRoute == 'direct'
                              ? Icons.link_rounded
                              : Icons.cloud_outlined,
                          key: const ValueKey('transfer-path'),
                          size: 20,
                        ),
                      ),
                    if (contentOperationActive)
                      IconButton(
                        key: const ValueKey('cancel-transfer'),
                        tooltip: t.cancel,
                        onPressed: cancelling ? null : _cancelTransfer,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    if (outgoingPairingUiActive)
                      IconButton(
                        key: const ValueKey('cancel-pairing'),
                        tooltip: t.cancel,
                        onPressed: _cancelPairing,
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
                if (contentOperationActive && transferProgress != null) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(value: transferProgress),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_size(transferredBytes)} / ${_size(totalBytes)} · ${(transferProgress! * 100).floor()}%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSecondaryContainer.withValues(
                              alpha: .75,
                            ),
                          ),
                        ),
                      ),
                      if (hasTransferred &&
                          transferRate?.bytesPerSecond != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${_size(transferRate!.bytesPerSecond!.round())}/s',
                          key: const ValueKey('transfer-speed'),
                          style: TextStyle(
                            color: colors.onSecondaryContainer.withValues(
                              alpha: .75,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          )
        : _failedSend != null
        ? _buildSendRetryNotice()
        : pendingShare != null
        ? ActivityNotice(child: _buildPendingShareNotice(pendingShare!))
        : _buildSendReceipt();
  }

  Widget? _buildSendReceipt() {
    final receipt = _sendReceipt;
    if (receipt == null) return null;
    return ActivityNotice(
      child: Row(
        key: const ValueKey('send-receipt'),
        children: [
          Icon(
            receipt.sent
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(receipt.message),
                  Text(
                    receipt.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => setState(() => _sendReceipt = null),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingShareNotice(PendingShare share) {
    final onlyPeer = peers.keys.singleOrNull;
    final preview = share.text?.trim();
    return Column(
      key: const ValueKey('pending-share'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            t.pendingContent(_sharedContentName(share)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (preview != null && preview.isNotEmpty)
          Text(
            String.fromCharCodes(preview.runes.take(120)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (peers.isEmpty) Text(t.addDeviceToContinueSending),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: activeSendOperations != 0
                  ? null
                  : () {
                      if (!identical(pendingShare, share) ||
                          activeSendOperations != 0) {
                        return;
                      }
                      setState(() => pendingShare = null);
                      unawaited(_releaseShare(share));
                    },
              child: Text(t.cancelShare),
            ),
            FilledButton(
              key: const ValueKey('choose-share-device'),
              onPressed:
                  peers.isEmpty || _sendUnavailable || activeSendOperations != 0
                  ? null
                  : () {
                      if (!identical(pendingShare, share)) return;
                      unawaited(
                        onlyPeer != null
                            ? _sendShare(onlyPeer, share)
                            : _chooseAndSendShare(share),
                      );
                    },
              child: Text(
                activeSendOperations != 0
                    ? t.preparingSendContent
                    : onlyPeer != null
                    ? t.sendToDevice(peerState.displayName(onlyPeer))
                    : t.chooseDevice,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSendRetryNotice() {
    final failed = _failedSend!;
    final allowed = _canSendTo(failed.peer, failed.revision);
    return ActivityNotice(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              allowed
                  ? '${t.sendFailedTo(_sendDeviceName(failed.peer))} ${failed.message}'
                  : peers.isEmpty
                  ? t.addDeviceToContinueSending
                  : t.sendDeviceChanged,
            ),
          ),
          Text(
            _sendReceiptContent(failed.content),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => unawaited(_discardFailedSend(failed.retry)),
                child: Text(t.discardSend),
              ),
              if (peers.isNotEmpty)
                TextButton(
                  key: const ValueKey('choose-retry-device'),
                  onPressed: _canResumeSend
                      ? () => _resumeFailedSend(chooseDevice: true)
                      : null,
                  child: Text(t.chooseDevice),
                ),
              if (allowed)
                FilledButton(
                  key: const ValueKey('retry-send'),
                  onPressed: _canResumeSend ? _resumeFailedSend : null,
                  child: Text(t.retry),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final notice = _buildActivityNotice();
    final showLiveActivity = widget.showLiveActivity;
    final appShowsActivity = _hasLiveActivity && showLiveActivity != null;
    if (appShowsActivity || _publishedLiveActivity) {
      _publishedLiveActivity = appShowsActivity;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showLiveActivity?.call(appShowsActivity ? notice : null);
      });
    }
    final page = Scaffold(
      body: SafeArea(child: LayoutBuilder(builder: _buildDeviceViewport)),
      bottomNavigationBar: appShowsActivity ? null : notice,
    );
    return PopScope(
      canPop: !selectingPeers,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selectingPeers) _clearDeviceSelection();
      },
      child: Platform.isMacOS || DesktopPlatform.isWindowsOrLinux
          ? DropTarget(
              enable:
                  node != null &&
                  !_deviceActionsBlocked &&
                  (ModalRoute.of(context)?.isCurrent ?? true),
              onDragEntered: (_) => setState(() => dropHover = true),
              onDragExited: (_) => setState(() => dropHover = false),
              onDragDone: (details) => unawaited(_receiveDrop(details)),
              child: Stack(
                children: [
                  page,
                  if (dropHover)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          margin: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.surface.withValues(alpha: .96),
                            border: Border.all(color: colors.primary, width: 2),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.file_download_outlined,
                                  size: 42,
                                  color: colors.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  t.dropFilesHere,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )
          : page,
    );
  }
}

class _TextComposeDialog extends StatefulWidget {
  const _TextComposeDialog({required this.devices, required this.isPaired});

  final Map<String, ({String name, String status})> devices;
  final bool Function(String) isPaired;

  @override
  State<_TextComposeDialog> createState() => _TextComposeDialogState();
}

class _TextComposeDialogState extends State<_TextComposeDialog> {
  final controller = TextEditingController();
  String? selected;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit(String peer) {
    final t = AppLocalizations.of(context)!;
    final text = controller.text;
    if (utf8.encode(text).length > 1024 * 1024) {
      setState(() => error = t.textTooLarge);
    } else if (!widget.isPaired(peer)) {
      setState(() => error = t.sendDeviceSelectAgain);
    } else {
      Navigator.pop(context, (peer: peer, text: text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final onlyPeer = widget.devices.keys.singleOrNull;
    final target = onlyPeer ?? selected;
    return AlertDialog(
      scrollable: true,
      title: Text(t.sendText),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 4,
              maxLines: 12,
              decoration: InputDecoration(hintText: t.enterText),
              onChanged: (_) => setState(() => error = null),
            ),
            if (onlyPeer == null) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('text-recipient'),
                isExpanded: true,
                itemHeight: null,
                decoration: InputDecoration(
                  labelText: t.chooseDevice,
                  border: const OutlineInputBorder(),
                ),
                selectedItemBuilder: (_) => [
                  for (final device in widget.devices.values)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(device.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                items: [
                  for (final entry in widget.devices.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '${entry.value.name} · ${entry.value.status}',
                        ),
                      ),
                    ),
                ],
                onChanged: (id) => setState(() {
                  selected = id;
                  error = null;
                }),
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: controller.text.isEmpty || target == null
              ? null
              : () => _submit(target),
          child: Text(
            target == null
                ? t.sendAction
                : t.sendToDevice(widget.devices[target]!.name),
          ),
        ),
      ],
    );
  }
}

String transferErrorMessage(Object error, [AppLocalizations? translations]) {
  final t = translations ?? lookupAppLocalizations(const Locale('zh'));
  if (error is StateError) return error.message.toString();
  return switch (classifyTransferFailure(error)) {
    TransferFailure.cancelled => t.transferCancelled,
    TransferFailure.declined => t.transferDeclined,
    TransferFailure.saveFailed => t.saveFailed,
    _ => t.transferInterrupted,
  };
}

String sendErrorMessage(
  Object error, {
  required bool transferStarted,
  required bool clipboard,
  required bool shared,
  required AppLocalizations translations,
}) {
  if (error is StateError) return error.message.toString();
  if (transferStarted) return transferErrorMessage(error, translations);
  if (clipboard) return translations.readClipboardFailed;
  if (shared) return translations.readSharedFailed;
  return translations.sendFailed;
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}
