import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'paired_devices.dart';
import 'peer_state.dart';
import 'presence_probe.dart';
import 'src/rust/api/node.dart';

enum PeerPresence { reachable, unavailable }

enum _RefreshRequest { snapshot, probe }

enum PresenceNetworkEvent { configurationChanged, systemWake }

class PresenceController extends ChangeNotifier {
  PresenceController({
    required this.pairingActive,
    required this.canPersistInfo,
    required this.recordDiagnostic,
    required this.removeUnpaired,
  });

  final bool Function(String) pairingActive;
  final bool Function() canPersistInfo;
  final void Function(String, [String?]) recordDiagnostic;
  final Future<void> Function(VelaNode, String, Object) removeUnpaired;

  VelaNode? _node;
  PairedDevices? _devices;
  bool _disposed = false;
  Object _lifetime = Object();
  Future<void> _monitoringTail = Future.value();
  VelaNode? _monitoringNode;
  bool _monitoringEnabled = false;
  bool _monitoringRequested = false;
  Timer? _monitoringRetry;
  Timer? _snapshotRetry;
  BigInt? _expiredRevision;
  BigInt _appliedRevision = BigInt.zero;
  Object _snapshotToken = Object();
  bool _probing = false;
  bool _checkingPeers = false;
  _RefreshRequest? _queuedRefresh;
  Completer<void>? _refreshInterrupt;
  int _pendingSystemWakes = 0;
  final Map<String, PeerPresence> _values = {};
  final Set<String> _visibleChecks = {};
  final Set<String> _snapshotChecks = {};
  final Map<String, int> _generations = {};
  final Map<String, Future<void>> _probes = {};
  final Set<String> _trustPending = {};
  final Set<String> _updatingInfo = {};
  final Map<String, ({VelaNode node, Object relationship, DeviceInfo info})>
  _pendingInfo = {};
  final Map<String, Timer> _infoRetries = {};

  bool get _alive => !_disposed;
  Map<String, String> get _peers => _devices?.state.peers ?? const {};
  Map<String, String> get _peerTypes => _devices?.state.types ?? const {};
  Map<String, PeerPresence> get values => UnmodifiableMapView(_values);
  Set<String> get visibleChecks => UnmodifiableSetView(_visibleChecks);
  bool get checkingPeers => _checkingPeers;
  bool get probing => _probing;
  bool get monitorEnabled => _monitoringEnabled;
  int get pendingSystemWakes => _pendingSystemWakes;

  bool _current(VelaNode source) => _alive && identical(_node, source);

  void _change(VoidCallback action) {
    if (!_alive) return;
    action();
    notifyListeners();
  }

  void attach(PairedDevices devices) {
    reset();
    _node = devices.node;
    _devices = devices;
    _visibleChecks.addAll(_peers.keys);
    _checkingPeers = _peers.isNotEmpty;
    unawaited(_watchSnapshotUpdates(devices.node));
    notifyListeners();
  }

  void pairingStarted(String id) {
    _snapshotToken = Object();
    _infoRetries.remove(id)?.cancel();
    _pendingInfo.remove(id);
  }

  void membershipChanging(Set<String> changed) {
    _snapshotToken = Object();
    _snapshotChecks.removeAll(changed);
    for (final id in changed) {
      _values.remove(id);
      _generations[id] = (_generations[id] ?? 0) + 1;
      _probes.remove(id);
      _infoRetries.remove(id)?.cancel();
      _pendingInfo.remove(id);
    }
    _trustPending.addAll(changed);
    _change(() => _visibleChecks.addAll(changed.where(_peers.containsKey)));
    if (_refreshInterrupt?.isCompleted == false) _refreshInterrupt!.complete();
  }

  void membershipPublished(PeerState state, Set<String> changed) {
    _change(() {
      _visibleChecks.removeWhere((id) => !state.peers.containsKey(id));
      _visibleChecks.addAll(changed.where(state.peers.containsKey));
      if (_visibleChecks.isEmpty) _checkingPeers = false;
    });
  }

