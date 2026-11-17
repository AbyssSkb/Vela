import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vela/transfer_history.dart';
import 'package:vela/transfer_history_store.dart';
import 'package:vela/received_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class ControlledPreferences extends InMemorySharedPreferencesStore {
  ControlledPreferences() : super.empty();

  final started = Completer<void>();
  final release = Completer<void>();
  int writes = 0;
  bool blockFirst = false;
  bool failFirst = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.history_test') {
      writes++;
      if (writes == 1 && blockFirst) {
        started.complete();
        await release.future;
      }
      if (writes == 1 && failFirst) return false;
    }
    return super.setValue(valueType, key, value);
  }
}

TransferRecord record(String name, {String? path, DateTime? time}) =>
    TransferRecord(
      name: name,
      peer: 'Phone',
      time: time ?? DateTime(2026),
      kind: HistoryKind.file,
      received: true,
      path: path,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final failFirst in [false, true]) {
    test(
      'keeps records and write queue across reload (first fails: $failFirst)',
      () async {
        final original = record('legacy', path: '/legacy');
        final legacy = original.toJson()..remove('size');
        SharedPreferences.setMockInitialValues({
          'history_test': jsonEncode([legacy]),
        });
        final prefs = await SharedPreferences.getInstance();
        final platform = ControlledPreferences()
          ..blockFirst = true
          ..failFirst = failFirst;
        SharedPreferencesStorePlatform.instance = platform;
        final store = TransferHistoryStore('test')..load(prefs);
        final notifier = store.records;
        expect(notifier.value.single.name, 'legacy');
        expect(notifier.value.single.size, isNull);
        var notifications = 0;
        notifier.addListener(() => notifications++);

        final first = store.add(record('first'));
        final firstResult = failFirst
            ? expectLater(first, throwsStateError)
            : first;
        await platform.started.future;
        final second = store.add(record('second'));
        expect(platform.writes, 1);
        store.load(prefs);
        expect(store.records, same(notifier));
        expect(notifications, 2);
        platform.release.complete();
        await firstResult;
        await second;
        expect(platform.writes, 2);
        final persisted = await platform.getAll();
        final loaded = TransferRecord.decode(
          persisted['flutter.history_test'] as String,
        );
        expect(loaded.map((item) => item.name), ['second', 'first', 'legacy']);
        await prefs.reload();
        final freshStore = TransferHistoryStore('test')..load(prefs);
        expect(freshStore.records.value.map((item) => item.name), [
          'second',
          'first',
          'legacy',
        ]);
      },
    );
  }

  test(
    'partially failed deletion keeps the failed record and saves the rest',
    () async {
      final dir = await Directory.systemTemp.createTemp('vela-history-store-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/file');
      await file.writeAsString('content');
      final existing = record('file', path: file.path);
      final denied = record('denied', path: 'content://files/denied');
      SharedPreferences.setMockInitialValues({
        'history_test': jsonEncode([existing.toJson(), denied.toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = TransferHistoryStore('test')..load(prefs);
      final failed = await store.remove(
        store.records.value,
        deleteFiles: true,
        deleteFile: (reference) async {
          if (reference == denied.path) throw StateError('denied');
          await const ReceivedStorage().delete(reference);
        },
      );
      expect(failed, isTrue);
      expect(await file.exists(), isFalse);
      expect(store.records.value.map((item) => item.name), ['denied']);
      expect(
        TransferRecord.decode(prefs.getString('history_test')).single.name,
        'denied',
      );
    },
  );
}
