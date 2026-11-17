import 'dart:io';

import 'package:vela/peer_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'desktop production factory preserves peers without an injected factory',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vela-desktop-store-',
      );
      final path = '${directory.path}/state.sqlite3';
      try {
        var store = await PeerStore.open(
          profile: 'default',
          databasePath: path,
        );
        await store.save('paired-device');
        await store.close();
        store = await PeerStore.open(profile: 'default', databasePath: path);
        expect(await store.load(), 'paired-device');
        await store.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows && !Platform.isLinux,
  );

  test(
    'preserves updates, recovers from write failures, and isolates profiles',
    () async {
      final dir = await Directory.systemTemp.createTemp('vela-peer-store-');
      final path = '${dir.path}/state.sqlite3';
      Future<PeerStore> open(String profile) => PeerStore.open(
        profile: profile,
        databasePath: path,
        factory: databaseFactoryFfi,
      );
      try {
        var store = await open('first');
        expect(await store.load(), isNull);
        await store.save('updated');
        final database = await databaseFactoryFfi.openDatabase(path);
        await database.execute('PRAGMA query_only = ON');
        await expectLater(store.save('failed'), throwsA(anything));
        expect(await store.load(), 'updated');
        await database.execute('PRAGMA query_only = OFF');
        await store.save('after retry');
        await store.close();
        await expectLater(store.save('failed'), throwsA(anything));

        store = await open('first');
        expect(await store.load(), 'after retry');
        await store.save('retry');
        await store.close();

        store = await open('second');
        expect(await store.load(), isNull);
        await store.save('other');
        await store.close();

        store = await open('first');
        expect(await store.load(), 'retry');
        await store.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test('detects the old database on every default database open', () async {
    final dir = await Directory.systemTemp.createTemp('vela-peer-upgrade-');
    final legacy = File('${dir.path}/peer_state.sqlite3');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    Future<PeerStore> open(String profile) =>
        PeerStore.open(profile: profile, factory: databaseFactoryFfi);
    try {
      await legacy.writeAsString('old database is not read');
      var store = await open('first');
      expect(store.legacyStateDetected, isTrue);
      expect(await store.load(), isNull);
      await store.close();
      store = await open('second');
      expect(store.legacyStateDetected, isTrue);
      expect(await store.load(), isNull);
      await store.close();
      store = await open('first');
      expect(store.legacyStateDetected, isTrue);
      await store.close();
      store = await PeerStore.open(
        profile: 'custom',
        databasePath: '${dir.path}/peer_state_v2.sqlite3',
        factory: databaseFactoryFfi,
      );
      expect(store.legacyStateDetected, isFalse);
      await store.close();
      expect(await legacy.readAsString(), 'old database is not read');
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
    }
  });

  test('fresh installation does not report old data', () async {
    final dir = await Directory.systemTemp.createTemp('vela-peer-fresh-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    try {
      final store = await PeerStore.open(
        profile: 'first',
        factory: databaseFactoryFfi,
      );
      expect(store.legacyStateDetected, isFalse);
      await store.close();
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
    }
  });
}
