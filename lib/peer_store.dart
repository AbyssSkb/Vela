import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

/// Stores the complete peer state as one transaction.
class PeerStore {
  PeerStore._(this._database, this._profile, this.legacyStateDetected);

  final Database _database;
  final String _profile;
  final bool legacyStateDetected;

  static Future<PeerStore> open({
    required String profile,
    String? databasePath,
    DatabaseFactory? factory,
  }) async {
    final path =
        databasePath ??
        '${(await getApplicationSupportDirectory()).path}/peer_state_v2.sqlite3';
    final legacyStateDetected =
        databasePath == null &&
        await File('${File(path).parent.path}/peer_state.sqlite3').exists();
    var selectedFactory = factory ?? databaseFactoryOrNull;
    if (selectedFactory == null && (Platform.isWindows || Platform.isLinux)) {
      ffi.sqfliteFfiInit();
      selectedFactory = ffi.databaseFactoryFfi;
    }
    final db = await (selectedFactory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA synchronous = FULL');
          await db.execute('PRAGMA fullfsync = ON');
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE peer_state (profile TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    return PeerStore._(db, profile, legacyStateDetected);
  }

  Future<String?> load() async {
    final rows = await _database.query(
      'peer_state',
      columns: ['value'],
      where: 'profile = ?',
      whereArgs: [_profile],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> save(String value) async {
    await _database.insert('peer_state', {
      'profile': _profile,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() => _database.close();
}