  void membershipSettled(Set<String> changed) {
    _trustPending.removeAll(changed);
    if (changed.isEmpty || !_alive || _node == null) return;
    _snapshotToken = Object();
    unawaited(readCurrentSnapshot());
    if (_checkingPeers) unawaited(requestPeerProbes());
  }

  Future<void> readCurrentSnapshot() async {
    final source = _node;
    if (source != null &&
        _alive &&
        _monitoringRequested &&
        _pendingSystemWakes == 0) {
      await _readCurrentSnapshot(source);
    }
  }

  Future<void> syncMonitoring({required bool enabled}) {
    _monitoringRequested = enabled;
    _prepareMonitoring();
    return _syncMonitoring();
  }

  void requestMonitoring({required bool enabled}) {
    _monitoringRequested = enabled;
    _requestMonitoring();
  }

  void resumeInfoUpdates() {
    final source = _node;
    if (!_alive || source == null) return;
    for (final entry in _pendingInfo.entries.toList()) {
      final next = entry.value;
      if (identical(next.node, source)) {
        _queueInfo(source, entry.key, next.relationship, next.info);
      }
    }
    unawaited(readCurrentSnapshot());
  }

  Future<void> handleNetworkEvent(PresenceNetworkEvent event) async {
    final resumed = event == PresenceNetworkEvent.systemWake;
    final source = _node;
    if (source == null || !_alive) return;
    if (resumed) {
      _pendingSystemWakes++;
      _snapshotToken = Object();
      if (_monitoringRequested && _peers.isNotEmpty) {
        _change(() {
          _checkingPeers = true;
          _visibleChecks.addAll(_peers.keys);
        });
      }
    }
    for (final id in _probes.keys) {
      _generations[id] = (_generations[id] ?? 0) + 1;
    }
    _probes.clear();
    if (_refreshInterrupt?.isCompleted == false) {
      if (_checkingPeers) _queuedRefresh = _RefreshRequest.probe;
      _refreshInterrupt!.complete();
    }
    try {
      if (resumed) {
        await retryNetworkChangeAfterWake(
          () => source.networkChange(resumed: true),
          shouldRetry: () => _current(source),
          onFailure: () {
            if (!_current(source)) return;
            _change(() {
              for (final id in _peers.keys) {
                _values[id] = PeerPresence.unavailable;
              }
              _checkingPeers = false;
              _visibleChecks.clear();
            });
          },
        );
      } else {
        await source.networkChange(resumed: false);
      }
    } finally {
      if (resumed && _current(source)) {
        _pendingSystemWakes--;
        if (_pendingSystemWakes == 0) {
          _snapshotToken = Object();
          _queuedRefresh = null;
          unawaited(readCurrentSnapshot());
          unawaited(requestPeerProbes());
        }
      }
    }
    if (!resumed && _current(source)) unawaited(readCurrentSnapshot());
  }

  void reset() {
    _lifetime = Object();
    _snapshotToken = Object();
    _node = null;
    _devices = null;
    _monitoringNode = null;
    _monitoringEnabled = false;
    _monitoringRetry?.cancel();
    _snapshotRetry?.cancel();
    for (final timer in _infoRetries.values) {
      timer.cancel();
    }
    _infoRetries.clear();
    _pendingInfo.clear();
    _updatingInfo.clear();
    _expiredRevision = null;
    _appliedRevision = BigInt.zero;
    _monitoringTail = Future.value();
    if (_refreshInterrupt?.isCompleted == false) _refreshInterrupt!.complete();
    _refreshInterrupt = null;
    _probes.clear();
    _generations.clear();
    _values.clear();
    _visibleChecks.clear();
    _snapshotChecks.clear();
    _trustPending.clear();
    _probing = false;
    _checkingPeers = false;
    _queuedRefresh = null;
    _pendingSystemWakes = 0;
  }

  @override
  void dispose() {
    if (_disposed) return;
    reset();
    _disposed = true;
    super.dispose();
  }

  void _setPresence(String id, PeerPresence value) {
    if (_values[id] == value) return;
    _values[id] = value;
    recordDiagnostic(
      value == PeerPresence.reachable ? 'online' : 'offline',
      id,
    );
  }

