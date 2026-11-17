import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'transfer_history.dart';

class TransferHistoryStore {
  TransferHistoryStore(this.profile);

  final String profile;
  final records = ValueNotifier<List<TransferRecord>>([]);
  late SharedPreferences _prefs;
  bool _loaded = false;
  Future<void> _writes = Future.value();

  void load(SharedPreferences prefs) {
    _prefs = prefs;
    // A node restart must not replace records waiting in the write queue.
    if (!_loaded) {
      records.value = TransferRecord.decode(
        prefs.getString('history_$profile'),
      );
      _loaded = true;
    }
  }

  Future<void> _write() {
    final write = _writes.then((_) async {
      if (!await _prefs.setString(
        'history_$profile',
        jsonEncode(records.value.map((item) => item.toJson()).toList()),
      )) {
        throw StateError('history write failed');
      }
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> add(TransferRecord record) async {
    records.value = [record, ...records.value];
    await _write();
  }

  Future<bool> remove(
    Iterable<TransferRecord> items, {
    required bool deleteFiles,
    Future<void> Function(String)? deleteFile,
  }) async {
    final result = await deleteFilesAndSelectRemovableRecords(
      items.toList(),
      deleteFiles: deleteFiles,
      deleteFile: deleteFile,
    );
    records.value = records.value
        .where((item) => !result.removed.contains(item))
        .toList();
    await _write();
    return result.failed;
  }
}
