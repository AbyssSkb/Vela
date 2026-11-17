import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'two_apps.dart' as pair_test;

Future<void> main(List<String> args) async {
  final sender = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final receiver = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  try {
    final id = await pair_test.readId(receiver);
    final name =
        (jsonDecode(
              await receiver.requestData(jsonEncode({'action': 'device'})),
            ) as Map)['name']
            as String;
    if (args.length > 2 && args[2] == 'pair') {
      final senderName =
          (jsonDecode(
                await sender.requestData(jsonEncode({'action': 'device'})),
              ) as Map)['name']
              as String;
      await sender.runUnsynchronized(
        () => receiver.runUnsynchronized(
          () => pair_test.addPeer(sender, receiver, id, senderName, name),
        ),
      );
    }
    final started = await sender.requestData(
      jsonEncode({
        'action': 'send-speed-test',
        'peer': id,
        'bytes': 128 * 1024 * 1024,
      }),
    );
    if (started != 'started') throw StateError('speed test did not start');
    await receiver.waitFor(
      find.byValueKey('accept-offer'),
      timeout: const Duration(seconds: 60),
    );
    await receiver.runUnsynchronized(
      () => receiver.tap(find.byValueKey('accept-offer')),
    );
    await sender.runUnsynchronized(
      () => sender.waitFor(
        find.byValueKey('transfer-speed'),
        timeout: const Duration(seconds: 120),
      ),
    );
    final speed = await sender.runUnsynchronized(
      () => sender.getText(find.byValueKey('transfer-speed')),
    );
    if (!RegExp(r'^\d+(\.\d+)? (B|KB|MB|GB)/s$').hasMatch(speed)) {
      throw StateError('Invalid speed display: $speed');
    }
    await sender.runUnsynchronized(
      () => sender.waitFor(
        find.text('已发送给 $name'),
        timeout: const Duration(seconds: 120),
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      final state = jsonDecode(
        await receiver.requestData(jsonEncode({'action': 'state'})),
      ) as Map;
      if (state['busy'] == false &&
          (state['activity'] as String? ?? '').startsWith('已接收 ')) {
        break;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('receiver did not finish');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (await receiver.requestData(
          jsonEncode({'action': 'clean-speed-test'}),
        ) !=
        'deleted') {
      throw StateError('could not clean speed test file');
    }
    stdout.writeln('SPEED_UI_TEST_OK: $speed');
  } finally {
    await sender.close();
    await receiver.close();
  }
}
