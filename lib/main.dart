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
import 'send_session.dart';
import 'paired_devices.dart';
import 'pending_share.dart';
import 'prepared_transfer.dart';
import 'pairing_session.dart';
import 'pairing_dialog.dart';
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
  await DesktopPlatform.restoreBackgroundSettings(settings);
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
      home: HomePage(
        key: _testHome,
        profile: widget.profile,
        language: language,
        appearance: appearance,
        changeSetting: _changeSetting,
        diagnosticsEnabled: diagnosticsEnabled,
        changeDiagnosticsEnabled: _changeDiagnosticsEnabled,
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
  });
  final String profile;
  final String language;
  final String appearance;
  final Future<void> Function(String, String) changeSetting;
  final bool diagnosticsEnabled;
  final Future<void> Function(bool) changeDiagnosticsEnabled;
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
  static const offerActionsChannel = MethodChannel('vela/offer_actions');
  late final runtime = AppRuntime(
    profile: widget.profile,
    testIdentity: kDebugMode && _driverMode,
    recordDiagnostic: _recordDiagnostic,
    onStartupFailure: _showStartupFailure,
    onMembershipChanging: _invalidatePeerMembership,
    onStateChanged: _publishPeerState,
    onRestore: _restorePeerSessions,
    onMembershipSettled: _settlePeerMembership,
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
  late final presenceController = PresenceController(
    pairingActive: (id) =>
        incomingPairings.containsKey(id) || outgoingPairings.containsKey(id),
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
    isMacOS: Platform.isMacOS || DesktopPlatform.isWindowsOrLinux,
    androidBackgroundReceive:
        Platform.isAndroid &&
        (prefs?.getBool('background_receive_${widget.profile}') ?? false),
  );
  Completer<void>? foregroundWaiter;
  Completer<bool>? notificationDecision;
  String? notificationOfferId;
  final List<_DiagnosticEntry> diagnosticEvents = [];
  final Set<String> selectedPeers = {};
  bool selectingPeers = false;
  String? deviceView;
  bool? automaticGraph;
  String deviceName = '设备';
  String systemDeviceName = '设备';
  String deviceType = 'other';
  String? error;
  bool contentOperationActive = false;
  bool outgoingPairingUiActive = false;
  final Map<String, OutgoingPairingSession> outgoingPairings = {};
  final Map<String, Future<void>> pairingTransitions = {};
  final Map<String, IncomingPairingSession> incomingPairings = {};
  String? activePairingPeer;
  bool awaitingOfferDecision = false;
  bool changingRelay = false;
  int incomingOffersPending = 0;
  int activeSendOperations = 0;
  bool pairingDialogActive = false;
  String? activity;
  AppLocalizations get t => AppLocalizations.of(context)!;
  String? lastMessage;
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
  String transferPath = '';
  bool hasTransferred = false;
  int transferredBytes = 0;
  int totalBytes = 0;
  int lastSystemTransferUpdate = 0;
  String? sendingTo;
  String? notificationContentName;
  String? notificationPeerType;
  String? notificationTransferId;
  PendingShare? pendingShare;
  PendingShare? handledAndroidShare;
  final List<Uint8List> dropBookmarks = [];
  final List<String> promisedDropFiles = [];
  bool dropHover = false, processingDrop = false;
  late final historyStore = TransferHistoryStore(widget.profile);

  bool get _updateBusy =>
      !canRestartNode ||
      startup != null ||
      folderOperation ||
      processingDrop ||
      pairingDialogActive ||
      shuttingDown;

  Future<void> _prepareUpdateInstall() async {
    if (_updateBusy) throw StateError('A transfer or pairing is in progress');
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
        if (!mounted || shuttingDown || updates.state != AppUpdateState.ready)
          return;
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
        if (call.method == 'decision' &&
            arguments is Map &&
            arguments['id'] == notificationOfferId &&
            arguments['accepted'] is bool &&
            notificationDecision?.isCompleted == false) {
          notificationDecision!.complete(arguments['accepted'] as bool);
        }
      });
    }
    if (Platform.isAndroid ||
        Platform.isMacOS ||
        DesktopPlatform.isWindowsOrLinux) {
      backgroundChannel.setMethodCallHandler((call) async {
        if (call.method == 'shutdown' &&
            (Platform.isMacOS || DesktopPlatform.isWindowsOrLinux)) {
          shuttingDown = true;
          startupRetry?.cancel();
          activeTransfer?.cancel();
          await folderJob?.cancel();
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
          await presenceController.networkChanged(resumed: resumed);
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
          windowVisibilityRevision++;
          final wasMonitoring = monitorPresence;
          final wasHidden = !presenceVisible;
          presenceWindowHidden = false;
          foreground = true;
          unawaited(_showLegacyPairingNotice());
          if (wasMonitoring != monitorPresence)
            presenceController.requestMonitoring(enabled: monitorPresence);
          if (foregroundWaiter?.isCompleted == false) {
            foregroundWaiter!.complete();
          }
          if (shouldRefreshForVisibility(
            visible: presenceVisible,
            becameVisible: wasHidden,
            refreshing: refreshingPresence,
          )) {
            unawaited(
              (wasHidden
                  ? presenceController.probePeers()
                  : presenceController.readSnapshot()),
            );
          }
        }
      });
    }
    if (Platform.isAndroid || Platform.isMacOS) {
      shareChannel.setMethodCallHandler((call) async {
        if (call.method == 'available') {
          if (Platform.isAndroid) await _showPendingTextPreview();
          await _takePendingShare();
        }
      });
      if (Platform.isAndroid) unawaited(_showPendingTextPreview());
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
      if (p != null && p.path != transferPath) {
        setState(() => transferPath = p.path);
      }
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
          (value != transferProgress || updatedRate || started)) {
        setState(() {
          transferProgress = value;
          transferredBytes = done;
          totalBytes = total;
          if (started) {
            hasTransferred = true;
            if (sendingTo != null) {
              activity = t.sendingTo(sendingTo!);
            }
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
            ? t.notificationSending
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
    if (Platform.isMacOS || DesktopPlatform.isWindowsOrLinux) {
      unawaited(_syncInitialWindowVisibility());
    }
    if (Platform.isMacOS || DesktopPlatform.isWindowsOrLinux) {
      unawaited(
        _applyMacBackground().catchError((Object e) {
          debugPrint('Could not restore background receiving: $e');
        }),
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
      unawaited(_showLegacyPairingNotice());
      if (foregroundWaiter?.isCompleted == false) foregroundWaiter!.complete();
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
            ? presenceController.probePeers()
            : presenceController.readSnapshot()),
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
    transferPath = '';
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

  void _setNodeStatus(String status) => _updateMacMenu('setNodeStatus', status);

  void _setTransferring(bool transferring) =>
      _updateMacMenu('setTransferring', transferring);

  void _updateMacMenu(String method, Object value) {
    if (!Platform.isMacOS && !DesktopPlatform.isWindowsOrLinux) return;
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
              'open': t.view,
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
    if (pendingShare != null) {
      _message(t.dropAlreadyPending, kind: NoticeKind.error);
      return;
    }
    if (peers.isEmpty) {
      _message(t.noDevices, kind: NoticeKind.info);
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

  Future<void> _showPendingTextPreview() async {
    try {
      final path = await shareChannel.invokeMethod<String>('takeTextPreview');
      if (path == null || !mounted) return;
      final text = await File(path).readAsString();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_showTextContent(text));
        });
      }
    } catch (e) {
      debugPrint('Could not view received text: $e');
      if (mounted) _message(t.historyMissing, kind: NoticeKind.error);
    }
  }

  Future<void> _takePendingShare() async {
    if (pendingShare != null) return;
    try {
      final share = await shareChannel.invokeMapMethod<String, dynamic>('take');
      if (mounted && share != null) {
        setState(() => pendingShare = PendingShare.fromMap(share));
        if (!contentOperationActive &&
            !outgoingPairingUiActive &&
            !awaitingOfferDecision) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        if (Platform.isAndroid) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _sendPendingAndroidShare(),
          );
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
    final key = Platform.isAndroid
        ? 'background_receive_${widget.profile}'
        : Platform.isMacOS
        ? 'mac_background_receiving'
        : DesktopPlatform.isWindowsOrLinux
        ? 'desktop_background_receiving'
        : null;
    if (key == null) return false;
    return (await SharedPreferences.getInstance()).getBool(key) ??
        DesktopPlatform.isWindowsOrLinux;
  }

  Future<void> _syncInitialWindowVisibility() async {
    final revision = windowVisibilityRevision;
    try {
      final visible = await backgroundChannel.invokeMethod<bool>(
        'getWindowVisible',
      );
      if (!mounted ||
          windowVisibilityRevision != revision ||
          visible != false) {
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

  Future<void> _applyMacBackground() async {
    if ((!Platform.isMacOS && !DesktopPlatform.isWindowsOrLinux) ||
        shuttingDown)
      return;
    final enabled = await _backgroundReceivingEnabled();
    if (!mounted || shuttingDown) return;
    await backgroundChannel.invokeMethod<void>(
      Platform.isMacOS ? 'setMacBackground' : 'setDesktopBackground',
      enabled,
    );
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
        deviceView = ['graph', 'list'].contains(storedView) ? storedView : null;
      });
      presenceController.attach(n, pairedDevices!);
      _recordDiagnostic('startup_complete_done');
      _recordDiagnostic('ready');
      startupFailures = 0;
      _setNodeStatus('ready');
      if (Platform.isAndroid) {
        unawaited(
          backgroundChannel
              .invokeMethod<void>('nodeReady', {'message': t.backgroundReady})
              .catchError((Object _) {}),
        );
      }
      if (ready.legacyStateDetected &&
          !(p.getBool('legacy_pairing_notice_${widget.profile}') ?? false)) {
        legacyNoticePending = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_showLegacyPairingNotice()),
        );
      }
      if (Platform.isAndroid) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _sendPendingAndroidShare(),
        );
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
                }),
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
      unawaited(presenceController.probePeers());
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

  void _replacePeerSession(String id) => presenceController.replaceSession(id);

  Future<T> _pairingTransition<T>(
    String id,
    Future<T> Function() action,
  ) async {
    final previous = pairingTransitions[id] ?? Future<void>.value();
    final complete = Completer<void>();
    final current = complete.future;
    pairingTransitions[id] = current;
    await previous;
    try {
      return await action();
    } finally {
      complete.complete();
      if (identical(pairingTransitions[id], current)) {
        pairingTransitions.remove(id);
      }
    }
  }

  Future<void> _syncTrustNow(VelaNode source) async {
    if (mounted && identical(node, source)) await pairedDevices!.syncTrust();
  }

  Future<void> _finishPairing(VelaNode source, String id) =>
      _pairingTransition(id, () async {
        if (identical(node, source) &&
            !outgoingPairings.containsKey(id) &&
            !incomingPairings.containsKey(id)) {
          try {
            await _syncTrustNow(source);
            await source.endPairing(peerId: id);
            if (!peers.containsKey(id)) presenceController.forgetSession(id);
          } catch (e) {
            debugPrint('Could not finish pairing: $e');
            if (mounted && identical(node, source)) {
              Timer(
                const Duration(seconds: 1),
                () => unawaited(_finishPairing(source, id)),
              );
            }
          }
        }
      });

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
    VelaNode n,
    IncomingRequest offer,
    IncomingRequestInfo info,
  ) async {
    final id = info.sender;
    final device = info.pairing!;
    if (!mounted || !identical(node, n) || shuttingDown || updates.installing) {
      await offer.decline();
      return;
    }
    if (incomingPairings.containsKey(id) || incomingPairings.length >= 8) {
      await offer.declinePairConflict();
      return;
    }
    final alreadyPairing = outgoingPairings.containsKey(id);
    final incoming = IncomingPairingSession();
    final cancelled = incoming.cancelled;
    incomingPairings[id] = incoming;
    if (!alreadyPairing) _replacePeerSession(id);
    final session = presenceController.sessionFor(id);
    try {
      await _pairingTransition(id, () => n.beginPairing(peerId: id));
      final outgoing = outgoingPairings[id];
      if (outgoing != null) {
        final decision = await outgoing.arbitration.decideIncoming(
          localId: n.id(),
          incomingId: id,
        );
        if (!mounted || !identical(node, n) || cancelled.isCompleted) return;
        if (decision == PairingCollision.duplicate) {
          await offer.decline();
          return;
        }
        if (decision == PairingCollision.busy) {
          await offer.declinePairConflict();
          return;
        }
      }
      if (pairingDialogActive) {
        await offer.declinePairConflict();
        return;
      }
      if (!mounted || !identical(node, n)) return;
      pairingDialogActive = true;
      final PairingDialogResult accepted;
      try {
        accepted = await showPairingDialog(
          context,
          peerClosed: Future.any([
            offer.waitForConnectionClose(),
            cancelled.future,
          ]),
          builder: (context) => AlertDialog(
            constraints: const BoxConstraints(maxWidth: 420),
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
                Text(
                  t.deviceCodeShort(
                    '${id.substring(0, 8)}…${id.substring(id.length - 8)}',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
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
        );
      } finally {
        pairingDialogActive = false;
      }
      if (!mounted ||
          !identical(node, n) ||
          cancelled.isCompleted ||
          !identical(presenceController.sessionFor(id), session) ||
          accepted == PairingDialogResult.connectionClosed) {
        return;
      }
      if (accepted != PairingDialogResult.accepted) {
        await offer.decline();
        return;
      }
      var saved = false;
      await pairedDevices!.update((state) {
        if (!identical(node, n) ||
            cancelled.isCompleted ||
            !identical(presenceController.sessionFor(id), session)) {
          return state;
        }
        saved = true;
        return state.add(id, device.name, device.deviceType);
      });
      if (!saved) {
        await offer.declinePairConflict();
        return;
      }
      await _syncTrustNow(n);
      if (!mounted ||
          !identical(node, n) ||
          cancelled.isCompleted ||
          !identical(presenceController.sessionFor(id), session)) {
        return;
      }
      try {
        await offer.acceptPair(name: deviceName, deviceType: deviceType);
        if (mounted) {
          unawaited(presenceController.readSnapshot());
          _message(t.addedPeer(device.name), kind: NoticeKind.success);
        }
      } catch (e) {
        debugPrint('Could not send pairing reply: $e');
        if (mounted) _message(t.pairFailed, kind: NoticeKind.error);
      }
    } catch (e) {
      debugPrint('Could not process pairing request: $e');
    } finally {
      if (identical(incomingPairings[id], incoming)) {
        incomingPairings.remove(id);
      }
      try {
        await _finishPairing(n, id);
      } catch (e) {
        debugPrint('Could not finish pairing: $e');
      }
    }
  }

  Future<void> _listenForIncomingRequests(VelaNode n) async {
    final offers = StreamController<IncomingRequest>();
    var queued = 0;
    unawaited(() async {
      try {
        while (!disposed && identical(node, n)) {
          final offer = await n.nextRequest();
          if (!identical(node, n) ||
              changingRelay ||
              shuttingDown ||
              updates.installing) {
            unawaited(offer.decline());
            continue;
          }
          final info = offer.info();
          if (info.pairing != null) {
            unawaited(_handlePair(n, offer, info));
          } else if (queued < 16) {
            queued++;
            incomingOffersPending++;
            offers.add(offer);
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
    final iterator = StreamIterator(offers.stream);
    while (!disposed && identical(node, n)) {
      var backgroundNotified = false;
      var receivingStarted = false;
      TransferJob? receivingJob;
      var receiveCompleted = false;
      var processingOffer = false;
      String? diagnosticPeer;
      try {
        if (!await iterator.moveNext()) return;
        processingOffer = true;
        final offer = iterator.current;
        queued--;
        if (!mounted || !identical(node, n)) return;
        final info = offer.info();
        final kind = TransferKind.fromWire(info.kind);
        String senderName() => peers.containsKey(info.sender)
            ? peerState.displayName(info.sender)
            : t.device;
        diagnosticPeer = info.sender;
        while (contentOperationActive && !disposed) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (!mounted) return;
        if (!peers.containsKey(info.sender)) {
          await offer.decline();
          continue;
        }
        final session = presenceController.sessionFor(info.sender);
        bool stillAuthorized() =>
            session != null &&
            peers.containsKey(info.sender) &&
            identical(presenceController.sessionFor(info.sender), session);
        unawaited(presenceController.readSnapshot());
        final autoAccept =
            prefs?.getBool('auto_accept_${widget.profile}') ?? false;
        final typedText = kind == TransferKind.typedText;
        final contentName = typedText
            ? t.textContent
            : switch (kind) {
                TransferKind.text => t.clipboardText,
                TransferKind.image => t.clipboardImage,
                TransferKind.batch => t.filesCount(info.files.length),
                _ => info.name,
              };
        final visible =
            Platform.isMacOS ||
                Platform.isAndroid ||
                DesktopPlatform.isWindowsOrLinux
            ? await backgroundChannel.invokeMethod<bool>('isVisible') ??
                  foreground
            : true;
        final wasBackground = !visible;
        var accept = autoAccept;
        var decided = autoAccept;
        if (wasBackground) {
          foregroundWaiter ??= Completer<void>();
          if (foregroundWaiter!.isCompleted) {
            foregroundWaiter = Completer<void>();
          }
          if (Platform.isAndroid && !autoAccept) {
            notificationOfferId = DateTime.now().microsecondsSinceEpoch
                .toString();
            notificationDecision = Completer<bool>();
          }
          try {
            await backgroundChannel.invokeMethod<void>('offer', {
              'title': Platform.isAndroid
                  ? t.shareFrom(senderName())
                  : (senderName()),
              'message': Platform.isAndroid
                  ? '$contentName · ${_size(info.size.toInt())}'
                  : t.backgroundOffer,
              'shortText': t.incomingShort,
              'focus':
                  Platform.isMacOS &&
                  (prefs?.getBool('mac_focus_on_offer_${widget.profile}') ??
                      true),
              'id': notificationOfferId,
              'accept': t.receive,
              'reject': t.reject,
            });
            backgroundNotified = true;
          } catch (e) {
            debugPrint('Could not show incoming notification: $e');
          }
          if (!autoAccept) {
            final result = await Future.any<Object>([
              foregroundWaiter!.future.then((_) => 'visible'),
              offer.waitForConnectionClose().then((_) => 'closed'),
              if (notificationDecision != null) notificationDecision!.future,
            ]);
            notificationOfferId = null;
            notificationDecision = null;
            try {
              await backgroundChannel.invokeMethod<void>('clearOffer');
              backgroundNotified = false;
            } catch (_) {}
            if (result == 'closed' || !mounted) continue;
            if (result is bool) {
              accept = result;
              decided = true;
            }
          }
        }
        if (!decided) {
          if (!mounted) return;
          final navigator = Navigator.of(context, rootNavigator: true);
          var offerDisconnected = false;
          final route = DialogRoute<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              constraints: const BoxConstraints(maxWidth: 420),
              title: Text(
                t.shareFrom(senderName()),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contentName,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (kind == TransferKind.batch) ...[
                    const SizedBox(height: 6),
                    Text(
                      info.files.take(3).join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _size(info.size.toInt()),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  key: const ValueKey('accept-offer'),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(t.receive),
                ),
              ],
            ),
          );
          awaitingOfferDecision = true;
          final decision = navigator.push(route);
          unawaited(
            offer.waitForConnectionClose().then((_) {
              if (route.isActive) {
                offerDisconnected = true;
                navigator.removeRoute(route, false);
              }
            }),
          );
          accept = await decision == true;
          awaitingOfferDecision = false;
          if (offerDisconnected) {
            if (mounted) _message(t.transferCancelled);
            continue;
          }
        }
        if (!accept) {
          await offer.decline();
          continue;
        }
        while (contentOperationActive && !disposed) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (!mounted) return;
        if (!stillAuthorized()) {
          await offer.decline();
          continue;
        }
        receivingJob = _beginTransfer(
          contentName: contentName,
          peerType: peerTypes[info.sender],
        );
        setState(() {
          contentOperationActive = true;
          activity = t.receiving(contentName);
          receivedPath = null;
        });
        receivingStarted = true;
        final base = Platform.isAndroid
            ? await getApplicationSupportDirectory()
            : await getApplicationDocumentsDirectory();
        final privateDir = await Directory(
          '${base.path}/Vela/${widget.profile}',
        ).create(recursive: true);
        final isFile = kind.isFile;
        var dir = privateDir;
        var savedPrivately = false;
        if ((Platform.isMacOS || DesktopPlatform.isWindowsOrLinux) && isFile) {
          try {
            dir = await receivedStorage.writableDirectory();
          } catch (e) {
            savedPrivately = true;
            debugPrint('Save location unavailable: $e');
          }
        }
        if (!stillAuthorized()) {
          await offer.decline();
          if (mounted) {
            setState(() {
              contentOperationActive = false;
              activity = null;
            });
          }
          _setTransferring(false);
          receivingStarted = false;
          continue;
        }
        final staged = kind == TransferKind.batch
            ? await offer.receiveFiles(directory: dir.path, job: receivingJob)
            : [await offer.receiveFile(directory: dir.path, job: receivingJob)];
        receiveCompleted = true;
        var paths = staged;
        var names = staged
            .map((path) => File(path).uri.pathSegments.last)
            .toList();
        final sizes = await Future.wait(
          staged.map((path) => File(path).length()),
        );
        if (Platform.isAndroid && isFile) {
          try {
            if (cancelling) throw StateError('transfer cancelled');
            setState(() {
              contentProcessing = ContentProcessing.savingReceived;
              activity = t.savingFile;
              transferProgress = null;
            });
            final saved = await receivedStorage.saveReceived(staged);
            paths = saved.map((entry) => entry.reference).toList();
            names = saved.map((entry) => entry.name).toList();
            for (final source in staged) {
              try {
                await File(source).delete();
              } catch (e) {
                debugPrint('Could not remove temporary file: $e');
              }
            }
          } catch (e) {
            if (cancelling ||
                (e is PlatformException && e.code == 'cancelled')) {
              for (final source in staged) {
                try {
                  await File(source).delete();
                } catch (_) {}
              }
              rethrow;
            }
            savedPrivately = true;
            debugPrint('Could not save to selected location: $e');
          } finally {
            contentProcessing = null;
          }
        }
        final path = paths.first;
        String? textPreview;
        String? receivedLink;
        String? receivedText;
        if (kind == TransferKind.text || typedText) {
          final text = await File(path).readAsString();
          receivedText = text;
          textPreview = String.fromCharCodes(text.trim().runes.take(120));
          receivedLink = detectHttpLink(text);
          if (!typedText) {
            if (Platform.isAndroid) {
              await clipboardChannel.invokeMethod<void>('writeText', {
                'text': text,
              });
            } else {
              await Clipboard.setData(ClipboardData(text: text));
            }
          }
        }
        var clipboardFailed = false;
        if (kind == TransferKind.image || isFile) {
          try {
            if (kind == TransferKind.image) {
              await DesktopPlatform.writeClipboardImage(
                await File(path).readAsBytes(),
              );
            } else if (Platform.isAndroid) {
              await clipboardChannel.invokeMethod<void>('writeFiles', {
                'paths': paths,
              });
            } else if (!await Pasteboard.writeFiles(paths)) {
              throw StateError(t.writeClipboardFailed);
            }
          } catch (e) {
            clipboardFailed = true;
            debugPrint('Could not copy received content: $e');
          }
        }
        final folderArchive =
            kind == TransferKind.file &&
            info.name.endsWith(folderArchiveSuffix);
        var historySaved = true;
        try {
          for (var i = 0; i < paths.length; i++) {
            await _addHistory(
              TransferRecord(
                name: isFile ? names[i] : contentName,
                peer: senderName(),
                time: DateTime.now(),
                kind: kind.historyKind(info.name),
                received: true,
                path: paths[i],
                size: sizes[i],
                preview: textPreview,
              ),
            );
          }
        } catch (e) {
          historySaved = false;
          debugPrint('Could not save history: $e');
        }
        _recordDiagnostic('received', info.sender);
        if (mounted) {
          final message = !historySaved
              ? t.historySaveFailed
              : savedPrivately && clipboardFailed
              ? '${t.savedPrivately} ${t.writeClipboardFailed}'
              : savedPrivately
              ? t.savedPrivately
              : clipboardFailed
              ? t.writeClipboardFailed
              : typedText
              ? t.textReceived
              : kind == TransferKind.batch
              ? t.filesReceived(paths.length)
              : kind == TransferKind.file
              ? t.received(names.first)
              : t.clipboardReceived;
          final openable =
              !typedText &&
              (kind == TransferKind.file ||
                  kind == TransferKind.clipboardFile ||
                  kind == TransferKind.image);
          setState(() {
            contentOperationActive = false;
            activity = message;
            receivedPath = openable ? path : null;
          });
          _finishSystemTransfer(
            message,
            path: openable ? path : null,
            name: names.first,
            url: receivedLink,
            previewTextPath: receivedText != null && receivedLink == null
                ? path
                : null,
            received: true,
          );
          _message(
            message,
            kind: historySaved && !savedPrivately && !clipboardFailed
                ? NoticeKind.success
                : NoticeKind.error,
            actionLabel: t.view,
            onAction: folderArchive
                ? () => _restoreFolder(path)
                : kind == TransferKind.batch
                ? _showHistory
                : openable
                ? () => _openReceived(path)
                : receivedLink != null
                ? () => _openLink(receivedLink!)
                : receivedText != null
                ? () => _showTextContent(receivedText!)
                : () => _openReceived(path),
          );
          if (wasBackground &&
              autoAccept &&
              !foreground &&
              !Platform.isAndroid) {
            try {
              await backgroundChannel.invokeMethod<void>('offer', {
                'title': 'Vela',
                'message': message,
                'focus': false,
              });
            } catch (e) {
              debugPrint('Could not show completion notification: $e');
            }
          } else if (backgroundNotified) {
            try {
              await backgroundChannel.invokeMethod<void>('clearOffer');
            } catch (_) {}
          }
        }
      } catch (e) {
        if (!identical(node, n)) return;
        if (backgroundNotified) {
          try {
            await backgroundChannel.invokeMethod<void>('clearOffer');
          } catch (_) {}
        }
        if (!disposed && mounted) {
          if (receivingStarted) {
            setState(() {
              contentOperationActive = false;
              activity = null;
            });
          }
          debugPrint('Receive failed: $e');
          final cancelled =
              cancelling ||
              classifyTransferFailure(e) == TransferFailure.cancelled;
          if (receivingStarted) {
            _recordDiagnostic(
              cancelled ? 'receiveCancelled' : 'receiveFailed',
              diagnosticPeer,
            );
          }
          final message = cancelled
              ? t.transferCancelled
              : transferErrorMessage(e, t);
          if (receivingStarted) _finishSystemTransfer(message);
          _message(
            message,
            kind: cancelled ? NoticeKind.info : NoticeKind.error,
          );
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      } finally {
        if (!receiveCompleted) receivingJob?.cancel();
        if (identical(activeTransfer, receivingJob)) activeTransfer = null;
        if (receivingStarted) _setTransferring(false);
        if (processingOffer) incomingOffersPending--;
      }
    }
  }

  void _invalidatePeerMembership(
    PeerState old,
    PeerState updated,
    Set<String> changed,
  ) {
    presenceController.membershipChanging(old, updated, changed);
    for (final id in changed) {
      if (updated.peers.containsKey(id)) continue;
      try {
        outgoingPairings[id]?.cancel();
      } catch (e) {
        debugPrint('Could not cancel pairing: $e');
      }
      incomingPairings[id]?.cancel();
    }
  }

  void _restorePeerSessions(PeerState state) =>
      presenceController.restoreSessions(state);

  void _publishPeerState(PeerState state, Set<String> changed) {
    presenceController.membershipPublished(state, changed);
    if (mounted)
      setState(
        () => selectedPeers.removeWhere((id) => !state.peers.containsKey(id)),
      );
  }

  void _settlePeerMembership(Set<String> changed) =>
      presenceController.membershipSettled(changed);

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

  Future<void> _removeUnpaired(VelaNode source, String id, Object session) =>
      _pairingTransition(id, () async {
        bool current() =>
            mounted &&
            identical(node, source) &&
            identical(presenceController.sessionFor(id), session) &&
            peers.containsKey(id) &&
            !incomingPairings.containsKey(id) &&
            !outgoingPairings.containsKey(id);
        if (!current()) return;
        var claimed = false;
        try {
          claimed = await source.revokeIfUnpaired(peerId: id);
          if (!claimed) return;
          var removed = false;
          final name = peerState.displayName(id);
          await pairedDevices!.update((state) {
            if (!current()) return state;
            removed = true;
            return state.remove(id);
          });
          if (removed && mounted) {
            _message(t.peerUnpaired(name));
          } else if (mounted && identical(node, source)) {
            await _syncTrustNow(source);
          }
        } catch (e) {
          debugPrint('Could not update unpaired device: $e');
          if (claimed && mounted && identical(node, source)) {
            try {
              await _syncTrustNow(source);
            } catch (error) {
              debugPrint('Could not restore trusted devices: $error');
            }
          }
        }
      });

  Future<void> _requestPairing(String id) async {
    if (shuttingDown || updates.installing) return;
    final activeNode = node;
    if (activeNode == null ||
        changingRelay ||
        outgoingPairings.containsKey(id)) {
      return;
    }
    final attempt = OutgoingPairingSession(id);
    outgoingPairings[id] = attempt;
    final cancel = attempt.cancelled;
    if (!incomingPairings.containsKey(id)) _replacePeerSession(id);
    final session = presenceController.sessionFor(id);
    var saved = false;
    Future<DeviceInfo>? request;
    OutgoingPairing? handle;
    try {
      await _pairingTransition(id, () => activeNode.beginPairing(peerId: id));
      if (cancel.isCompleted || !identical(node, activeNode)) return;
      handle = await activeNode.beginOutgoingPairing(peerId: id);
      if (cancel.isCompleted || !identical(node, activeNode)) {
        handle.cancel();
        return;
      }
      attempt.handle = handle;
      request = handle.request(name: deviceName, deviceType: deviceType);
      final info = await Future.any<DeviceInfo?>([
        request,
        cancel.future.then((_) => null),
      ]);
      if (info == null ||
          cancel.isCompleted ||
          !identical(node, activeNode) ||
          !identical(presenceController.sessionFor(id), session)) {
        return;
      }
      await pairedDevices!.update((state) {
        if (cancel.isCompleted ||
            !identical(node, activeNode) ||
            !identical(presenceController.sessionFor(id), session)) {
          return state;
        }
        saved = true;
        return state.add(id, info.name, info.deviceType);
      });
      if (saved) {
        await _syncTrustNow(activeNode);
        if (cancel.isCompleted ||
            !identical(node, activeNode) ||
            !identical(presenceController.sessionFor(id), session)) {
          saved = false;
          return;
        }
      }
      if (saved && mounted) {
        unawaited(presenceController.readSnapshot());
        _message(t.addedPeer(info.name), kind: NoticeKind.success);
      }
    } catch (e) {
      saved = false;
      debugPrint('Pairing failed: $e');
      if (mounted && !cancel.isCompleted) {
        _message(
          classifyTransferFailure(e) == TransferFailure.pairingDeclined
              ? t.pairDeclined
              : t.pairFailed,
          kind: NoticeKind.error,
        );
      }
    } finally {
      attempt.arbitration.complete(saved);
      if (!saved) {
        try {
          handle?.cancel();
        } catch (e) {
          debugPrint('Could not cancel pairing: $e');
        }
      }
      if (request != null) {
        try {
          await request;
        } catch (_) {}
      }
      if (identical(outgoingPairings[id], attempt)) {
        outgoingPairings.remove(id);
      }
      try {
        await _finishPairing(activeNode, id);
      } catch (e) {
        debugPrint('Could not finish pairing: $e');
      }
    }
  }

  Future<void> _addDevice() async {
    if (shuttingDown || updates.installing) return;
    if (outgoingPairingUiActive || contentOperationActive || changingRelay) {
      return;
    }
    final id = await showDialog<String>(
      context: context,
      builder: (_) => const AddDeviceDialog(),
    );
    if (id == null || node == null || changingRelay || !mounted) return;
    if (id == node!.id()) {
      _message(t.cannotAddSelf, kind: NoticeKind.error);
      return;
    }
    if (outgoingPairings.containsKey(id) || incomingPairings.containsKey(id)) {
      _message(t.pairConflict, kind: NoticeKind.error);
      return;
    }
    setState(() => outgoingPairingUiActive = true);
    activePairingPeer = id;
    try {
      await _requestPairing(id);
    } finally {
      activePairingPeer = null;
      if (mounted) {
        setState(() => outgoingPairingUiActive = false);
        unawaited(presenceController.readSnapshot());
      }
    }
  }

  Future<void> _cancelPairing() async {
    final id = activePairingPeer;
    if (id == null) return;
    outgoingPairings[id]?.cancel();
  }

  Future<void> _confirmAndRemovePeer(String id) async {
    if (!peers.containsKey(id)) return;
    final name = peerState.displayName(id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
        title: Text(t.removeDevicesQuestion(ids.length)),
        content: Text(t.removeDevicesBody),
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

  Widget _presenceIcon(String id) {
    if (visiblePresenceChecks.contains(id)) {
      return Tooltip(
        message: t.checking,
        child: Semantics(
          label: t.checking,
          child: Icon(
            Icons.circle_outlined,
            key: const ValueKey('device-presence-check'),
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final reachable = presence[id] == PeerPresence.reachable;
    final label = reachable ? t.reachable : t.unreachable;
    final colors = Theme.of(context).colorScheme;
    final color = reachable ? Colors.green : colors.error;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Icon(Icons.circle, size: 12, color: color),
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

  Future<String?> _choosePeer() async {
    if (peers.isEmpty) return null;
    if (peers.length == 1) return peers.keys.first;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                t.chooseDevice,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final peer in peers.keys)
                    ListTile(
                      leading: Icon(_deviceIcon(peer)),
                      title: Text(
                        peerState.displayName(peer),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _presenceIcon(peer),
                      onTap: () => Navigator.pop(context, peer),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendPendingAndroidShare() async {
    final share = pendingShare;
    if (!mounted ||
        share == null ||
        identical(share, handledAndroidShare) ||
        node == null ||
        changingRelay ||
        peers.isEmpty ||
        contentOperationActive ||
        outgoingPairingUiActive ||
        awaitingOfferDecision) {
      return;
    }
    handledAndroidShare = share;
    final id = await _choosePeer();
    if (changingRelay && identical(pendingShare, share)) {
      handledAndroidShare = null;
      return;
    }
    if (!mounted ||
        id == null ||
        !peers.containsKey(id) ||
        !identical(pendingShare, share)) {
      return;
    }
    await _sendShare(id, peerState.displayName(id), share);
  }

  Future<void> _chooseAndSend({
    bool clipboard = false,
    bool media = false,
  }) async {
    final id = await _choosePeer();
    if (id == null || !mounted || !peers.containsKey(id)) return;
    if (media) {
      try {
        final uris =
            await const MethodChannel('vela/files')
                .invokeListMethod<String>('pickMedia') ??
            [];
        if (!mounted || uris.isEmpty || !peers.containsKey(id)) return;
        if (uris.length > 100) {
          _message(t.tooManyFiles, kind: NoticeKind.error);
          return;
        }
        if (contentOperationActive) {
          _message(t.transferBusy, kind: NoticeKind.error);
          return;
        }
        await _sendShare(
          id,
          peerState.displayName(id),
          PendingShare(uris: uris),
        );
      } catch (e) {
        debugPrint('Media selection failed: $e');
        if (mounted) _message(t.mediaPickFailed, kind: NoticeKind.error);
      }
    } else {
      await _prepareAndSend(
        id,
        peerState.displayName(id),
        clipboard ? _prepareClipboard : _pickFiles,
        clipboard: clipboard,
      );
    }
  }

  Future<void> _composeAndSendText() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _TextComposeDialog(),
    );
    if (text == null || !mounted) return;
    final id = await _choosePeer();
    if (utf8.encode(text).length > 1024 * 1024) {
      if (mounted) _message(t.textTooLarge, kind: NoticeKind.error);
      return;
    }
    if (id != null && mounted && peers.containsKey(id)) {
      await _sendShare(
        id,
        peerState.displayName(id),
        PendingShare(text: text, typed: true),
      );
    }
  }

  Future<void> _chooseAndSendFolder() async {
    if (shuttingDown || updates.installing) return;
    final id = await _choosePeer();
    if (id == null || !mounted || !peers.containsKey(id)) return;
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
    if (source == null ||
        !mounted ||
        !peers.containsKey(id) ||
        shuttingDown ||
        updates.installing) {
      return;
    }
    if (contentOperationActive || node == null) {
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
        peerState.displayName(id),
        _createSendSession(PreparedTransfer(paths: [path], ownedPaths: [path])),
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
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => SafeArea(
        child: ListTileTheme(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          minLeadingWidth: 24,
          horizontalTitleGap: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(_deviceIcon(id)),
                title: Text(
                  peerState.displayName(id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(switch (peerTypes[id]) {
                  'mobile' => t.mobile,
                  'tablet' => t.tablet,
                  'desktop' => t.desktop,
                  _ => t.device,
                }),
                trailing: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(child: _presenceIcon(id)),
                ),
              ),
              if (peerState.aliases.containsKey(id))
                ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: Text(t.systemDeviceName),
                  subtitle: Text(
                    peers[id]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.fingerprint_rounded),
                title: Text(t.deviceCode),
                subtitle: Text(
                  id.length > 16
                      ? '${id.substring(0, 8)}…${id.substring(id.length - 8)}'
                      : id,
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
                title: Text(t.rename),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              if (peerState.aliases.containsKey(id))
                ListTile(
                  leading: const Icon(Icons.restore_rounded),
                  title: Text(t.useDeviceName),
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
  }

  String _relayTokenKey(String url) => runtime.relayTokenKey(url);

  bool get canRestartNode =>
      !changingRelay &&
      !contentOperationActive &&
      activeSendOperations == 0 &&
      !outgoingPairingUiActive &&
      !awaitingOfferDecision &&
      incomingOffersPending == 0 &&
      incomingPairings.isEmpty &&
      outgoingPairings.isEmpty;

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
      if (mounted && Platform.isAndroid) unawaited(_sendPendingAndroidShare());
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
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.myDevice),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.showDeviceCode),
                const SizedBox(height: 12),
                Center(
                  child: QrImageView(
                    data: 'vela:1:$id',
                    size: 192,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  id,
                  key: const ValueKey('device-id'),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: id));
              Navigator.pop(context);
              _message(t.deviceCodeCopied, kind: NoticeKind.success);
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(t.deviceCode),
          ),
        ],
      ),
    );
  }

  Future<void> _prepareAndSend(
    String id,
    String name,
    Future<PreparedTransfer?> Function() prepare, {
    bool clipboard = false,
    PendingShare? share,
  }) async {
    if (node == null ||
        contentOperationActive ||
        changingRelay ||
        shuttingDown ||
        updates.installing)
      return;
    PreparedTransfer? content;
    activeSendOperations++;
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
    } finally {
      activeSendOperations--;
    }
    if (content != null) await _send(id, name, _createSendSession(content));
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
        ownedPaths: [file.path],
        kind: kind,
        fromClipboard: clipboard,
        share: share,
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
        ownedPaths: paths,
        kind: kind,
        fromClipboard: clipboard,
        share: share,
      );
    } catch (_) {
      if (paths.isNotEmpty) {
        await _cleanupPrepared(
          PreparedTransfer(paths: paths, ownedPaths: paths),
        );
      }
      rethrow;
    }
  }

  Future<PreparedTransfer> _prepareShare(PendingShare share) {
    if (share.paths != null) {
      return Future.value(PreparedTransfer(paths: share.paths!, share: share));
    }
    if (share.uris != null || share.uri != null) {
      return _materializeUris(share.uris ?? [share.uri!], share: share);
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
    );
  }

  Future<void> _sendShare(String id, String name, PendingShare share) =>
      _prepareAndSend(id, name, () => _prepareShare(share), share: share);

  Future<void> _cleanupPrepared(PreparedTransfer content) async {
    try {
      await content.cleanup();
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

  Future<void> _discardSend(SendSession session) async {
    try {
      await session.discard();
    } catch (e) {
      debugPrint('Could not remove temporary content: $e');
    }
  }

  Future<void> _send(String id, String name, SendSession session) async {
    final content = session.content;
    final share = content.share;
    var transferStarted = false;
    TransferJob? sendingJob;
    var sendCompleted = false;
    String? resultMessage;
    var resultKind = NoticeKind.success;
    SendRetry? retry;
    activeSendOperations++;
    try {
      if (!mounted) return;
      if (node == null ||
          contentOperationActive ||
          changingRelay ||
          shuttingDown ||
          updates.installing) {
        throw StateError(t.transferBusy);
      }
      if (Platform.isAndroid &&
          share != null &&
          identical(pendingShare, share)) {
        setState(() => pendingShare = null);
      }
      final path = content.paths.first;
      if (!await File(path).exists()) throw StateError(t.fileUnavailable);
      if (!mounted) return;
      if (node == null ||
          contentOperationActive ||
          changingRelay ||
          shuttingDown ||
          updates.installing) {
        throw StateError(t.transferBusy);
      }
      final contentName = switch (content.kind) {
        TransferKind.text => t.clipboardText,
        TransferKind.typedText => t.textContent,
        TransferKind.image => t.clipboardImage,
        _ when content.paths.length > 1 => t.filesCount(content.paths.length),
        _ => File(path).uri.pathSegments.last,
      };
      sendingJob = _beginTransfer(
        target: name,
        contentName: contentName,
        peerType: peerTypes[id],
      );
      setState(() {
        contentOperationActive = true;
        activity = t.connectingTo(name);
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
          if (identical(pendingShare, share)) pendingShare = null;
        });
        unawaited(presenceController.readSnapshot());
        resultMessage = message;
      }
      try {
        await session.complete();
      } catch (e) {
        debugPrint('Could not release sent content: $e');
      }
    } catch (e) {
      debugPrint('Send failed: $e');
      if (mounted) {
        setState(() => activity = null);
        final cancelled =
            cancelling ||
            classifyTransferFailure(e) == TransferFailure.cancelled;
        if (transferStarted)
          _recordDiagnostic(cancelled ? 'sendCancelled' : 'sendFailed', id);
        resultMessage = cancelled
            ? t.transferCancelled
            : sendErrorMessage(
                e,
                transferStarted: transferStarted,
                clipboard: content.fromClipboard,
                shared: share != null,
                translations: t,
              );
        resultKind = cancelled ? NoticeKind.info : NoticeKind.error;
        if (!cancelled && transferStarted && !sendCompleted)
          retry = session.allowRetry();
      }
    } finally {
      activeSendOperations--;
      if (!sendCompleted) sendingJob?.cancel();
      if (identical(activeTransfer, sendingJob)) activeTransfer = null;
      if (transferStarted) _setTransferring(false);
      if (retry == null) await _discardSend(session);
      if (mounted) {
        if (transferStarted) {
          setState(() => contentOperationActive = false);
          _finishSystemTransfer(resultMessage);
        }
        if (resultMessage != null) {
          final retryOffer = retry;
          final notice = _message(
            resultMessage,
            kind: resultKind,
            actionLabel: retryOffer == null ? null : t.retry,
            onAction: retryOffer == null
                ? null
                : () {
                    final next = retryOffer.take();
                    if (next != null) unawaited(_send(id, name, next));
                  },
          );
          if (retryOffer != null) {
            unawaited(
              notice!.closed.then((_) => retryOffer.dismiss()).catchError((
                Object e,
              ) {
                debugPrint('Could not release abandoned content: $e');
              }),
            );
          }
        }
      } else if (retry != null) {
        await _discardSend(session);
      }
    }
  }

  Future<void> _addHistory(TransferRecord record) => historyStore.add(record);

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

  Future<void> _showTextContent(String text) async {
    final link = detectHttpLink(text);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(t.historyText)),
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
    if (record.path == null || !await _receivedExists(record.path!)) {
      _message(t.historyMissing, kind: NoticeKind.error);
      return;
    }
    if (record.kind.canRestoreFolder) {
      await _restoreFolder(record.path!);
      return;
    }
    if (!record.kind.isText) {
      await _openReceived(record.path!);
      return;
    }
    try {
      final text = await File(record.path!).readAsString();
      if (!mounted) return;
      await _showTextContent(text);
    } catch (_) {
      if (mounted) _message(t.openFailed, kind: NoticeKind.error);
    }
  }

  Future<void> _exportHistory(TransferRecord record) async {
    if (record.path == null || !await _receivedExists(record.path!)) {
      _message(t.historyMissing, kind: NoticeKind.error);
      return;
    }
    try {
      if (await receivedStorage.export(record.path!, record.name)) {
        _message(t.savedFile, kind: NoticeKind.success);
      }
    } catch (e) {
      debugPrint('Export failed: $e');
      if (mounted) _message(t.saveFileFailed, kind: NoticeKind.error);
    }
  }

  void _showHistory() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TransferHistoryPage(
          records: historyStore.records,
          open: _openHistory,
          export: _exportHistory,
          remove: _removeHistory,
          openFolder: () => receivedStorage.openFolder(),
          reveal: (record) async {
            if (record.path == null || !await _receivedExists(record.path!)) {
              throw StateError(t.historyMissing);
            }
            await receivedStorage.openFolder(reference: record.path);
          },
        ),
      ),
    );
  }

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _message(
    String message, {
    NoticeKind kind = NoticeKind.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    lastMessage = message;
    return mounted
        ? showNotice(
            context,
            message,
            kind: kind,
            actionLabel: actionLabel,
            onAction: onAction,
          )
        : null;
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
    unawaited(runtime.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final page = Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final headerButtonWidth = math.min(
              44.0,
              math.max(0.0, (viewport.maxWidth - 48 - 8) / 3),
            );
            final toolbarActions = <String>[
              if (peers.isNotEmpty) ...['add', 'refresh', 'view', 'select'],
              if (node != null) ...['device', 'history'],
            ];
            final toolbarSlots = ((viewport.maxWidth - 48 - 112 - 44) / 44)
                .floor()
                .clamp(0, toolbarActions.length);
            final visibleActions = toolbarActions.take(toolbarSlots).toSet();
            Widget toolbarSlot(String action, Widget button) {
              if (!visibleActions.contains(action)) {
                return const SizedBox.shrink();
              }
              if (MediaQuery.disableAnimationsOf(context)) return button;
              return TweenAnimationBuilder<double>(
                key: ValueKey('toolbar-fade-$action'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                builder: (_, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                child: button,
              );
            }

            final wide = viewport.maxWidth >= 700;
            final compactHeader =
                wide && viewport.maxHeight < 500 && !Platform.isMacOS;
            final headerTop = Platform.isMacOS
                ? 44.0
                : compactHeader
                ? 4.0
                : 24.0;
            final headerBottom = compactHeader ? 4.0 : 12.0;
            final deviceHeight =
                viewport.maxHeight - headerTop - 48 - headerBottom;
            if (node != null && automaticGraph == null) {
              automaticGraph = viewport.maxWidth >= 640 && deviceHeight >= 360;
            }
            final showingGraph =
                deviceView == 'graph' ||
                (deviceView == null && (automaticGraph ?? false));

            final actions = <(String, String, IconData, VoidCallback)>[
              (
                'send-file',
                t.files,
                Icons.insert_drive_file_outlined,
                () => _chooseAndSend(),
              ),
              (
                'send-folder',
                t.folder,
                Icons.folder_outlined,
                _chooseAndSendFolder,
              ),
              if (Platform.isAndroid)
                (
                  'send-media',
                  t.media,
                  Icons.photo_library_outlined,
                  () => _chooseAndSend(media: true),
                ),
              (
                'send-text',
                t.textContent,
                Icons.edit_outlined,
                _composeAndSendText,
              ),
              (
                'send-clipboard',
                t.clipboard,
                Icons.content_paste_go_rounded,
                () => _chooseAndSend(clipboard: true),
              ),
            ];

            List<Widget> devices() => [
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
                            padding: const EdgeInsets.only(bottom: 32),
                            child: DeviceGraph(
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
                              enabled:
                                  !contentOperationActive &&
                                  !outgoingPairingUiActive,
                              onTap: (id) => selectingPeers
                                  ? _togglePeerSelection(id)
                                  : pendingShare == null
                                  ? _showDeviceDetails(id)
                                  : _sendShare(
                                      id,
                                      peerState.displayName(id),
                                      pendingShare!,
                                    ),
                              onLongPress: _togglePeerSelection,
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
                            leading: Icon(
                              _deviceIcon(id),
                              color: colors.primary,
                            ),
                            title: Text(
                              peerState.displayName(id),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: selectingPeers
                                ? Semantics(
                                    label: peerState.displayName(id),
                                    child: Checkbox(
                                      value: selectedPeers.contains(id),
                                      onChanged:
                                          contentOperationActive ||
                                              outgoingPairingUiActive
                                          ? null
                                          : (_) => _togglePeerSelection(id),
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _presenceIcon(id),
                                      const SizedBox(width: 14),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                            onLongPress:
                                contentOperationActive ||
                                    outgoingPairingUiActive
                                ? null
                                : () => _togglePeerSelection(id),
                            onTap:
                                contentOperationActive ||
                                    outgoingPairingUiActive
                                ? null
                                : () => selectingPeers
                                      ? _togglePeerSelection(id)
                                      : pendingShare == null
                                      ? _showDeviceDetails(id)
                                      : _sendShare(
                                          id,
                                          peerState.displayName(id),
                                          pendingShare!,
                                        ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (!showingGraph)
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ];

            return CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(24, headerTop, 24, headerBottom),
                  sliver: SliverToBoxAdapter(
                    child: IconButtonTheme(
                      data: IconButtonThemeData(
                        style: IconButton.styleFrom(
                          minimumSize: Size(headerButtonWidth, 48),
                          fixedSize: Size(headerButtonWidth, 48),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (selectingPeers) ...[
                            IconButton(
                              tooltip: t.cancel,
                              onPressed: () => setState(() {
                                selectedPeers.clear();
                                selectingPeers = false;
                              }),
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
                              onPressed: () => setState(
                                () => selectedPeers.addAll(peers.keys),
                              ),
                              icon: const Icon(Icons.select_all_rounded),
                            ),
                            IconButton(
                              tooltip: t.removeDevice,
                              onPressed:
                                  contentOperationActive ||
                                      outgoingPairingUiActive ||
                                      selectedPeers.isEmpty
                                  ? null
                                  : _removeSelectedPeers,
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ] else ...[
                            Expanded(
                              child: Text(
                                t.devices,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            SizedBox(
                              width: math.min(
                                16,
                                math.max(0, viewport.maxWidth - 64),
                              ),
                            ),
                            toolbarSlot(
                              'refresh',
                              IconButton(
                                key: const ValueKey('refresh-devices'),
                                tooltip: checkingPeers
                                    ? t.checking
                                    : t.refreshDevices,
                                onPressed: checkingPeers
                                    ? null
                                    : () => presenceController.probePeers(
                                        userInitiated: true,
                                      ),
                                icon: checkingPeers
                                    ? const SizedBox(
                                        key: ValueKey(
                                          'manual-refresh-progress',
                                        ),
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.refresh_rounded),
                              ),
                            ),
                            toolbarSlot(
                              'view',
                              IconButton(
                                key: const ValueKey('toggle-device-view'),
                                tooltip: showingGraph
                                    ? t.showList
                                    : t.showGraph,
                                onPressed: () =>
                                    _toggleDeviceView(showingGraph),
                                icon: Icon(
                                  showingGraph
                                      ? Icons.view_list_rounded
                                      : Icons.hub_outlined,
                                ),
                              ),
                            ),
                            toolbarSlot(
                              'select',
                              IconButton(
                                key: const ValueKey('select-devices'),
                                tooltip: t.selectDevices,
                                onPressed:
                                    contentOperationActive ||
                                        outgoingPairingUiActive
                                    ? null
                                    : () =>
                                          setState(() => selectingPeers = true),
                                icon: const Icon(Icons.checklist_rounded),
                              ),
                            ),
                            toolbarSlot(
                              'device',
                              IconButton(
                                tooltip: t.myDevice,
                                onPressed: _showMyDeviceDialog,
                                icon: const Icon(Icons.qr_code_rounded),
                              ),
                            ),
                            toolbarSlot(
                              'history',
                              IconButton(
                                key: const ValueKey('transfer-history'),
                                tooltip: t.transferHistory,
                                onPressed: _showHistory,
                                icon: const Icon(Icons.history_rounded),
                              ),
                            ),
                            toolbarSlot(
                              'add',
                              IconButton(
                                key: const ValueKey('add-device'),
                                tooltip: t.addDevice,
                                onPressed:
                                    node == null ||
                                        outgoingPairingUiActive ||
                                        contentOperationActive
                                    ? null
                                    : _addDevice,
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ),
                            if (node != null &&
                                visibleActions.length == toolbarActions.length)
                              IconButton(
                                key: const ValueKey('home-settings'),
                                tooltip: t.settings,
                                onPressed: _showSettings,
                                icon: const Icon(Icons.settings_outlined),
                              )
                            else if (node != null)
                              PopupMenuButton<String>(
                                key: const ValueKey('home-more'),
                                tooltip: MaterialLocalizations.of(context)
                                    .showMenuTooltip,
                                icon: const Icon(Icons.more_vert_rounded),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                onSelected: (value) {
                                  switch (value) {
                                    case 'add':
                                      _addDevice();
                                    case 'view':
                                      _toggleDeviceView(showingGraph);
                                    case 'select':
                                      setState(() => selectingPeers = true);
                                    case 'refresh':
                                      presenceController.probePeers(
                                        userInitiated: true,
                                      );
                                    case 'device':
                                      _showMyDeviceDialog();
                                    case 'history':
                                      _showHistory();
                                    case 'settings':
                                      _showSettings();
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (toolbarActions.contains('add') &&
                                      !visibleActions.contains('add'))
                                    PopupMenuItem(
                                      value: 'add',
                                      key: const ValueKey('add-device'),
                                      enabled:
                                          !outgoingPairingUiActive &&
                                          !contentOperationActive,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.add_rounded,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(t.addDevice),
                                        ],
                                      ),
                                    ),
                                  if (toolbarActions.contains('refresh') &&
                                      !visibleActions.contains('refresh'))
                                    PopupMenuItem(
                                      value: 'refresh',
                                      key: const ValueKey('refresh-devices'),
                                      enabled: !checkingPeers,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.refresh_rounded,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            checkingPeers
                                                ? t.checking
                                                : t.refreshDevices,
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (toolbarActions.contains('view') &&
                                      !visibleActions.contains('view'))
                                    PopupMenuItem(
                                      value: 'view',
                                      key: const ValueKey('toggle-device-view'),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            showingGraph
                                                ? Icons.view_list_rounded
                                                : Icons.hub_outlined,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            showingGraph
                                                ? t.showList
                                                : t.showGraph,
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (toolbarActions.contains('select') &&
                                      !visibleActions.contains('select'))
                                    PopupMenuItem(
                                      value: 'select',
                                      key: const ValueKey('select-devices'),
                                      enabled:
                                          !contentOperationActive &&
                                          !outgoingPairingUiActive,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.checklist_rounded,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(t.selectDevices),
                                        ],
                                      ),
                                    ),
                                  if (toolbarActions.contains('device') &&
                                      !visibleActions.contains('device'))
                                    PopupMenuItem(
                                      value: 'device',
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.qr_code_rounded,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(t.myDevice),
                                        ],
                                      ),
                                    ),
                                  if (toolbarActions.contains('history') &&
                                      !visibleActions.contains('history'))
                                    PopupMenuItem(
                                      value: 'history',
                                      child: Row(
                                        key: const ValueKey('transfer-history'),
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.history_rounded,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(t.transferHistory),
                                        ],
                                      ),
                                    ),
                                  PopupMenuItem(
                                    value: 'settings',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.settings_outlined,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(t.settings),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ],
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
                          Text(
                            t.startupFailed,
                            style: TextStyle(color: colors.error),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () {
                                  setState(() => error = null);
                                  unawaited(_retryFromUI());
                                },
                                child: Text(t.retry),
                              ),
                              if (Platform.isAndroid ||
                                  Platform.isMacOS ||
                                  DesktopPlatform.isWindowsOrLinux)
                                TextButton(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => BackgroundSettingsPage(
                                        profile: widget.profile,
                                        onChanged: _backgroundPresenceChanged,
                                      ),
                                    ),
                                  ),
                                  child: Text(t.backgroundReceiving),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else if (node == null)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (peers.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 72),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 152,
                              height: 112,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned(
                                    left: 8,
                                    top: 8,
                                    child: Container(
                                      width: 106,
                                      height: 78,
                                      decoration: BoxDecoration(
                                        color: const Color(0xffe9ecfc),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Icon(
                                        Icons.laptop_mac_rounded,
                                        size: 46,
                                        color: colors.primary,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 8,
                                    bottom: 4,
                                    child: Container(
                                      width: 57,
                                      height: 74,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(19),
                                        border: Border.all(
                                          color: const Color(0xffe5e8f4),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.phone_android_rounded,
                                        size: 32,
                                        color: colors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              t.connectDevices,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t.emptyDevices,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              key: const ValueKey('add-device'),
                              onPressed:
                                  outgoingPairingUiActive ||
                                      contentOperationActive
                                  ? null
                                  : _addDevice,
                              icon: const Icon(Icons.add_rounded),
                              label: Text(t.addDevice),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: math.max(
                        wide
                            ? actions.length * 40.0 + (actions.length - 1) * 6
                            : 220.0,
                        deviceHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: HomeResponsiveLayout(
                          wide: wide,
                          actions: [
                            for (final (key, label, icon, action) in actions)
                              FilledButton.tonal(
                                key: ValueKey(key),
                                onPressed:
                                    contentOperationActive ||
                                        outgoingPairingUiActive ||
                                        selectingPeers
                                    ? null
                                    : action,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) =>
                                      constraints.maxWidth < 90
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              icon,
                                              size: math.min(
                                                18,
                                                constraints.maxWidth,
                                              ),
                                            ),
                                            Flexible(
                                              child: Text(
                                                label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(icon, size: 20),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                          ],
                          devices: CustomScrollView(
                            key: const ValueKey('home-devices'),
                            physics: const ClampingScrollPhysics(),
                            slivers: devices(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar:
          outgoingPairingUiActive ||
              (contentOperationActive && activity != null)
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
                        child: Text(
                          cancelling
                              ? t.cancelling
                              : contentOperationActive && activity != null
                              ? activity!
                              : t.connectingPair,
                          key: const ValueKey('activity-status'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (contentOperationActive && transferPath.isNotEmpty)
                        Tooltip(
                          message: transferPath == 'direct'
                              ? t.directConnection
                              : transferPath == 'mixed'
                              ? t.mixedConnection
                              : t.relayConnection,
                          child: Icon(
                            transferPath == 'direct'
                                ? Icons.link_rounded
                                : transferPath == 'mixed'
                                ? Icons.swap_horiz_rounded
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
                          onPressed: activePairingPeer == null
                              ? null
                              : _cancelPairing,
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
          : pendingShare != null
          ? ActivityNotice(
              child: Row(
                children: [
                  const Icon(Icons.share_rounded, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      pendingShare!.hasFiles ? t.selectedFile : t.selectedText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: t.cancelShare,
                    onPressed: () {
                      final share = pendingShare;
                      setState(() => pendingShare = null);
                      if (share != null) unawaited(_releaseShare(share));
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            )
          : null,
    );
    return PopScope(
      canPop: !selectingPeers,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selectingPeers) {
          setState(() {
            selectedPeers.clear();
            selectingPeers = false;
          });
        }
      },
      child: Platform.isMacOS || DesktopPlatform.isWindowsOrLinux
          ? DropTarget(
              enable:
                  node != null &&
                  !contentOperationActive &&
                  !outgoingPairingUiActive &&
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
  const _TextComposeDialog();
  @override
  State<_TextComposeDialog> createState() => _TextComposeDialogState();
}

class _TextComposeDialogState extends State<_TextComposeDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(t.sendText),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: 4,
          maxLines: 12,
          decoration: InputDecoration(hintText: t.enterText),
          onChanged: (_) => setState(() {}),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: controller.text.isEmpty
              ? null
              : () => Navigator.pop(context, controller.text),
          child: Text(t.sendText),
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
