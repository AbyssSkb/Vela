import 'dart:async';
import 'dart:typed_data';

import 'package:vela/peer_store.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/frb_generated.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:sqflite_common/src/factory.dart';

const peerId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class MemoryPeerStore implements PeerStore {
  String? saved;

  @override
  Future<void> save(String value) async {
    saved = value;
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class GatedDatabaseFactory implements SqfliteDatabaseFactory {
  GatedDatabaseFactory(this.delegate);
  final DatabaseFactory delegate;
  bool gateNextWrite = false;
  bool failNextWrite = false;
  int failedWrites = 0;
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();
  int writesAfterGate = 0;
  String? lastSavedValue;
  bool countWrites = false;

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async =>
      GatedDatabase(await delegate.openDatabase(path, options: options), this);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class GatedDatabase implements Database {
  GatedDatabase(this.delegate, this.factory);
  final Database delegate;
  final GatedDatabaseFactory factory;
  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (factory.failNextWrite && table == 'peer_state') {
      factory.failNextWrite = false;
      factory.failedWrites++;
      throw StateError('simulated peer state save failure');
    }
    if (factory.gateNextWrite && table == 'peer_state') {
      factory.gateNextWrite = false;
      factory.countWrites = true;
      factory.writeStarted.complete();
      await factory.releaseWrite.future;
    }
    final result = await delegate.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
    if (factory.countWrites && table == 'peer_state') {
      factory.writesAfterGate++;
      factory.lastSavedValue = values['value'] as String;
    }
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => delegate.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );
  @override
  Future<void> close() => delegate.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOutgoingPairing implements OutgoingPairing {
  @override
  void cancel() {}
  @override
  Future<DeviceInfo> request({
    required String name,
    required String deviceType,
  }) async => const DeviceInfo(name: 'Phone', deviceType: 'mobile');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNode implements VelaNode {
  FakeNode({this.enableGate});
  final Completer<void>? enableGate;
  final enableStarted = Completer<void>();
  final pendingOffer = Completer<IncomingRequest>();
  final fresh = Completer<DeviceInfo>();
  final freshCalls = <Completer<DeviceInfo>>[];
  var closed = false;
  var monitoring = false;
  var peerTrusted = true;
  var unpairedTaken = 0;
  var trustCalls = 0;
  int? failTrustOnCall;
  var failedTrustCalls = 0;
  var change = Completer<void>();
  var holdWatch = false;
  var watchHeld = false;
  var releaseWatch = Completer<void>();
  var snapshot = PresenceSnapshot(
    revision: BigInt.one,
    peers: [
      const PeerPresenceSnapshot(
        peerId: peerId,
        info: null,
        proofValidUntilNs: null,
        unpaired: false,
      ),
    ],
  );

  void publish({
    required DeviceInfo? info,
    required BigInt? proofValidUntilNs,
    bool unpaired = false,
  }) {
    snapshot = PresenceSnapshot(
      revision: snapshot.revision + BigInt.one,
      peers: [
        PeerPresenceSnapshot(
          peerId: peerId,
          info: info,
          proofValidUntilNs: proofValidUntilNs,
          unpaired: unpaired,
        ),
      ],
    );
    final previous = change;
    change = Completer<void>();
    if (!previous.isCompleted) previous.complete();
  }

  @override
  String id() =>
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  @override
  Future<void> replaceTrustedPeers({required List<String> trusted}) async {
    trustCalls++;
    if (trustCalls == failTrustOnCall) {
      failedTrustCalls++;
      throw StateError('simulated trust sync failure');
    }
    final next = trusted.contains(peerId);
    if (next != peerTrusted) {
      peerTrusted = next;
      publish(info: null, proofValidUntilNs: null);
    }
  }

  @override
  Future<bool> revokeIfUnpaired({required String peerId}) async {
    if (!peerTrusted || !snapshot.peers.single.unpaired) return false;
    unpairedTaken++;
    peerTrusted = false;
    publish(info: null, proofValidUntilNs: null);
    return true;
  }

  @override
  Future<void> beginPairing({required String peerId}) async {}
  @override
  Future<void> endPairing({required String peerId}) async {}
  @override
  TransferJob newTransferJob() => FakeTransferJob();
  @override
  Future<OutgoingPairing> beginOutgoingPairing({
    required String peerId,
  }) async => FakeOutgoingPairing();
  @override
  Future<void> setDeviceInfo({
    required String name,
    required String deviceType,
  }) async {}
  @override
  Future<void> waitUntilOnline() async {}
  @override
  Future<IncomingRequest> nextRequest() => pendingOffer.future;
  @override
  Future<DeviceInfo> checkPeerFresh({required String peerId}) {
    final next = freshCalls.isEmpty ? fresh : Completer<DeviceInfo>();
    freshCalls.add(next);
    return next.future;
  }

  @override
  Future<DeviceInfo> checkPeer({required String peerId}) async =>
      throw StateError('offline');
  @override
  Future<void> setPresenceMonitoring({required bool enabled}) async {
    if (enabled && enableGate != null && !enableGate!.isCompleted) {
      if (!enableStarted.isCompleted) enableStarted.complete();
      await enableGate!.future;
    }
    monitoring = enabled;
  }

  @override
  Future<PresenceSnapshot> waitPresenceSnapshot({
    required BigInt afterRevision,
  }) async {
    if (afterRevision == BigInt.zero &&
        snapshot.peers.single.info != null &&
        (snapshot.peers.single.proofValidUntilNs ?? BigInt.zero) <=
            BigInt.from(1000000000)) {
      publish(info: null, proofValidUntilNs: null);
    }
    while (!closed && snapshot.revision <= afterRevision) {
      await change.future;
    }
    if (closed) throw StateError('closed');
    final current = snapshot;
    if (holdWatch && afterRevision > BigInt.zero) {
      watchHeld = true;
      await releaseWatch.future;
    }
    return current;
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!change.isCompleted) change.complete();
    if (!releaseWatch.isCompleted) releaseWatch.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTransferJob implements TransferJob {
  @override
  void cancel() {}
  @override
  TransferProgress progress() => TransferProgress(
    done: BigInt.zero,
    total: BigInt.zero,
    path: '',
    udpBytesSent: BigInt.zero,
  );
  @override
  Future<void> sendFile({
    required String peerId,
    required String path,
    required String kind,
  }) async {}
  @override
  Future<void> sendFiles({
    required String peerId,
    required List<String> paths,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRustApi implements RustLibApi {
  FakeRustApi(this.node);
  final FakeNode node;
  BigInt clockNow = BigInt.from(1000000000);
  @override
  Future<VelaNode> crateApiNodeStartNode({required List<int> secret}) async =>
      node;
  @override
  Future<Uint8List> crateApiNodeGenerateSecret() async => Uint8List(32);
  @override
  BigInt crateApiNodeDiagnosticsMonotonicMs() => BigInt.zero;
  @override
  BigInt crateApiNodeProofClockNowNs() => clockNow;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
