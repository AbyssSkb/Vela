import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'two_apps.dart' as pair_test;

Future<Map> state(FlutterDriver driver) async =>
    jsonDecode(await driver.requestData(jsonEncode({'action': 'state'})))
        as Map;

Future<void> main(List<String> args) async {
  final a = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final b = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  try {
    await a.runUnsynchronized(
      () => b.runUnsynchronized(() async {
        final idA = await pair_test.readId(a);
        final idB = await pair_test.readId(b);
        final nameA =
            (jsonDecode(await a.requestData(jsonEncode({'action': 'device'})))
                    as Map)['name']
                as String;
        final nameB =
            (jsonDecode(await b.requestData(jsonEncode({'action': 'device'})))
                    as Map)['name']
                as String;
        await pair_test.addPeer(a, b, idB, nameA, nameB);
        if (!((await state(a))['peers'] as Map).containsKey(idB) ||
            !((await state(b))['peers'] as Map).containsKey(idA)) {
          throw StateError('pairing did not persist on both devices');
        }
        await a.tap(find.byValueKey('peer-$idB'));
        await a.waitFor(
          find.text('移除设备'),
          timeout: const Duration(seconds: 15),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await a.tap(find.text('移除设备'));
        await a.tap(find.text('移除'));
        await a.waitForAbsent(find.text(nameB));
        await b.waitForAbsent(
          find.text(nameA),
          timeout: const Duration(seconds: 75),
        );
        if (((await state(a))['peers'] as Map).containsKey(idB) ||
            ((await state(b))['peers'] as Map).containsKey(idA)) {
          throw StateError('removal did not persist on both devices');
        }
        await pair_test.addPeer(a, b, idB, nameA, nameB);
        await pair_test.sendAndAccept(a, b, idB, nameB);
        stdout.writeln('UNPAIR_ONLINE_AND_REPAIR_TEST_OK');
      }),
    );
  } finally {
    await a.close();
    await b.close();
  }
}
