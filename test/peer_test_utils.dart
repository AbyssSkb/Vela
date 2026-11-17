import 'dart:io';

import 'package:vela/peer_state.dart';
import 'package:vela/peer_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> seedPeerState(
  WidgetTester tester,
  Directory directory,
  PeerState state,
) async {
  await tester.runAsync(() async {
    final store = await PeerStore.open(
      profile: 'test',
      databasePath: '${directory.path}/peer_state_v2.sqlite3',
      factory: databaseFactoryFfi,
    );
    await store.save(state.encode());
    await store.close();
  });
}
