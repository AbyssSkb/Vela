import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'two_apps.dart' as pair_test;

Future<Map> state(FlutterDriver driver) async =>
    jsonDecode(await driver.requestData(jsonEncode({'action': 'state'})))
        as Map;

Future<void> main(List<String> args) async {
  final mode = args[0];
  final a = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  FlutterDriver? b;
  try {
    if (mode != 'remove') {
      b = await FlutterDriver.connect(dartVmServiceUrl: args[2]);
    }
    if (mode == 'pair') {
      final idB = await pair_test.readId(b!);
      final nameA =
          (jsonDecode(await a.requestData(jsonEncode({'action': 'device'})))
                  as Map)['name']
              as String;
      final nameB =
          (jsonDecode(await b.requestData(jsonEncode({'action': 'device'})))
                  as Map)['name']
              as String;
      await pair_test.addPeer(a, b, idB, nameA, nameB);
      stdout.writeln('OFFLINE_PREPARED');
    } else if (mode == 'remove') {
      await a.runUnsynchronized(() async {
        final id = ((await state(a))['peers'] as Map).keys.single as String;
        await a.tap(find.byValueKey('peer-$id'));
        await a.waitFor(find.text('移除设备'));
        await a.tap(find.text('移除设备'));
        await a.waitFor(find.text('移除'));
        await a.tap(find.text('移除'));
      });
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (true) {
        final current = await state(a);
        if ((current['peers'] as Map).isEmpty) break;
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('offline removal did not persist: $current');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      stdout.writeln('OFFLINE_REMOVAL_OK');
    } else if (mode == 'verify') {
      final deadline = DateTime.now().add(const Duration(seconds: 75));
      while (true) {
        final left = await state(a);
        final right = await state(b!);
        if ((left['peers'] as Map).isEmpty && (right['peers'] as Map).isEmpty) {
          break;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('offline removal was not synced');
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      stdout.writeln('OFFLINE_RESTART_SYNC_OK');
    } else {
      throw ArgumentError('unknown mode');
    }
  } finally {
    await a.close();
    await b?.close();
  }
}