  void _queueInfo(
    VelaNode source,
    String id,
    Object relationship,
    DeviceInfo info,
  ) {
    _infoRetries.remove(id)?.cancel();
    _pendingInfo[id] = (node: source, relationship: relationship, info: info);
    if (!_updatingInfo.add(id)) return;
    final lifetime = _lifetime;
    unawaited(() async {
      try {
        while (_alive &&
            identical(lifetime, _lifetime) &&
            _pendingInfo.containsKey(id)) {
          final next = _pendingInfo.remove(id)!;
          bool current() =>
              _current(next.node) &&
              _devices!.isCurrentRelationship(id, next.relationship);
          if (!current()) continue;
          if (!canPersistInfo()) {
            _pendingInfo.putIfAbsent(id, () => next);
            break;
          }
          try {
            await _devices!.update(
              (state) => current() && canPersistInfo()
                  ? state.updateInfo(id, next.info.name, next.info.deviceType)
                  : state,
            );
          } catch (e) {
            debugPrint('Could not save device information: $e');
            if (current() && canPersistInfo()) {
              _pendingInfo.putIfAbsent(id, () => next);
              _infoRetries[id] = Timer(const Duration(seconds: 1), () {
                _infoRetries.remove(id);
                final retry = _pendingInfo.remove(id);
                if (retry != null) {
                  _queueInfo(retry.node, id, retry.relationship, retry.info);
                }
              });
              break;
            }
          }
        }
      } finally {
        if (identical(lifetime, _lifetime)) _updatingInfo.remove(id);
      }
    }());
  }

  void _applySnapshot(VelaNode source, PresenceSnapshot snapshot) {
    if (!_alive ||
        !identical(_node, source) ||
        !_monitoringRequested ||
        !identical(_monitoringNode, source) ||
        !_monitoringEnabled ||
        _pendingSystemWakes > 0 ||
        snapshot.revision < _appliedRevision) {
      return;
    }
    _appliedRevision = snapshot.revision;
    final now = proofClockNowNs();
    final clockUnavailable = now == (BigInt.one << 64) - BigInt.one;
    final changes = <String, PeerPresence>{};
    final checked = <String>{};
    final resolved = <String>{};
    final metadata = <({String id, Object relationship, DeviceInfo info})>[];
    final unpaired = <({String id, Object relationship})>[];
    final expired = <String>{};
    var retryClock = false;
    for (final peer in snapshot.peers) {
      final id = peer.peerId;
      final relationship = _devices!.relationshipFor(id);
      if (!_peers.containsKey(id) ||
          _trustPending.contains(id) ||
          relationship == null ||
          pairingActive(id)) {
        continue;
      }
      if (peer.unpaired) {
        unpaired.add((id: id, relationship: relationship));
        continue;
      }
      final info = peer.info;
      if (clockUnavailable && info != null) retryClock = true;
      if (!clockUnavailable &&
          info != null &&
          (peer.proofValidUntilNs == null || now >= peer.proofValidUntilNs!)) {
        expired.add(id);
        continue;
      }
      final live =
          info != null &&
          peer.proofValidUntilNs != null &&
          now < peer.proofValidUntilNs!;
      final next = live ? PeerPresence.reachable : PeerPresence.unavailable;
      if (_values[id] != next) changes[id] = next;
      resolved.add(id);
      if (_visibleChecks.contains(id) &&
          (!_checkingPeers ||
              (_snapshotChecks.contains(id) && !_probes.containsKey(id)))) {
        checked.add(id);
      }
      if (live &&
          (_updatingInfo.contains(id) ||
              _infoRetries.containsKey(id) ||
              _peers[id] != info.name ||
              _peerTypes[id] != info.deviceType)) {
        metadata.add((id: id, relationship: relationship, info: info));
      }
    }
    if (changes.isNotEmpty ||
        checked.isNotEmpty ||
        expired.isNotEmpty ||
        resolved.any(_snapshotChecks.contains)) {
      _change(() {
        changes.forEach(_setPresence);
        _snapshotChecks.removeAll(resolved);
        _snapshotChecks.addAll(expired);
        _visibleChecks.removeAll(checked);
        _visibleChecks.addAll(expired);
        if (_visibleChecks.isEmpty) _checkingPeers = false;
      });
    }
    for (final value in metadata) {
      _queueInfo(source, value.id, value.relationship, value.info);
    }
    for (final value in unpaired) {
      unawaited(removeUnpaired(source, value.id, value.relationship));
    }
    if (expired.isNotEmpty) {
      final retryImmediately = _expiredRevision != snapshot.revision;
      _expiredRevision = snapshot.revision;
      _scheduleSnapshotRead(
        source,
        retryImmediately ? Duration.zero : const Duration(milliseconds: 100),
      );
    } else {
      _expiredRevision = null;
      if (retryClock) {
        _scheduleSnapshotRead(source, const Duration(milliseconds: 250));
      }
    }
  }

