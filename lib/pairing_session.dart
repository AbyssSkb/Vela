import 'dart:async';

import 'package:flutter/foundation.dart';

import 'paired_devices.dart';
import 'peer_confirmation.dart' show PeerDecision;
import 'src/rust/api/node.dart';

enum PairingCollision { proceed, duplicate, busy }

class PairingCollisionArbitration {
  PairingCollisionArbitration(this.peerId);

  final String peerId;
  final Completer<bool> _finished = Completer<bool>();

  Future<PairingCollision> decideIncoming({
    required String localId,
    required String incomingId,
  }) async {
    if (incomingId != peerId || localId.compareTo(incomingId) >= 0) {
      return PairingCollision.proceed;
    }
    try {
      return await _finished.future.timeout(const Duration(seconds: 2))
          ? PairingCollision.duplicate
          : PairingCollision.proceed;
    } on TimeoutException {
      return PairingCollision.busy;
    }
  }

  void complete(bool success) {
    if (!_finished.isCompleted) _finished.complete(success);
  }
}

class _PairingAttempt {
  _PairingAttempt(this.devices, this.id, this.pairingRevision);

  final PairedDevices devices;
  final String id;
  final Object? pairingRevision;
  final cancelled = Completer<void>();

  bool get current =>
      !cancelled.isCompleted &&
      devices.isCurrentPairingRevision(id, pairingRevision);

  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
  }

  Future<bool> commit(DeviceInfo peer) async {
    final saved = await devices.pair(
      id,
      peer.name,
      peer.deviceType,
      when: () => current,
    );
    if (saved && current) await devices.syncTrust();
    return saved;
  }
}

class _OutgoingAttempt extends _PairingAttempt {
  _OutgoingAttempt(PairedDevices devices, String id, Object? pairingRevision)
    : arbitration = PairingCollisionArbitration(id),
      super(devices, id, pairingRevision);

  final PairingCollisionArbitration arbitration;
  OutgoingPairing? handle;

  @override
  void cancel() {
    super.cancel();
    handle?.cancel();
  }
}

class PairingSessions {
  PairingSessions({
    required this.currentDevices,
    required this.localInfo,
    required this.onPairingStarted,
  });

  final PairedDevices? Function() currentDevices;
  final DeviceInfo Function() localInfo;
  final void Function(String) onPairingStarted;
  final _outgoing = <String, _OutgoingAttempt>{};
  final _incoming = <String, _PairingAttempt>{};
  final _transitions = <String, Future<void>>{};
  bool _confirming = false;

  bool get isActive => _outgoing.isNotEmpty || _incoming.isNotEmpty;
  bool isActiveFor(String id) =>
      _outgoing.containsKey(id) || _incoming.containsKey(id);

  void cancelOutgoing(String id) => _outgoing[id]?.cancel();

  void cancel(String id) {
    _incoming[id]?.cancel();
    try {
      cancelOutgoing(id);
    } catch (e) {
      debugPrint('Could not cancel pairing: $e');
    }
  }

  // Same-peer isolation, revocation and release must finish in arrival order.
  Future<T> serialize<T>(String id, Future<T> Function() action) {
    final previous = _transitions[id] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final done = result.then<void>((_) {}, onError: (Object _) {});
    _transitions[id] = done;
    return result.whenComplete(() {
      if (identical(_transitions[id], done)) _transitions.remove(id);
    });
  }

  Object? _relationship(PairedDevices devices, String id) {
    if (isActiveFor(id)) return devices.pairingRevisionFor(id);
    final pairingRevision = devices.beginPairingRevision(id);
    onPairingStarted(id);
    return pairingRevision;
  }

  Future<void> _isolate(_PairingAttempt attempt) => serialize(
    attempt.id,
    () => attempt.devices.node.beginPairing(peerId: attempt.id),
  );

