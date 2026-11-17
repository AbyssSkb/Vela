import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  final d = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  try {
    await d.runUnsynchronized(() async {
      await d.requestData(jsonEncode({'action': 'mac-close-test'}));
      final closed = jsonDecode(
        await d.requestData(jsonEncode({'action': 'mac-status-test'})),
      ) as Map;
      if (closed['visible'] != false) {
        throw StateError('Window remained visible after close');
      }
      stdout.writeln('MAC_CLOSE_KEEPS_PROCESS_RUNNING_OK');
    });
  } finally {
    await d.close();
  }
}
