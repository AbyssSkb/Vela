import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'two_apps.dart' as pair_test;

Future<void> main(List<String> args) async {
  final sender = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final receiver = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  try {
    final id = await pair_test.readId(receiver);
    final senderName =
        (jsonDecode(await sender.requestData(jsonEncode({'action': 'device'})))
                as Map)['name']
            as String;
    final receiverName =
        (jsonDecode(
              await receiver.requestData(jsonEncode({'action': 'device'})),
            ) as Map)['name']
            as String;
    await sender.tap(find.byValueKey('add-device'));
    await sender.tap(find.byValueKey('peer-id'));
    await sender.enterText(id);
    await sender.tap(find.byValueKey('confirm-peer'));
    await receiver.waitFor(
      find.byValueKey('accept-pair'),
      timeout: const Duration(seconds: 75),
    );
    await receiver.tap(find.text('拒绝'));
    await sender.waitFor(
      find.text('对方拒绝了配对请求'),
      timeout: const Duration(seconds: 30),
    );
    await sender.waitForAbsent(find.text(receiverName));
    await receiver.waitForAbsent(find.text(senderName));
    stdout.writeln('PAIR_DECLINE_UI_TEST_OK');
  } finally {
    await sender.close();
    await receiver.close();
  }
}