  Future<void> _readCurrentSnapshot(VelaNode source) async {
    final snapshotToken = _snapshotToken;
    try {
      final snapshot = await source.waitPresenceSnapshot(
        afterRevision: BigInt.zero,
      );
      if (identical(snapshotToken, _snapshotToken)) {
        _applySnapshot(source, snapshot);
      }
    } catch (e) {
      if (_alive && identical(_node, source)) {
        debugPrint('Could not read device status: $e');
        _scheduleSnapshotRead(source, const Duration(milliseconds: 250));
      }
    }
  }

  void _scheduleSnapshotRead(VelaNode source, Duration delay) {
    _snapshotRetry?.cancel();
    _snapshotRetry = Timer(delay, () {
      if (_alive && identical(_node, source)) {
        unawaited(_readCurrentSnapshot(source));
      }
    });
  }

  Future<void> _watchSnapshotUpdates(VelaNode source) async {
    final lifetime = _lifetime;
    var revision = BigInt.zero;
    while (_current(source) && identical(lifetime, _lifetime)) {
      try {
        final snapshotToken = _snapshotToken;
        final snapshot = await source.waitPresenceSnapshot(
          afterRevision: revision,
        );
        if (!_alive || !identical(_node, source)) return;
        if (!identical(snapshotToken, _snapshotToken)) {
          revision = BigInt.zero;
          continue;
        }
        if (snapshot.revision > revision) revision = snapshot.revision;
        _applySnapshot(source, snapshot);
      } catch (e) {
        if (!_alive || !identical(_node, source)) return;
        debugPrint('Device status stream failed: $e');
        revision = BigInt.zero;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _syncMonitoring() async {
    final source = _node;
    if (!_alive || source == null) return;
    final previous = _monitoringTail;
    final complete = Completer<void>();
    _monitoringTail = complete.future;
    await previous;
    try {
      if (!_alive || !identical(_node, source)) return;
      final enabled = _monitoringRequested;
      await source.setPresenceMonitoring(enabled: enabled);
      if (!_alive || !identical(_node, source)) return;
      _monitoringNode = source;
      _monitoringEnabled = enabled;
      if (enabled && _monitoringRequested)
        unawaited(_readCurrentSnapshot(source));
    } finally {
      complete.complete();
    }
  }

  void _requestMonitoring() {
    _prepareMonitoring();
    final source = _node;
    _monitoringRetry?.cancel();
    unawaited(
      _syncMonitoring()
          .then((_) {
            if (_alive &&
                source != null &&
                identical(_node, source) &&
                identical(_monitoringNode, source) &&
                _monitoringEnabled &&
                _monitoringRequested &&
                _checkingPeers &&
                !_probing) {
              unawaited(requestPeerProbes());
            }
          })
          .catchError((Object e) {
            debugPrint('Could not update device monitoring: $e');
            if (_alive && source != null && identical(_node, source)) {
              _monitoringRetry = Timer(
                const Duration(seconds: 1),
                _requestMonitoring,
              );
            }
          }),
    );
  }

  void _prepareMonitoring() {
    _snapshotToken = Object();
    if (!_alive || _monitoringRequested) return;
    _monitoringEnabled = false;
    _change(() {
      _values.clear();
      _snapshotChecks.clear();
      _visibleChecks.addAll(_peers.keys);
      _checkingPeers = false;
    });
  }

  Future<void> requestPeerProbes({bool userInitiated = false}) async {
    final activeNode = _node;
    if (!_alive ||
        !_monitoringRequested ||
        activeNode == null ||
        _peers.isEmpty ||
        _pendingSystemWakes > 0) {
      return;
    }
    if (userInitiated) recordDiagnostic('manualRefresh');
    if (_probing) {
      _queuedRefresh = _RefreshRequest.probe;
      if (_refreshInterrupt?.isCompleted == false) {
        _refreshInterrupt!.complete();
      }
      _change(() {
        _checkingPeers = true;
        _visibleChecks.addAll(_peers.keys);
      });
      return;
    }

    Future<void> probe(String id) async {
      final relationship = _devices!.relationshipFor(id);
      final generation = (_generations[id] ?? 0) + 1;
      _generations[id] = generation;
      bool current() =>
          _alive &&
          identical(_node, activeNode) &&
          _peers.containsKey(id) &&
          _devices!.isCurrentRelationship(id, relationship) &&
          _generations[id] == generation;
      try {
        await activeNode.checkPeerFresh(peerId: id);
      } catch (_) {
      } finally {
        if (current()) await _readCurrentSnapshot(activeNode);
        if (current() &&
            _visibleChecks.contains(id) &&
            !_snapshotChecks.contains(id)) {
          _change(() {
            _visibleChecks.remove(id);
            if (_visibleChecks.isEmpty) _checkingPeers = false;
          });
        }
      }
    }

    _change(() {
      _probing = true;
      _checkingPeers = true;
      _visibleChecks.addAll(_peers.keys);
    });
    final interrupt = Completer<void>();
    _refreshInterrupt = interrupt;
    final ids = _peers.keys.toList();
    final deferred = <String>{};
    Future<void> worker(String id) async {
      if (!_alive ||
          !_monitoringRequested ||
          interrupt.isCompleted ||
          !_peers.containsKey(id)) {
        return;
      }
      if (_trustPending.contains(id)) {
        deferred.add(id);
        return;
      }
      if (interrupt.isCompleted) return;
      final task = probe(id);
      _probes[id] = task;
      unawaited(
        task.whenComplete(() {
          if (!identical(_probes[id], task)) return;
          _probes.remove(id);
          if (_alive &&
              _visibleChecks.contains(id) &&
              !_snapshotChecks.contains(id) &&
              !_trustPending.contains(id) &&
              _pendingSystemWakes == 0) {
            _change(() {
              _visibleChecks.remove(id);
              if (_visibleChecks.isEmpty) _checkingPeers = false;
            });
          }
        }),
      );
      await Future.any([task, interrupt.future]);
    }

    try {
      await Future.any([_monitoringTail, interrupt.future]);
      if (!_alive ||
          !identical(_node, activeNode) ||
          !_monitoringRequested ||
          interrupt.isCompleted) {
        return;
      }
      if (!identical(_monitoringNode, activeNode) || !_monitoringEnabled) {
        deferred.addAll(ids);
        _requestMonitoring();
        return;
      }
      await Future.wait(ids.map(worker));
    } finally {
      if (identical(_refreshInterrupt, interrupt)) {
        _refreshInterrupt = null;
        if (_alive && _pendingSystemWakes > 0) {
          _probing = false;
        } else if (_alive) {
          if (_checkingPeers || _visibleChecks.isNotEmpty) {
            _change(() {
              _probing = false;
              if (!interrupt.isCompleted) {
                _visibleChecks.removeWhere(
                  (id) =>
                      !_trustPending.contains(id) &&
                      !deferred.contains(id) &&
                      !_snapshotChecks.contains(id),
                );
                if (_visibleChecks.isEmpty) _checkingPeers = false;
              } else if (_visibleChecks.isEmpty) {
                _checkingPeers = false;
              }
            });
          } else {
            _probing = false;
          }
          if (interrupt.isCompleted) {
            _queuedRefresh ??= _RefreshRequest.snapshot;
          }
          final queued = _queuedRefresh;
          _queuedRefresh = null;
          if (queued == _RefreshRequest.probe) {
            unawaited(requestPeerProbes());
          } else if (queued == _RefreshRequest.snapshot) {
            unawaited(readCurrentSnapshot());
          }
        } else {
          _probing = false;
        }
      }
    }
  }
}
