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
    this.onMembershipSettled,
  }) : _state = initialState,
       _relationships = {
         for (final id in initialState.peers.keys) id: Object(),
       };

  final VelaNode node;
  final PeerStore store;
  final void Function(PeerState updated, Set<String> changed)?
  onMembershipChanging;
  final void Function(PeerState state, Set<String> changed)? onStateChanged;
  final void Function(Set<String> changed)? onMembershipSettled;

  PeerState _state;
  PeerState get state => _state;
  Future<void> _tail = Future.value();
  Future<void> get idle => _tail;
  Timer? _trustRetry;
  bool _closed = false;
  Future<void>? _closing;

  // An in-flight decision is valid only for the relationship it started under.
  final Map<String, Object> _relationships;
  Object? relationshipFor(String id) => _relationships[id];
  bool isCurrentRelationship(String id, Object? relationship) =>
      !_closed &&
      relationship != null &&
      identical(_relationships[id], relationship);

  Object beginRelationship(String id) => _relationships[id] = Object();
  void forgetRelationship(String id) => _relationships.remove(id);

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
        }),
      );
    });
  }

  Future<bool> update(PeerState Function(PeerState) change) =>
      _enqueue(() async {
        final old = _state;
        final updated = change(old);
        if (identical(updated, old)) return false;
        final before = old.peers.keys.toSet();
        final after = updated.peers.keys.toSet();
        final removed = before.difference(after);
        final added = after.difference(before);
        final changed = {...removed, ...added};
        final trustChanged = changed.isNotEmpty;
        for (final id in removed) {
          _relationships.remove(id);
        }
        if (!_closed && trustChanged)
          onMembershipChanging?.call(updated, changed);
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
                _relationships.putIfAbsent(id, Object.new);
              }
              _scheduleTrustSync();
              if (trustRestricted) await _setTrust(old.peers.keys);
            }
            rethrow;
          }
          _state = updated;
          for (final id in added) {
            _relationships.putIfAbsent(id, Object.new);
          }
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
        } finally {
          if (!_closed && trustChanged) onMembershipSettled?.call(changed);
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
    Object relationship, {
    required bool Function() pairingActive,
  }) async {
    bool current() =>
        isCurrentRelationship(id, relationship) &&
        state.peers.containsKey(id) &&
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
