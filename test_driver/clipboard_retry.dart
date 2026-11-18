import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> a) async {
  final sender = await FlutterDriver.connect(dartVmServiceUrl: a[0]);
  final receiver = await FlutterDriver.connect(dartVmServiceUrl: a[1]);
  try {
    await sender.runUnsynchronized(
      () => receiver.runUnsynchronized(() async {
        await sender.requestData(
          jsonEncode({
            'action': 'set-clipboard',
            'kind': 'text',
            'content': 'original retry text',
          }),
        );
        await sender.tap(find.byValueKey('send-clipboard'));
        await receiver.requestData(jsonEncode({'action': 'mac-show-test'}));
        await receiver.waitFor(
          find.byValueKey('accept-offer'),
          timeout: const Duration(seconds: 75),
        );
        await receiver.tap(find.text('拒绝'));
        await sender.waitFor(
          find.byValueKey('retry-send'),
          timeout: const Duration(seconds: 75),
        );
        await sender.requestData(
          jsonEncode({
            'action': 'set-clipboard',
            'kind': 'text',
            'content': 'changed clipboard',
          }),
        );
        await sender.tap(find.byValueKey('retry-send'));
        await receiver.requestData(jsonEncode({'action': 'mac-show-test'}));
        await receiver.waitFor(
          find.byValueKey('accept-offer'),
          timeout: const Duration(seconds: 75),
        );
        await receiver.tap(find.byValueKey('accept-offer'));
        await receiver.waitFor(
          find.text('剪贴板内容已接收'),
          timeout: const Duration(seconds: 75),
        );
        final text = await receiver.requestData(
          jsonEncode({'action': 'get-clipboard', 'kind': 'text'}),
        );
        if (text != 'original retry text') {
          throw StateError('retry sent changed clipboard');
        }
        stdout.writeln('CLIPBOARD_RETRY_SNAPSHOT_OK');
      }),
    );
  } finally {
    await sender.close();
    await receiver.close();
  }
}
