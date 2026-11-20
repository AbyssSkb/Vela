import 'dart:async';
import 'dart:io';

import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/main.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/transfer_history.dart';
import 'package:vela/transfer_history_store.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:sqflite_common/src/factory.dart';

import 'support/fakes.dart' show FakeNode, FakeRustApi, peerId;
import 'peer_test_utils.dart';

class CloseGateFactory implements SqfliteDatabaseFactory {
  CloseGateFactory(this.delegate);
  final DatabaseFactory delegate;
  final closeStarted = Completer<void>();
  final releaseClose = Completer<void>();
  bool gated = false;
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async => CloseGateDatabase(
    await delegate.openDatabase(path, options: options),
    this,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CloseGateDatabase implements Database {
  CloseGateDatabase(this.delegate, this.factory);
  final Database delegate;
  final CloseGateFactory factory;
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
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => delegate.insert(
    table,
    values,
    nullColumnHack: nullColumnHack,
    conflictAlgorithm: conflictAlgorithm,
  );
  @override
  Future<void> close() async {
    if (!factory.gated) {
      factory.gated = true;
      factory.closeStarted.complete();
      await factory.releaseClose.future;
    }
    await delegate.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FirstFailureApi extends FakeRustApi {
  FirstFailureApi(super.node);
  int starts = 0;
  @override
  Future<VelaNode> crateApiNodeStartNode({required List<int> secret}) async {
    if (++starts == 1) throw StateError('temporary initialization failure');
    return node;
  }
}

class TwoNodesApi extends FakeRustApi {
  TwoNodesApi(super.node, this.second);
  final FakeNode second;
  int starts = 0;
  @override
  Future<VelaNode> crateApiNodeStartNode({required List<int> secret}) async =>
      ++starts == 1 ? node : second;
}

class HistoryWriteGate extends InMemorySharedPreferencesStore {
  HistoryWriteGate() : super.empty();
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.history_test' && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const path = MethodChannel('plugins.flutter.io/path_provider');
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const background = MethodChannel('vela/background');
  const storage = MethodChannel('vela/storage');

  Future<void> mount(WidgetTester tester, Directory dir) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(path, (_) async => dir.path);
    messenger.setMockMethodCallHandler(secure, (_) async => null);
    messenger.setMockMethodCallHandler(background, (_) async => null);
    messenger.setMockMethodCallHandler(
      storage,
      (_) async => {'isDefault': true, 'displayPath': ''},
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomePage(
          profile: 'test',
          language: 'en',
          appearance: 'light',
          changeSetting: (_, _) async {},
          diagnosticsEnabled: false,
          changeDiagnosticsEnabled: (_) async {},
        ),
      ),
    );
  }

  Future<void> waitUntil(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue);
  }

  Future<void> dispose(WidgetTester tester, Directory dir) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    RustLib.dispose();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(path, null);
    messenger.setMockMethodCallHandler(secure, null);
    messenger.setMockMethodCallHandler(background, null);
    messenger.setMockMethodCallHandler(storage, null);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  testWidgets('Retry during failed startup waits for store cleanup', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('vela-startup-close-');
    final factory = CloseGateFactory(databaseFactoryFfi);
    databaseFactory = factory;
    SharedPreferences.setMockInitialValues({});
    final node = FakeNode();
    final api = FirstFailureApi(node);
    RustLib.initMock(api: api);
    try {
      await mount(tester, dir);
      await waitUntil(tester, () => factory.closeStarted.isCompleted);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(
        api.starts,
        1,
        reason: 'old database must be closed before a second node is created',
      );
      factory.releaseClose.complete();
      final dynamic home = tester.state(find.byType(HomePage));
      await waitUntil(tester, () => identical(home.node, node));
      expect(api.starts, 2);
      expect(home.error, isNull);
    } finally {
      if (!factory.releaseClose.isCompleted) factory.releaseClose.complete();
      await dispose(tester, dir);
    }
  });

  testWidgets('relay change waits for startup before replacing node', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('vela-startup-relay-');
    final gate = Completer<void>();
    final first = FakeNode(enableGate: gate);
    final second = FakeNode();
    final api = TwoNodesApi(first, second);
    databaseFactory = databaseFactoryFfi;
    await seedPeerState(tester, dir, PeerState(peers: {peerId: 'Phone'}));
    SharedPreferences.setMockInitialValues({});
    RustLib.initMock(api: api);
    try {
      await mount(tester, dir);
      await waitUntil(tester, () => first.enableStarted.isCompleted);
      expect(api.starts, 1);
      await tester.tap(find.byKey(const ValueKey('home-settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Relay servers'));
      await tester.tap(find.text('Relay servers'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('relay-enabled')));
      await tester.pump();
      expect(api.starts, 1);
      expect(
        first.closed,
        isFalse,
        reason: 'the first startup must finish before its node is closed',
      );
      gate.complete();
      await waitUntil(tester, () => api.starts == 2);
      expect(first.closed, isTrue);
      final dynamic home = tester.state(
        find.byType(HomePage, skipOffstage: false),
      );
      await waitUntil(tester, () => identical(home.node, second));
      await waitUntil(
        tester,
        () => !tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('relay-enabled')))
            .value,
      );
    } finally {
      if (!gate.isCompleted) gate.complete();
      await dispose(tester, dir);
    }
  });

  testWidgets('relay restart keeps queued history and its listener', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('vela-history-relay-');
    final first = FakeNode();
    final second = FakeNode();
    final api = TwoNodesApi(first, second);
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final platform = HistoryWriteGate();
    RustLib.initMock(api: api);
    try {
      await mount(tester, dir);
      final dynamic home = tester.state(find.byType(HomePage));
      await waitUntil(tester, () => identical(home.node, first));
      final store = home.historyStore as TransferHistoryStore;
      final notifier = store.records;
      var notifications = 0;
      notifier.addListener(() => notifications++);
      SharedPreferencesStorePlatform.instance = platform;
      TransferRecord record(String name) => TransferRecord(
        name: name,
        peer: 'Phone',
        time: DateTime(2026),
        kind: HistoryKind.file,
        received: true,
      );
      final writeFirst = store.add(record('first'));
      await waitUntil(tester, () => platform.started.isCompleted);
      final writeSecond = store.add(record('second'));

      await tester.tap(find.byKey(const ValueKey('home-settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Relay servers'));
      await tester.tap(find.text('Relay servers'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('relay-enabled')));
      await tester.pump();
      await waitUntil(tester, () => identical(home.node, second));
      expect(store.records, same(notifier));
      expect(notifier.value.map((item) => item.name), ['second', 'first']);
      expect(notifications, 2);
      platform.release.complete();
      await tester.runAsync(() async {
        await writeFirst;
        await writeSecond;
      });
      final saved = await platform.getAll();
      expect(
        TransferRecord.decode(saved['flutter.history_test'] as String)
            .map((item) => item.name),
        ['second', 'first'],
      );
    } finally {
      if (!platform.release.isCompleted) platform.release.complete();
      await dispose(tester, dir);
    }
  });
}
