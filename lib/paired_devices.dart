import 'dart:async';

import 'package:flutter/foundation.dart';

import 'peer_state.dart';
import 'peer_store.dart';
import 'src/rust/api/node.dart';

class PairedDevices {
  PairedDevices({
    required this.node,
    required this.store,
    required PeerState initialState,
    this.onMembershipChanging,
    this.onStateChanged,
    this.onMembershipWriteFinished,
  }) : _state = initialState,
       _pairingRevisions = {
         for (final id in initialState.deviceIds) id: Object(),
       };

  final VelaNode node;
  final PeerStore store;
  final void Function(PeerState updated, Set<String> changed)?
  onMembershipChanging;
  final void Function(PeerState state, Set<String> changed)? onStateChanged;
  final void Function(Set<String> changed)? onMembershipWriteFinished;

  PeerState _state;
  PeerState get state => _state;
  Future<void> _tail = Future.value();
  Future<void> get idle => _tail;
  Timer? _trustRetry;
  bool _closed = false;
  Future<void>? _closing;

  // An in-flight decision is valid only for the pairing revision it started under.
  final Map<String, Object> _pairingRevisions;
  Object? pairingRevisionFor(String id) => _pairingRevisions[id];
  bool isCurrentPairingRevision(String id, Object? pairingRevision) =>
      !_closed &&
      pairingRevision != null &&
      identical(_pairingRevisions[id], pairingRevision);

  Object beginPairingRevision(String id) => _pairingRevisions[id] = Object();
  void forgetPairingRevision(String id) => _pairingRevisions.remove(id);

  Future<T> _enqueue<T>(Future<T> Function() action) {
    if (_closed) return Future.error(StateError('Paired devices are closed'));
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _setTrust(Iterable<String> ids) =>
      node.replaceTrustedPeers(trusted: ids.toList());

  Future<void> syncTrust() => _enqueue(() async {
    try {
      await _setTrust(_state.deviceIds);
    } catch (_) {
      _scheduleTrustSync();
      rethrow;
    }
  });

  void _scheduleTrustSync() {
    _trustRetry?.cancel();
    if (_closed) return;
    _trustRetry = Timer(const Duration(seconds: 1), () {
      if (_closed) return;
      unawaited(
        syncTrust().catchError((Object error) {
          debugPrint('Could not sync trusted devices: $error');
        }),
      );
    });
  }

  Future<bool> update(
    PeerState Function(PeerState) change,
  ) => _enqueue(() async {
    final old = _state;
    final updated = change(old);
    if (identical(updated, old)) return false;
    final before = old.deviceIds.toSet();
    final after = updated.deviceIds.toSet();
    final removed = before.difference(after);
    final added = after.difference(before);
    final changed = {...removed, ...added};
    final trustChanged = changed.isNotEmpty;
    for (final id in removed) {
      _pairingRevisions.remove(id);
    }
    if (!_closed && trustChanged) onMembershipChanging?.call(updated, changed);
    try {
      var trustRestricted = false;
      try {
        if (trustChanged) {
          await _setTrust(before.intersection(after));
          trustRestricted = true;
        }
        await store.save(updated.encode());
      } catch (_) {
        if (trustChanged) {
          for (final id in removed) {
            _pairingRevisions.putIfAbsent(id, Object.new);
          }
          _scheduleTrustSync();
          if (trustRestricted) await _setTrust(old.deviceIds);
        }
        rethrow;
      }
      _state = updated;
      for (final id in added) {
        _pairingRevisions.putIfAbsent(id, Object.new);
      }
      if (!_closed) onStateChanged?.call(updated, changed);
      if (trustChanged) {
        try {
          await _setTrust(updated.deviceIds);
        } catch (error) {
          debugPrint('Could not sync trusted devices: $error');
          _scheduleTrustSync();
        }
      }
      return true;
    } finally {
      if (!_closed && trustChanged) onMembershipWriteFinished?.call(changed);
    }
  });

  Future<bool> pair(
    String id,
    String name,
    String type, {
    bool Function()? when,
  }) => update(
    (state) => when == null || when() ? state.add(id, name, type) : state,
  );

  Future<bool> remove(String id) => update((state) => state.remove(id));

  Future<bool> removeIfUnpaired(
    String id,
    Object pairingRevision, {
    required bool Function() pairingActive,
  }) async {
    bool current() =>
        isCurrentPairingRevision(id, pairingRevision) &&
        state.containsDevice(id) &&
        !pairingActive();
    if (!current() || !await node.revokeIfUnpaired(peerId: id)) return false;
    var removed = false;
    try {
      removed = await update((state) => current() ? state.remove(id) : state);
      return removed;
    } finally {
      // A concurrent re-pair may supersede the Rust revocation before the write.
      if (!removed && !_closed) {
        try {
          await syncTrust();
        } catch (error) {
          debugPrint('Could not restore trusted devices: $error');
        }
      }
    }
  }

  Future<bool> updateInfo(String id, String name, String type) =>
      update((state) => state.updateInfo(id, name, type));

  Future<bool> setAlias(String id, String? alias) =>
      update((state) => state.setAlias(id, alias));

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _trustRetry?.cancel();
    await idle;
    await store.close();
  }
}
