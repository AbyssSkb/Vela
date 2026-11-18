import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela/paired_devices.dart';
import 'package:vela/pairing_session.dart';
import 'package:vela/peer_confirmation.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/src/rust/api/node.dart';

import 'support/fakes.dart' show FakeNode, MemoryPeerStore, peerId;

class IncomingPairOffer implements IncomingRequest {
  IncomingPairOffer(this.onAccept);
  final void Function() onAccept;
  final closed = Completer<void>();

  @override
  Future<void> waitForConnectionClose() => closed.future;

  @override
  Future<void> acceptPair({
    required String name,
    required String deviceType,
  }) async {
    onAccept();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const phone = DeviceInfo(name: 'Phone', deviceType: 'mobile');
  late FakeNode node;
  late MemoryPeerStore store;
  late PairedDevices devices;
  late PairingSessions sessions;
  setUp(() {
    node = FakeNode()..peerTrusted = false;
    store = MemoryPeerStore();
    devices = PairedDevices(
      node: node,
      store: store,
      initialState: PeerState(),
    );
    sessions = PairingSessions(
      currentDevices: () => devices,
      localInfo: () => const DeviceInfo(name: 'Laptop', deviceType: 'desktop'),
      onPairingStarted: (_) {},
    );
  });
  tearDown(() => devices.close());

  test(
    'incoming approval persists and trusts the peer before replying',
    () async {
      var replied = false;
      final offer = IncomingPairOffer(() {
        expect(PeerState.decode(store.saved!).peers[peerId], 'Phone');
        expect(node.peerTrusted, isTrue);
        replied = true;
      });
      final accepted = await sessions.receive(
        devices,
        offer,
        peerId,
        phone,
        confirm: (_) async => PeerDecision.accepted,
      );
      expect(accepted, isTrue);
      expect(replied, isTrue);
      expect(sessions.isActive, isFalse);
    },
  );

  test(
    'cancelling a pending decision leaves no trusted relationship',
    () async {
      final prompting = Completer<void>();
      final offer = IncomingPairOffer(() => fail('unexpected pairing reply'));
      final result = sessions.receive(
        devices,
        offer,
        peerId,
        phone,
        confirm: (closed) async {
          prompting.complete();
          await closed;
          return PeerDecision.connectionClosed;
        },
      );
      await prompting.future;
      sessions.cancel(peerId);
      sessions.cancel(peerId);
      expect(await result, isFalse);
      expect(store.saved, isNull);
      expect(devices.pairingRevisionFor(peerId), isNull);
      expect(sessions.isActive, isFalse);
    },
  );

  test('crossed outgoing attempts choose one direction', () async {
    final a = PairingCollisionArbitration('b');
    final b = PairingCollisionArbitration('a');
    expect(
      await a.decideIncoming(localId: 'a', incomingId: 'c'),
      PairingCollision.proceed,
    );
    var settled = false;
    final decision = a.decideIncoming(localId: 'a', incomingId: 'b').then((
      value,
    ) {
      settled = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    expect(
      await b.decideIncoming(localId: 'b', incomingId: 'a'),
      PairingCollision.proceed,
    );
    a.complete(true);
    expect(await decision, PairingCollision.duplicate);
  });

  test(
    'failed outgoing permits incoming and does not hide a genuine refusal',
    () async {
      final attempt = PairingCollisionArbitration('b');
      final decision = attempt.decideIncoming(localId: 'a', incomingId: 'b');
      attempt.complete(false);
      expect(await decision, PairingCollision.proceed);
    },
  );

  testWidgets(
    'unresolved collision is declined after two seconds even if outgoing later succeeds',
    (tester) async {
      final attempt = PairingCollisionArbitration('b');
      PairingCollision? result;
      final decision = attempt
          .decideIncoming(localId: 'a', incomingId: 'b')
          .then((value) => result = value);
      await tester.pump(const Duration(milliseconds: 1999));
      expect(result, isNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(result, PairingCollision.busy);
      attempt.complete(true);
      await decision;
      expect(result, PairingCollision.busy);
    },
  );
}
