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
        await Future.wait([
          a.tap(find.byValueKey('add-device')),
          b.tap(find.byValueKey('add-device')),
        ]);
        await a.tap(find.byValueKey('peer-id'));
        await a.enterText(idB);
        await b.tap(find.byValueKey('peer-id'));
        await b.enterText(idA);
        await Future.wait([
          a.tap(find.byValueKey('confirm-peer')),
          b.tap(find.byValueKey('confirm-peer')),
        ]);
        final receiver = idA.compareTo(idB) < 0 ? b : a;
        await receiver.waitFor(
          find.byValueKey('accept-pair'),
          timeout: const Duration(seconds: 75),
        );
        await receiver.tap(find.byValueKey('accept-pair'));
        final deadline = DateTime.now().add(const Duration(seconds: 75));
        while (true) {
          final sa = await state(a);
          final sb = await state(b);
          if ((sa['peers'] as Map).containsKey(idB) &&
              (sb['peers'] as Map).containsKey(idA) &&
              sa['pairing'] == false &&
              sb['pairing'] == false) {
            break;
          }
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('crossed pairing did not converge: $sa / $sb');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await a.tap(find.byValueKey('peer-$idB'));
        await a.waitFor(
          find.text('移除设备'),
          timeout: const Duration(seconds: 15),
        );
        await a.tap(find.text('移除设备'));
        await a.tap(find.text('移除'));
        final removedDeadline = DateTime.now().add(const Duration(seconds: 30));
        while (((await state(b))['peers'] as Map).containsKey(idA)) {
          if (DateTime.now().isAfter(removedDeadline)) {
            throw StateError('remote device retained the removed pairing');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        stdout.writeln('SIMULTANEOUS_PAIRING_OK');
      }),
    );
  } finally {
    await a.close();
    await b.close();
  }
}
