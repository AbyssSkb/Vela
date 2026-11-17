import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  final d = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  try {
    await d.runUnsynchronized(() async {
      await d.waitFor(
        find.byValueKey('accept-offer'),
        timeout: const Duration(seconds: 90),
      );
      final app = await Process.run('swift', [
        '-e',
        'import AppKit; let p = NSRunningApplication(processIdentifier: ${args[1]}); print("hidden=\\(p?.isHidden ?? true),active=\\(p?.isActive ?? false)")',
      ]);
      stdout.write(app.stdout);
      if (!(app.stdout as String).contains('hidden=false')) {
        throw StateError('Mac window did not reopen');
      }
      await d.tap(find.byValueKey('accept-offer'));
      final end = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(end)) {
        final state = jsonDecode(
          await d.requestData(jsonEncode({'action': 'state'})),
        ) as Map;
        final path = state['receivedPath'] as String?;
        if (state['busy'] == false &&
            path != null &&
            path.endsWith('vela-background-test.txt')) {
          if (await File(path).readAsString() !=
              'Android to Mac background test\n') {
            throw StateError('wrong file content');
          }
          stdout.writeln('MAC_BACKGROUND_RECEIVE_OK');
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      throw StateError('receive timed out');
    });
  } finally {
    await d.close();
  }
}
