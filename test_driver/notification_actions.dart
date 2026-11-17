import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'android_background.dart' as android;

Future<void> main(List<String> args) async {
  final d = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final adb = args[1], peer = args[2];
  Future<Map> state() async =>
      jsonDecode(await d.requestData(jsonEncode({'action': 'state'}))) as Map;
  Future<void> send(String text) async {
    await d.requestData(
      jsonEncode({'action': 'send', 'peer': peer, 'content': text}),
    );
    await android.waitNotification(adb, true);
  }

  Future<void> waitMessage(String message) async {
    final end = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(end)) {
      final s = await state();
      if (s['busy'] == false &&
          (s['message'] as String? ?? '').contains(message)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('Expected $message, got ${await state()}');
  }

  try {
    await d.requestData(jsonEncode({'action': 'mac-show-test'}));
    await d.runUnsynchronized(() async {
      await android.adb(adb, ['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
      await send('notification reject test');
      await d.waitFor(find.byValueKey('activity-notice'));
      final bar = await d.getBottomRight(find.byValueKey('activity-notice'));
      final bottom = await d.getBottomRight(find.byType('Scaffold'));
      if ((bar.dy - bottom.dy).abs() > 1) {
        throw StateError('Activity notice has a bottom gap');
      }
      if (!((await state())['activity'] as String).startsWith('正在发送给 ')) {
        throw StateError('Unexpected sending text');
      }
      stdout.writeln('MAC_ACTIVITY_NOTICE_OK');
      await android.adb(adb, [
        'shell',
        'cmd',
        'statusbar',
        'expand-notifications',
      ]);
      await android.tap(adb, 'Decline');
      await waitMessage('对方拒绝了接收');
      await android.waitNotification(adb, false);
      stdout.writeln('BACKGROUND_REJECT_OK');
      await android.adb(adb, ['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
      await send('notification accept test');
      await android.adb(adb, [
        'shell',
        'cmd',
        'statusbar',
        'expand-notifications',
      ]);
      await android.tap(adb, 'Accept');
      await waitMessage('已发送给');
      await android.waitNotification(adb, false);
      stdout.writeln('BACKGROUND_ACCEPT_OK');
      await android.adb(adb, ['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
      await send('notification cancel test');
      await d.tap(find.byValueKey('cancel-transfer'));
      await waitMessage('传输已取消');
      await android.waitNotification(adb, false);
      stdout.writeln('BACKGROUND_CANCEL_OK');
    });
  } finally {
    await d.close();
  }
}