  Future<void> _releaseIfIdle(PairedDevices devices, String id) =>
      serialize(id, () async {
        if (!identical(devices, currentDevices()) || isActiveFor(id)) return;
        try {
          await devices.syncTrust();
          if (!identical(devices, currentDevices())) return;
          await devices.node.endPairing(peerId: id);
          if (!isActiveFor(id) && !devices.state.containsDevice(id)) {
            devices.forgetPairingRevision(id);
          }
        } catch (e) {
          debugPrint('Could not finish pairing: $e');
          if (identical(devices, currentDevices())) {
            Timer(
              const Duration(seconds: 1),
              () => unawaited(_releaseIfIdle(devices, id)),
            );
          }
        }
      });

  Future<DeviceInfo?> request(PairedDevices devices, String id) async {
    if (_outgoing.containsKey(id)) return null;
    final attempt = _OutgoingAttempt(devices, id, _relationship(devices, id));
    _outgoing[id] = attempt;
    var saved = false;
    Future<DeviceInfo>? reply;
    try {
      await _isolate(attempt);
      if (!attempt.current) return null;
      final handle = await devices.node.beginOutgoingPairing(peerId: id);
      attempt.handle = handle;
      if (!attempt.current) return null;
      final local = localInfo();
      reply = handle.request(name: local.name, deviceType: local.deviceType);
      final peer = await Future.any<DeviceInfo?>([
        reply,
        attempt.cancelled.future.then((_) => null),
      ]);
      if (peer == null || !attempt.current) return null;
      saved = await attempt.commit(peer) && attempt.current;
      return saved ? peer : null;
    } catch (_) {
      if (attempt.cancelled.isCompleted) return null;
      rethrow;
    } finally {
      attempt.arbitration.complete(saved);
      if (!saved) {
        try {
          attempt.handle?.cancel();
        } catch (e) {
          debugPrint('Could not cancel pairing: $e');
        }
      }
      if (reply != null) {
        try {
          await reply;
        } catch (_) {}
      }
      _outgoing.remove(id);
      await _releaseIfIdle(devices, id);
    }
  }

  Future<bool> receive(
    PairedDevices devices,
    IncomingRequest offer,
    String id,
    DeviceInfo peer, {
    required Future<PeerDecision> Function(Future<void> closed) confirm,
  }) async {
    if (_incoming.containsKey(id) || _incoming.length >= 8) {
      await offer.declinePairConflict();
      return false;
    }
    final attempt = _PairingAttempt(devices, id, _relationship(devices, id));
    _incoming[id] = attempt;
    try {
      final approved = await _approveIncoming(attempt, offer, peer, confirm);
      if (!approved || !attempt.current) {
        return false;
      }
      final local = localInfo();
      await offer.acceptPair(name: local.name, deviceType: local.deviceType);
      return true;
    } finally {
      _incoming.remove(id);
      await _releaseIfIdle(devices, id);
    }
  }

  Future<bool> _approveIncoming(
    _PairingAttempt attempt,
    IncomingRequest offer,
    DeviceInfo peer,
    Future<PeerDecision> Function(Future<void> closed) confirm,
  ) async {
    final id = attempt.id;
    try {
      await _isolate(attempt);
      final outgoing = _outgoing[id];
      if (outgoing != null) {
        final decision = await outgoing.arbitration.decideIncoming(
          localId: attempt.devices.node.id(),
          incomingId: id,
        );
        if (!attempt.current) return false;
        if (decision == PairingCollision.duplicate) {
          await offer.decline();
          return false;
        }
        if (decision == PairingCollision.busy) {
          await offer.declinePairConflict();
          return false;
        }
      }
      if (!attempt.current) return false;
      if (_confirming) {
        await offer.declinePairConflict();
        return false;
      }
      _confirming = true;
      final PeerDecision decision;
      try {
        decision = await confirm(
          Future.any([
            offer.waitForConnectionClose(),
            attempt.cancelled.future,
          ]),
        );
      } finally {
        _confirming = false;
      }
      if (!attempt.current || decision == PeerDecision.connectionClosed) {
        return false;
      }
      if (decision == PeerDecision.declined) {
        await offer.decline();
        return false;
      }
      if (!await attempt.commit(peer)) {
        await offer.declinePairConflict();
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Could not process pairing request: $e');
      return false;
    }
  }
}
