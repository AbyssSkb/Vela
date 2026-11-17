import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'two_apps.dart' as pair;

Future<Map> state(FlutterDriver driver) async =>
    jsonDecode(await driver.requestData(jsonEncode({'action': 'state'})))
        as Map;

Future<void> waitCancelled(FlutterDriver driver) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final current = await state(driver);
    if (current['busy'] == false && current['message'] == '传输已取消') return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Cancellation did not finish: ${await state(driver)}');
}

Future<void> main(List<String> args) async {
  final a = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final b = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  try {
    await a.runUnsynchronized(
      () => b.runUnsynchronized(() async {
        final id = await pair.readId(b);
        final senderName =
            (jsonDecode(await a.requestData(jsonEncode({'action': 'device'})))
                    as Map)['name']
                as String;
        final receiverName =
            (jsonDecode(await b.requestData(jsonEncode({'action': 'device'})))
                    as Map)['name']
                as String;
        await pair.addPeer(a, b, id, senderName, receiverName);

        await a.requestData(
          jsonEncode({
            'action': 'send',
            'peer': id,
            'content': 'cancel before acceptance',
          }),
        );
        await b.waitFor(
          find.byValueKey('accept-offer'),
          timeout: const Duration(seconds: 60),
        );
        await a.waitFor(
          find.byValueKey('transfer-path'),
          timeout: const Duration(seconds: 30),
        );
        await a.tap(find.byValueKey('cancel-transfer'));
        await b.waitForAbsent(
          find.byValueKey('accept-offer'),
          timeout: const Duration(seconds: 30),
        );
        await waitCancelled(a);
        await waitCancelled(b);

        await a.requestData(
          jsonEncode({
            'action': 'send-speed-test',
            'peer': id,
            'bytes': 512 * 1024 * 1024,
          }),
        );
        await b.waitFor(
          find.byValueKey('accept-offer'),
          timeout: const Duration(seconds: 60),
        );
        await b.tap(find.byValueKey('accept-offer'));
        await b.waitFor(
          find.byValueKey('cancel-transfer'),
          timeout: const Duration(seconds: 30),
        );
        await b.tap(find.byValueKey('cancel-transfer'));
        await waitCancelled(b);
        await waitCancelled(a);

        await pair.sendAndAccept(a, b, id, receiverName);
        stdout.writeln('TRANSFER_CANCEL_UI_OK');
      }),
    );
  } finally {
    await a.close();
    await b.close();
  }
}
