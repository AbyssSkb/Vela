import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vela/paired_devices.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/peer_store.dart';
import 'package:vela/src/rust/api/node.dart';

class RecordingNode implements VelaNode {
  final events = <String>[];
  Completer<void>? trustGate;
  final trustStarted = Completer<void>();
  int? failTrustCall;
  int trustCalls = 0;

  @override
  Future<void> replaceTrustedPeers({required List<String> trusted}) async {
    events.add('trust:${trusted.join(',')}');
    trustCalls++;
    if (!trustStarted.isCompleted) trustStarted.complete();
    final gate = trustGate;
    trustGate = null;
    if (gate != null) await gate.future;
    if (trustCalls == failTrustCall) throw StateError('trust unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory directory;
  late String databasePath;
  late PeerStore store;
  late RecordingNode node;
  PairedDevices? devices;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vela-paired-devices-');
    databasePath = '${directory.path}/peers.sqlite3';
    store = await PeerStore.open(
      profile: 'test',
      databasePath: databasePath,
      factory: databaseFactoryFfi,
    );
    node = RecordingNode();
    devices = null;
  });

  tearDown(() async {
    if (devices != null) {
      await devices!.close();
    } else {
      await store.close();
    }
    await directory.delete(recursive: true);
  });

  test('revokes first, persists, publishes, then grants new trust', () async {
    final original = PeerState().add('old', 'Old device', 'desktop');
    await store.save(original.encode());
    devices = PairedDevices(
      node: node,
      store: store,
      initialState: original,
      onMembershipChanging: (updated, changed) {
        expect(devices!.state, same(original));
        expect(devices!.relationshipFor('old'), isNull);
        expect(changed, {'old', 'new'});
        node.events.add('changing');
      },
      onStateChanged: (state, changed) {
        expect(devices!.state, same(state));
        node.events.add('published:${state.peers.keys.join(',')}');
      },
      onMembershipSettled: (_) => node.events.add('settled'),
    );

    await devices!.update(
      (state) => state.remove('old').add('new', 'New device', 'mobile'),
    );

    expect(node.events, [
      'changing',
      'trust:',
      'published:new',
      'trust:new',
      'settled',
    ]);
    expect(PeerState.decode((await store.load())!).peers, {
      'new': 'New device',
    });
  });

  test('failed persistence restores old trust and keeps old state', () async {
    final original = PeerState().add('old', 'Old device', 'desktop');
    await store.save(original.encode());
    devices = PairedDevices(
      node: node,
      store: store,
      initialState: original,
      onStateChanged: (_, _) => node.events.add('published'),
      onMembershipSettled: (_) => node.events.add('settled'),
    );
    final previous = devices!.relationshipFor('old');
    final database = await databaseFactoryFfi.openDatabase(databasePath);
    await database.execute('PRAGMA query_only = ON');
    try {
      await expectLater(devices!.remove('old'), throwsA(anything));
    } finally {
      await database.execute('PRAGMA query_only = OFF');
    }

    expect(devices!.state, same(original));
    expect(PeerState.decode((await store.load())!).peers, original.peers);
    expect(node.events.take(2), ['trust:', 'trust:old']);
    expect(devices!.relationshipFor('old'), isNotNull);
    expect(devices!.isCurrentRelationship('old', previous), isFalse);
    expect(node.events, isNot(contains('published')));
    expect(node.events.last, 'settled');
    await devices!.setAlias('old', 'Alias after failure');
    expect(devices!.state.displayName('old'), 'Alias after failure');
  });

  test(
    'a new pairing invalidates an older commit waiting in the queue',
    () async {
      devices = PairedDevices(
        node: node,
        store: store,
        initialState: PeerState(),
      );
      final first = devices!.beginRelationship('new');
      final gate = Completer<void>();
      node.trustGate = gate;
      final blockingSync = devices!.syncTrust();
      await node.trustStarted.future;
      final stalePair = devices!.pair(
        'new',
        'Stale name',
        'desktop',
        when: () => devices!.isCurrentRelationship('new', first),
      );
      final second = devices!.beginRelationship('new');
      gate.complete();
      await blockingSync;
      expect(await stalePair, isFalse);
      expect(await store.load(), isNull);
      await devices!.pair('new', 'New name', 'desktop');
      expect(devices!.isCurrentRelationship('new', second), isTrue);
      await devices!.setAlias('new', 'Work');
      expect(devices!.isCurrentRelationship('new', second), isTrue);
      await devices!.close();
      expect(devices!.isCurrentRelationship('new', second), isFalse);
    },
  );

  test('close drains queued changes and rejects new work', () async {
    final original = PeerState().add('old', 'Old device', 'desktop');
    var publications = 0;
    devices = PairedDevices(
      node: node,
      store: store,
      initialState: original,
      onStateChanged: (_, _) => publications++,
    );
    final gate = Completer<void>();
    node.trustGate = gate;
    final pairing = devices!.pair('new', 'New device', 'mobile');
    await node.trustStarted.future;
    final alias = devices!.setAlias('new', 'Queued alias');
    final closing = devices!.close();
    await expectLater(devices!.remove('old'), throwsA(isA<StateError>()));
    gate.complete();
    await Future.wait([pairing, alias]);
    await closing;

    expect(devices!.state.displayName('new'), 'Queued alias');
    expect(publications, 0);
    final reopened = await PeerStore.open(
      profile: 'test',
      databasePath: databasePath,
      factory: databaseFactoryFfi,
    );
    try {
      final persisted = PeerState.decode((await reopened.load())!);
      expect(persisted.displayName('new'), 'Queued alias');
    } finally {
      await reopened.close();
    }
  });

  test('a failed trust grant retries the latest committed state', () async {
    devices = PairedDevices(
      node: node,
      store: store,
      initialState: PeerState(),
    );
    node.failTrustCall = 2;
    await devices!.pair('new', 'New device', 'mobile');
    expect(devices!.state.peers, {'new': 'New device'});
    await devices!.setAlias('new', 'Latest name');
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await devices!.idle;
    expect(node.events, ['trust:', 'trust:new', 'trust:new']);
    expect(
      PeerState.decode((await store.load())!).displayName('new'),
      'Latest name',
    );
  });
}
