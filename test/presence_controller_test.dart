import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela/paired_devices.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/presence_controller.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/frb_generated.dart';

import 'support/fakes.dart';

class _RecordingNode extends FakeNode {
  final checkedPeers = <String>[];

  @override
  Future<DeviceInfo> checkPeerFresh({required String peerId}) {
    checkedPeers.add(peerId);
    return super.checkPeerFresh(peerId: peerId);
  }
}

Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

void main() {
  late FakeNode node;
  late PresenceController controller;
  late PairedDevices devices;

  PairedDevices trustedDevices(FakeNode node, {String? otherPeer}) =>
      PairedDevices(
        node: node,
        store: MemoryPeerStore(),
        initialState: PeerState(
          peers: {peerId: 'Phone', if (otherPeer != null) otherPeer: 'Laptop'},
          types: {peerId: 'mobile'},
        ),
        onMembershipChanging: (_, changed) =>
            controller.membershipChanging(changed),
        onStateChanged: controller.membershipPublished,
        onMembershipWriteFinished: controller.membershipWriteFinished,
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
    await controller.readCurrentSnapshot();
    expect(node.freshCalls, isEmpty);

    final probe = controller.requestPeerProbes(userInitiated: true);
    await _flush();
    expect(node.freshCalls, hasLength(1));
    expect(controller.checkingPeers, isTrue);
    node.fresh.complete(const DeviceInfo(name: 'Phone', deviceType: 'mobile'));
    await probe;

    expect(controller.checkingPeers, isFalse);
    expect(controller.values[peerId], PeerPresence.unavailable);
  });

  test('refreshing one device probes only that device', () async {
    await devices.close();
    final old = node;
    final recording = _RecordingNode();
    node = recording;
    final otherPeer = 'b' * 64;
    devices = trustedDevices(node, otherPeer: otherPeer);
    controller.attach(devices);
    await old.close();
    await controller.syncMonitoring(enabled: true);
    const info = DeviceInfo(name: 'Phone', deviceType: 'mobile');
    final initial = controller.requestPeerProbes();
    await _flush();
    for (final call in recording.freshCalls) {
      call.complete(info);
    }
    await initial;
    recording.checkedPeers.clear();

    final refresh = controller.requestPeerProbe(peerId);
    await _flush();
    await controller.requestPeerProbe(peerId);
    expect(recording.checkedPeers, [peerId]);
    expect(controller.visibleChecks, contains(peerId));
    expect(controller.checkingPeers, isFalse);
    recording.freshCalls.last.complete(info);
    await refresh;
    expect(controller.visibleChecks, isNot(contains(peerId)));
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
    await controller.readCurrentSnapshot();
    old.releaseWatch.complete();
    await _flush();

    expect(controller.values[peerId], PeerPresence.unavailable);
    await old.close();
  });

  test(
    'membership interruption does not start another network probe',
    () async {
      await controller.syncMonitoring(enabled: true);
      final probe = controller.requestPeerProbes();
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
    await controller.readCurrentSnapshot();
    expect(controller.values[peerId], PeerPresence.reachable);
    await devices.setAlias(peerId, 'Work');
    expect(controller.values[peerId], PeerPresence.reachable);
    await devices.remove(peerId);
    expect(controller.values, isNot(contains(peerId)));
  });
}
