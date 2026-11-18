import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:sqflite_common/src/factory.dart';
import 'package:vela/app_runtime.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/frb_generated.dart';

import 'support/fakes.dart';

class _MemoryDatabase implements Database {
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();
  bool holdWrite = false;
  bool closed = false;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => [];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {}

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
  }) async => [];

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (holdWrite) {
      writeStarted.complete();
      await releaseWrite.future;
    }
    return 1;
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryFactory implements SqfliteDatabaseFactory {
  _MemoryFactory(this.database);
  final _MemoryDatabase database;
  int opens = 0;

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    opens++;
    await options?.onConfigure?.call(database);
    return database;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatedStart extends FakeRustApi {
  _GatedStart(super.node);
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<VelaNode> crateApiNodeStartNode({required List<int> secret}) async {
    started.complete();
    await release.future;
    return node;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const device = MethodChannel('vela/device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _MemoryDatabase database;
  late _MemoryFactory factory;
  late AppRuntime runtime;
  late FakeNode node;

  setUp(() {
    database = _MemoryDatabase();
    factory = _MemoryFactory(database);
    databaseFactory = factory;
    SharedPreferences.setMockInitialValues({});
    node = FakeNode();
    RustLib.initMock(api: FakeRustApi(node));
    messenger.setMockMethodCallHandler(
      paths,
      (_) async => '/virtual/vela-runtime',
    );
    messenger.setMockMethodCallHandler(
      device,
      (_) async => {'name': 'Test', 'type': 'desktop'},
    );
    runtime = AppRuntime(
      profile: 'test',
      testIdentity: true,
      recordDiagnostic: (_) {},
      onStartupFailure: (_) {},
      onMembershipChanging: (_, __) {},
      onStateChanged: (_, __) {},
      onMembershipSettled: (_) {},
    );
  });

  tearDown(() async {
    await runtime.dispose();
    RustLib.dispose();
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(device, null);
  });

  test('repeated start keeps the same node and store', () async {
    final first = await runtime.start();
    expect(await runtime.start(), same(first));
    expect(factory.opens, 1);
  });

  test(
    'close drains persisted device changes before closing the node',
    () async {
      await runtime.start();
      database.holdWrite = true;
      final write = runtime.devices!.pair(peerId, 'Phone', 'mobile');
      await database.writeStarted.future;
      final closing = runtime.close();
      expect(runtime.node, isNull);
      expect(node.closed, isFalse);
      expect(database.closed, isFalse);
      database.releaseWrite.complete();
      await write;
      await closing;
      expect(database.closed, isTrue);
      expect(node.closed, isTrue);
    },
  );

  test('dispose rejects and cleans a late startup result', () async {
    RustLib.dispose();
    final api = _GatedStart(node);
    RustLib.initMock(api: api);
    final opening = runtime.start();
    await api.started.future;
    final closing = runtime.dispose();
    api.release.complete();
    expect(await opening, isNull);
    await closing;
    expect(runtime.node, isNull);
    expect(database.closed, isTrue);
    expect(node.closed, isTrue);
  });
}
