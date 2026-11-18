import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela/paired_devices.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/presence_controller.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/frb_generated.dart';

import 'support/fakes.dart';

Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

void main() {
  late FakeNode node;
  late PresenceController controller;
  late PairedDevices devices;

  PairedDevices trustedDevices(FakeNode node) => PairedDevices(
    node: node,
    store: MemoryPeerStore(),
    initialState: PeerState(
      peers: {peerId: 'Phone'},
      types: {peerId: 'mobile'},
    ),
    onMembershipChanging: (_, changed) =>
        controller.membershipChanging(changed),
    onStateChanged: controller.membershipPublished,
    onMembershipSettled: controller.membershipSettled,
  );

  setUp(() {
    node = FakeNode();
    RustLib.initMock(api: FakeRustApi(node));
    controller = PresenceController(
      pairingActive: (_) => false,
      canPersistInfo: () => true,
      recordDiagnostic: (_, [__]) {},
      removeUnpaired: (_, __, ___) async {},
    );
    devices = trustedDevices(node);
    controller.attach(devices);
  });

  tearDown(() async {
    controller.dispose();
    await devices.close();
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
    await devices.close();
    node = FakeNode();
    devices = trustedDevices(node);
    controller.attach(devices);
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

      controller.membershipChanging({peerId});
      await probe;
      await _flush();
      expect(node.freshCalls, hasLength(1));

      node.fresh.complete(
        const DeviceInfo(name: 'Phone', deviceType: 'mobile'),
      );
      await _flush();
    },
  );

  test('only a membership change clears a peer’s online status', () async {
    await controller.syncMonitoring(enabled: true);
    node.publish(
      info: const DeviceInfo(name: 'Phone', deviceType: 'mobile'),
      proofValidUntilNs: BigInt.from(9000000000),
    );
    await controller.readSnapshot();
    expect(controller.values[peerId], PeerPresence.reachable);
    await devices.setAlias(peerId, 'Work');
    expect(controller.values[peerId], PeerPresence.reachable);
    await devices.remove(peerId);
    expect(controller.values, isNot(contains(peerId)));
  });
}
