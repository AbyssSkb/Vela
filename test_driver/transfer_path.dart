import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> a) async {
  final d = await FlutterDriver.connect(dartVmServiceUrl: a[0]);
  try {
    await d.runUnsynchronized(() async {
      final response = await d.requestData(
        jsonEncode({
          'action': 'send-speed-test',
          'peer': a[1],
          'bytes': 128 * 1024 * 1024,
        }),
      );
      if (response != 'started') throw StateError('send not started');
      await d.waitFor(
        find.byTooltip(a[2]),
        timeout: const Duration(seconds: 50),
      );
      stdout.writeln('TRANSFER_PATH_ICON_OK: ${a[2]}');
      await d.tap(find.byValueKey('cancel-transfer'));
    });
  } finally {
    await d.close();
  }
}
