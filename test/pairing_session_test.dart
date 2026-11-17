import 'package:vela/pairing_session.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:flutter_test/flutter_test.dart';

class TrackingPairingHandle implements OutgoingPairing {
  int cancellations = 0;

  @override
  void cancel() => cancellations++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('outgoing session owns its cancellation and network handle', () async {
    final session = OutgoingPairingSession('b');
    final handle = TrackingPairingHandle();
    session.handle = handle;

    session.cancel();

    await session.cancelled.future;
    expect(handle.cancellations, 1);
    expect(session.cancelled.isCompleted, isTrue);
    final decision = session.arbitration.decideIncoming(
      localId: 'a',
      incomingId: 'b',
    );
    session.arbitration.complete(false);
    expect(await decision, PairingCollision.proceed);
  });

  test('incoming session cancellation is idempotent', () async {
    final session = IncomingPairingSession();
    session.cancel();
    session.cancel();
    await session.cancelled.future;
    expect(session.cancelled.isCompleted, isTrue);
  });

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
