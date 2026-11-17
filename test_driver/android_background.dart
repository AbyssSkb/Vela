import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<String> adb(String exe, List<String> args) async {
  final r = await Process.run(exe, args);
  if (r.exitCode != 0) throw StateError('adb failed: ${r.stderr}');
  return r.stdout as String;
}

Future<String> ui(String exe) async {
  await adb(exe, ['shell', 'uiautomator', 'dump', '/sdcard/vela-test.xml']);
  return adb(exe, ['shell', 'cat', '/sdcard/vela-test.xml']);
}

Future<void> tap(String exe, String label) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(end)) {
    final xml = await ui(exe);
    for (final match in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
      final node = match.group(0)!;
      if (!node.contains('content-desc="$label"') &&
          !node.contains('text="$label"')) {
        continue;
      }
      final b = RegExp(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
          .firstMatch(node);
      if (b == null) continue;
      final x = (int.parse(b[1]!) + int.parse(b[3]!)) ~/ 2;
      final y = (int.parse(b[2]!) + int.parse(b[4]!)) ~/ 2;
      await adb(exe, ['shell', 'input', 'tap', '$x', '$y']);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw StateError('Android control not found: $label');
}

Future<void> waitNotification(String exe, bool present) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(end)) {
    final notifications = await adb(exe, [
      'shell',
      'dumpsys',
      'notification',
      '--noredact',
    ]);
    final found =
        notifications.contains('id=32') &&
        notifications.contains('com.example.vela');
    if (found == present) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw StateError('Expected incoming notification: $present');
}

Future<void> main(List<String> args) async {
  final d = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final exe = args[1], peer = args[2];
  try {
    await d.runUnsynchronized(() async {
      await adb(exe, ['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
      await d.waitFor(
        find.byValueKey('add-device'),
        timeout: const Duration(seconds: 30),
      );
      await d.tap(find.byValueKey('add-device'));
      await d.tap(find.byValueKey('peer-id'));
      await d.enterText(peer);
      await d.tap(find.byValueKey('confirm-peer'));
      await tap(exe, 'Add');
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(deadline)) {
        final state = jsonDecode(
          await d.requestData(jsonEncode({'action': 'state'})),
        ) as Map;
        if ((state['peers'] as Map).containsKey(peer)) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await adb(exe, ['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
      await d.requestData(
        jsonEncode({
          'action': 'send',
          'peer': peer,
          'content': 'cancel in background',
        }),
      );
      await waitNotification(exe, true);
      await d.tap(find.byValueKey('cancel-transfer'));
      await waitNotification(exe, false);
      await d.requestData(
        jsonEncode({
          'action': 'send',
          'peer': peer,
          'content': 'background receive verified',
        }),
      );
      await waitNotification(exe, true);
      await adb(exe, ['shell', 'cmd', 'statusbar', 'expand-notifications']);
      await tap(exe, 'A device is sending content');
      await tap(exe, 'Accept');
      final end = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(end)) {
        final state = jsonDecode(
          await d.requestData(jsonEncode({'action': 'state'})),
        ) as Map;
        if (state['busy'] == false &&
            (state['activity'] as String? ?? '').startsWith('已发送给')) {
          stdout.writeln('ANDROID_BACKGROUND_OFFER_CANCEL_RECEIVE_OK');
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      throw StateError('Android receive did not complete');
    });
  } finally {
    await d.close();
  }
}
