import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela/paired_devices.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/presence_controller.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/frb_generated.dart';

import 'support/fakes.dart';

class _Devices implements PairedDevices {
  _Devices(this.state);

  @override
  PeerState state;

  @override
  Future<bool> update(PeerState Function(PeerState) change) async {
    final next = change(state);
    final changed = !identical(next, state);
    state = next;
    return changed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

void main() {
  late FakeNode node;
  late PresenceController controller;
  late _Devices devices;

  setUp(() {
    node = FakeNode();
    RustLib.initMock(api: FakeRustApi(node));
    devices = _Devices(
      PeerState(peers: {peerId: 'Phone'}, types: {peerId: 'mobile'}),
    );
    controller = PresenceController(
      pairingActive: (_) => false,
      canPersistInfo: () => true,
      recordDiagnostic: (_, [__]) {},
      removeUnpaired: (_, __, ___) async {},
    );
    controller.attach(node, devices);
  });

  tearDown(() async {
    controller.dispose();
    await node.close();
    RustLib.dispose();
  });

  test('reading a snapshot never starts a network probe', () async {
    await controller.syncMonitoring(enabled: true);
    await controller.readSnapshot();
    expect(node.freshCalls, isEmpty);

    final probe = controller.probePeers(userInitiated: true);
    await _flush();
    expect(node.freshCalls, hasLength(1));
    expect(controller.checkingPeers, isTrue);
    node.fresh.complete(const DeviceInfo(name: 'Phone', deviceType: 'mobile'));
    await probe;

    expect(controller.checkingPeers, isFalse);
    expect(controller.values[peerId], PeerPresence.unavailable);
  });

  test('reset discards a delayed snapshot from the old node', () async {
    await controller.syncMonitoring(enabled: true);
    await _flush();
    node.holdWatch = true;
    node.publish(
      info: const DeviceInfo(name: 'Phone', deviceType: 'mobile'),
      proofValidUntilNs: BigInt.from(9000000000),
    );
    await _flush();
    expect(node.watchHeld, isTrue);

    final old = node;
    node = FakeNode();
    controller.attach(node, devices);
    await controller.syncMonitoring(enabled: true);
    await controller.readSnapshot();
    old.releaseWatch.complete();
    await _flush();

    expect(controller.values[peerId], PeerPresence.unavailable);
    await old.close();
  });

  test(
    'membership interruption does not start another network probe',
    () async {
      await controller.syncMonitoring(enabled: true);
      final probe = controller.probePeers();
      await _flush();
      expect(node.freshCalls, hasLength(1));

      controller.membershipChanging(devices.state, PeerState(), {peerId});
      await probe;
      await _flush();
      expect(node.freshCalls, hasLength(1));

      node.fresh.complete(
        const DeviceInfo(name: 'Phone', deviceType: 'mobile'),
      );
      await _flush();
    },
  );

  test('membership rollback creates a new session identity', () {
    final previousSession = controller.sessionFor(peerId);
    final old = devices.state;
    controller.membershipChanging(old, PeerState(), {peerId});
    expect(controller.sessionFor(peerId), isNull);

    controller.restoreSessions(old);
    expect(controller.sessionFor(peerId), isNotNull);
    expect(identical(controller.sessionFor(peerId), previousSession), isFalse);
    expect(controller.visibleChecks, contains(peerId));
  });
}
