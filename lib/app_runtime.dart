import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'paired_devices.dart';
import 'peer_state.dart';
import 'peer_store.dart';
import 'relay_settings.dart' show useCustomRelays;
import 'src/rust/api/node.dart';

class RuntimeReady {
  const RuntimeReady({
    required this.node,
    required this.preferences,
    required this.deviceName,
    required this.systemDeviceName,
    required this.deviceType,
    required this.legacyStateDetected,
  });

  final VelaNode node;
  final SharedPreferences preferences;
  final String deviceName, systemDeviceName, deviceType;
  final bool legacyStateDetected;
}

/// Owns the node and its persisted trust state through startup and shutdown.
class AppRuntime {
  AppRuntime({
    required this.profile,
    required this.testIdentity,
    required this.recordDiagnostic,
    required this.onStartupFailure,
    required this.onMembershipChanging,
    required this.onStateChanged,
    required this.onMembershipWriteFinished,
  });

  static const secureStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: 'Vela',
      usesDataProtectionKeychain: false,
    ),
  );
  static const _deviceChannel = MethodChannel('vela/device');

  final String profile;
  final bool testIdentity;
  final void Function(String) recordDiagnostic;
  final void Function(Object) onStartupFailure;
  bool startupCleanupComplete = true;
  final void Function(PeerState, Set<String>) onMembershipChanging;
  final void Function(PeerState, Set<String>) onStateChanged;
  final void Function(Set<String>) onMembershipWriteFinished;

  VelaNode? get node => _node;
  PairedDevices? get devices => _devices;
  VelaNode? _node;
  PairedDevices? _devices;
  Future<RuntimeReady?>? _starting;
  RuntimeReady? _ready;
  Future<void>? _closing;
  int _generation = 0;
  bool _disposed = false;

  String relayTokenKey(String url) =>
      'relay_token_${profile}_${base64Url.encode(utf8.encode(url))}';

  Future<RuntimeReady?> start() {
    if (_disposed) return Future.value();
    final closing = _closing;
    if (closing != null) return closing.then((_) => start());
    if (_ready != null) return Future.value(_ready);
    if (_starting != null) return _starting!;
    startupCleanupComplete = true;
    final generation = _generation;
    final attempt = _open(generation);
    _starting = attempt;
    return attempt.whenComplete(() {
      if (identical(_starting, attempt)) _starting = null;
    });
  }

  Future<RuntimeReady?> _open(int generation) async {
    PeerStore? openingStore;
    VelaNode? openingNode;
    var stage = 'preferences';
    void entering(String next) {
      stage = next;
      recordDiagnostic('startup_${next}_begin');
    }

    void completed() => recordDiagnostic('startup_${stage}_done');

    try {
      entering('preferences');
      final preferences = await SharedPreferences.getInstance();
      completed();
      entering('identity');
      final stored = testIdentity
          ? preferences.getString('test_identity_$profile')
          : await secureStorage.read(key: 'identity_$profile');
      final secret = stored == null
          ? await generateSecret()
          : base64Decode(stored);
      if (stored == null) {
        if (testIdentity) {
          await preferences.setString(
            'test_identity_$profile',
            base64Encode(secret),
          );
        } else {
          await secureStorage.write(
            key: 'identity_$profile',
            value: base64Encode(secret),
          );
        }
      }
      completed();
      entering('storeOpen');
      final store = await PeerStore.open(profile: profile);
      openingStore = store;
      completed();
      entering('storeLoad');
      final encoded = await store.load();
      final state = encoded == null ? PeerState() : PeerState.decode(encoded);
      completed();
      entering('deviceInfo');
      Map<String, String>? device;
      try {
        device = await _deviceChannel.invokeMapMethod<String, String>('info');
      } on MissingPluginException {
        device = null;
      }
      final rawName =
          device?['name']?.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim() ??
          '';
      final fallback = Platform.isAndroid
          ? 'Android 设备'
          : Platform.localHostname;
      final systemName = String.fromCharCodes(
        (rawName.isEmpty ? fallback : rawName).runes.take(60),
      );
      final overrideName = preferences
          .getString('device_name_$profile')
          ?.trim();
      final name = overrideName != null && overrideName.isNotEmpty
          ? overrideName
          : testIdentity && profile != 'default'
          ? profile
          : systemName;
      final type = ['mobile', 'tablet', 'desktop'].contains(device?['type'])
          ? device!['type']!
          : Platform.isMacOS || Platform.isLinux || Platform.isWindows
          ? 'desktop'
          : 'other';
      completed();
      final relays =
          preferences.getStringList('custom_relays_$profile') ?? <String>[];
      final custom = useCustomRelays(
        preferences.getBool('custom_relays_enabled_$profile') ?? true,
        relays,
      );
      entering('relayCredentials');
      final tokens = custom
          ? await Future.wait(
              relays.map(
                (url) async =>
                    await secureStorage.read(key: relayTokenKey(url)) ?? '',
              ),
            )
          : <String>[];
      completed();
      entering('node');
      final node = custom
          ? await startNodeWithRelays(
              secret: secret,
              urls: relays,
              tokens: tokens,
            )
          : await startNode(secret: secret);
      openingNode = node;
      completed();
      entering('trust');
      await node.replaceTrustedPeers(trusted: state.deviceIds.toList());
      completed();
      entering('nodeInfo');
      await node.setDeviceInfo(name: name, deviceType: type);
      completed();
      if (_disposed || generation != _generation) return null;
      _node = node;
      _devices = PairedDevices(
        node: node,
        store: store,
        initialState: state,
        onMembershipChanging: onMembershipChanging,
        onStateChanged: onStateChanged,
        onMembershipWriteFinished: onMembershipWriteFinished,
      );
      openingNode = null;
      openingStore = null;
      return _ready = RuntimeReady(
        node: node,
        preferences: preferences,
        deviceName: name,
        systemDeviceName: systemName,
        deviceType: type,
        legacyStateDetected: store.legacyStateDetected,
      );
    } catch (error) {
      recordDiagnostic('startup_${stage}_failed');
      onStartupFailure(error);
      rethrow;
    } finally {
      // Failed and superseded starts keep ownership until both resources close.
      try {
        await openingNode?.close();
      } catch (error) {
        startupCleanupComplete = false;
        debugPrint('Could not close starting node: $error');
      }
      try {
        await openingStore?.close();
      } catch (error) {
        startupCleanupComplete = false;
        debugPrint('Could not close starting store: $error');
      }
    }
  }

  Future<void> close() =>
      _closing ??= _close().whenComplete(() => _closing = null);

  Future<void> _close() async {
    _generation++;
    final opening = _starting;
    final oldNode = _node;
    final oldDevices = _devices;
    _node = null;
    _devices = null;
    _ready = null;
    try {
      await oldDevices?.close();
    } finally {
      try {
        await oldNode?.close();
      } finally {
        if (opening != null) {
          try {
            await opening;
          } catch (_) {
            // The start caller owns its error; shutdown only waits for cleanup.
          }
        }
      }
    }
  }

  Future<void> dispose() {
    _disposed = true;
    return close();
  }
}
