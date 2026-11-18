import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  final mac = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final android = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  final adb = args[2];
  final macName =
      (jsonDecode(await mac.requestData(jsonEncode({'action': 'device'})))
              as Map)['name']
          as String;
  Future<String> shell(List<String> arguments) async {
    final result = await Process.run(adb, [
      '-s',
      'emulator-5554',
      'shell',
      ...arguments,
    ]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return result.stdout as String;
  }

  Future<void> acceptShare() async {
    final recipient = find.byValueKey('choose-share-device');
    await android.waitFor(recipient, timeout: const Duration(seconds: 60));
    await android.tap(recipient);
    await mac.waitFor(
      find.byValueKey('accept-offer'),
      timeout: const Duration(seconds: 60),
    );
    await mac.tap(find.byValueKey('accept-offer'));
    await android.waitFor(
      find.text('已发送给 $macName'),
      timeout: const Duration(seconds: 60),
    );
  }

  try {
    await shell([
      'am',
      'start',
      '-a',
      'android.intent.action.SEND',
      '-t',
      'text/plain',
      '--es',
      'android.intent.extra.TEXT',
      'shared-text-test',
      '-n',
      'com.example.vela/.MainActivity',
    ]);
    await acceptShare();
    await mac.waitFor(find.text('剪贴板内容已接收'));
    final text = await mac.requestData(
      jsonEncode({'action': 'get-clipboard', 'kind': 'text'}),
    );
    if (text != 'shared-text-test') throw StateError('shared text mismatch');
    await android.requestData(
      jsonEncode({
        'action': 'set-clipboard',
        'kind': 'file',
        'content': 'shared-file-test',
      }),
    );
    final names = await shell([
      'run-as',
      'com.example.vela',
      'ls',
      '-t',
      'files',
    ]);
    final name = names
        .split('\n')
        .firstWhere((item) => item.startsWith('clip-test-'))
        .trim();
    final uri = 'content://com.example.vela.provider/files/$name';
    await shell([
      'am',
      'start',
      '-a',
      'android.intent.action.SEND',
      '-t',
      'application/octet-stream',
      '--eu',
      'android.intent.extra.STREAM',
      uri,
      '-n',
      'com.example.vela/.MainActivity',
    ]);
    await acceptShare();
    await mac.waitFor(find.text('已接收 $name'));
    stdout.writeln('ANDROID_SHARE_TEST_OK');
  } finally {
    await mac.close();
    await android.close();
  }
}
