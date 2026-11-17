import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'two_apps.dart' as pair;

Future<String> name(FlutterDriver d) async =>
    (jsonDecode(await d.requestData(jsonEncode({'action': 'device'})))
            as Map)['name']
        as String;
Future<void> main(List<String> args) async {
  final a = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final b = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  final c = await FlutterDriver.connect(dartVmServiceUrl: args[2]);
  try {
    await a.runUnsynchronized(
      () => b.runUnsynchronized(
        () => c.runUnsynchronized(() async {
          final nameA = await name(a),
              nameB = await name(b),
              nameC = await name(c);
          final idB = await pair.readId(b), idC = await pair.readId(c);
          await pair.addPeer(a, b, idB, nameA, nameB);
          await Future<void>.delayed(const Duration(seconds: 2));
          await pair.addPeer(a, c, idC, nameA, nameC);
          await Future<void>.delayed(const Duration(seconds: 2));
          await a.tap(find.byValueKey('send-clipboard'));
          await a.waitFor(
            find.text('选择设备'),
            timeout: const Duration(seconds: 15),
          );
          stdout.writeln('MULTIPLE_DEVICE_SELECTION_OK');
        }),
      ),
    );
  } finally {
    await a.close();
    await b.close();
    await c.close();
  }
}
