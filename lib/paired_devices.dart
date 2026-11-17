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
    this.onRestore,
    this.onMembershipSettled,
  }) : _state = initialState;

  final VelaNode node;
  final PeerStore store;
  final void Function(PeerState old, PeerState updated, Set<String> changed)?
  onMembershipChanging;
  final void Function(PeerState state, Set<String> changed)? onStateChanged;
  final void Function(PeerState state)? onRestore;
  final void Function(Set<String> changed)? onMembershipSettled;

  PeerState _state;
  PeerState get state => _state;
  Future<void> _tail = Future.value();
  Future<void> get idle => _tail;
  Timer? _trustRetry;
  bool _closed = false;
  Future<void>? _closing;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    if (_closed) return Future.error(StateError('Paired devices are closed'));
    final previous = _tail;
    final complete = Completer<void>();
    _tail = complete.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        complete.complete();
      }
    }();
  }

  Future<void> _setTrust(Iterable<String> ids) =>
      node.replaceTrustedPeers(trusted: ids.toList());

  Future<void> syncTrust() => _enqueue(() async {
    try {
      await _setTrust(_state.peers.keys);
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
          _scheduleTrustSync();
        }),
      );
    });
  }

  Future<bool> update(PeerState Function(PeerState) change) => _enqueue(
    () async {
      final old = _state;
      final updated = change(old);
      if (identical(updated, old)) return false;
      final retained = old.peers.keys.where(updated.peers.containsKey).toList();
      final trustChanged =
          retained.length != old.peers.length ||
          retained.length != updated.peers.length;
      final changed = <String>{...old.peers.keys, ...updated.peers.keys}
        ..removeWhere(
          (id) => old.peers.containsKey(id) == updated.peers.containsKey(id),
        );
      if (!_closed && changed.isNotEmpty) {
        onMembershipChanging?.call(old, updated, changed);
      }
      var persisted = false;
      try {
        if (trustChanged) await _setTrust(retained);
        try {
          await store.save(updated.encode());
          persisted = true;
        } catch (_) {
          if (trustChanged) {
            if (!_closed) onRestore?.call(old);
            await _setTrust(old.peers.keys);
          }
          rethrow;
        }
        _state = updated;
        if (!_closed) onStateChanged?.call(updated, changed);
        if (trustChanged) {
          try {
            await _setTrust(updated.peers.keys);
          } catch (error) {
            debugPrint('Could not sync trusted devices: $error');
            _scheduleTrustSync();
          }
        }
        return true;
      } catch (_) {
        if (!persisted && trustChanged) {
          if (!_closed) onRestore?.call(old);
          _scheduleTrustSync();
        }
        rethrow;
      } finally {
        if (!_closed && changed.isNotEmpty) onMembershipSettled?.call(changed);
      }
    },
  );

  Future<bool> pair(String id, String name, String type) =>
      update((state) => state.add(id, name, type));

  Future<bool> remove(String id) => update((state) => state.remove(id));

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
