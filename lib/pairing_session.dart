import 'dart:async';

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

class OutgoingPairingSession {
  OutgoingPairingSession(String peerId)
    : arbitration = PairingCollisionArbitration(peerId);

  final PairingCollisionArbitration arbitration;
  final cancelled = Completer<void>();
  OutgoingPairing? handle;

  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
    handle?.cancel();
  }
}

class IncomingPairingSession {
  final cancelled = Completer<void>();

  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
  }
}
