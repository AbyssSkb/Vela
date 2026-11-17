import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'two_apps.dart' as pair;

Future<Map> state(FlutterDriver d) async =>
    jsonDecode(await d.requestData(jsonEncode({'action': 'state'}))) as Map;
Future<void> waitUntil(Future<bool> Function() check, String message) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await check()) {
    if (DateTime.now().isAfter(deadline)) throw StateError(message);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> main(List<String> args) async {
  final a = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final b = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  try {
    await a.runUnsynchronized(
      () => b.runUnsynchronized(() async {
        final idB = await pair.readId(b);
        final nameA =
            (jsonDecode(await a.requestData(jsonEncode({'action': 'device'})))
                    as Map)['name']
                as String;
        final nameB =
            (jsonDecode(await b.requestData(jsonEncode({'action': 'device'})))
                    as Map)['name']
                as String;
        await pair.addPeer(a, b, idB, nameA, nameB);
        await Future<void>.delayed(const Duration(seconds: 1));
        if ((await state(b))['message'] != '已添加 $nameA') {
          throw StateError('pairing reported failure: ${await state(b)}');
        }
        final name = '${List.filled(21, 'long-file-').join()}report.txt';
        final result = await a.requestData(
          jsonEncode({
            'action': 'send',
            'peer': idB,
            'content': 'test',
            'filename': name,
          }),
        );
        if (result != 'started') {
          throw StateError('send did not start: $result');
        }
        await b.waitFor(
          find.byValueKey('accept-offer'),
          timeout: const Duration(seconds: 30),
        );
        await b.waitFor(find.text(name));
        final topLeft = await b.getTopLeft(find.text(name));
        final bottomRight = await b.getBottomRight(find.text(name));
        final width = bottomRight.dx - topLeft.dx;
        if (width > 372.5) {
          throw StateError('receive dialog content too wide: $width');
        }
        await waitUntil(
          () async => (await state(a))['refreshingPresence'] == false,
          'initial refresh did not finish',
        );
        await a.tap(find.byValueKey('refresh-devices'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await waitUntil(
          () async =>
              (await state(a))['refreshingPresence'] == false &&
              ((await state(a))['presence'] as Map)[idB] == 'reachable',
          'status check was blocked by open offer',
        );
        await b.tap(find.text('拒绝'));
        await waitUntil(
          () async => (await state(a))['busy'] == false,
          'declined send did not finish',
        );
        final failure = (await state(a))['message'] as String? ?? '';
        if (!failure.startsWith('发送失败')) {
          throw StateError('missing failure notice: $failure');
        }
        await a.waitFor(find.text(failure));
        final bottom = await a.getBottomRight(find.byType('Scaffold'));
        if ((await a.getTopLeft(find.text(failure))).dy < bottom.dy - 180) {
          throw StateError('failure notice is not at the bottom');
        }
        await pair.sendAndAccept(a, b, idB, nameB);
        stdout.writeln('LONG_DIALOG_AND_STATUS_DURING_OFFER_OK width=$width');
      }),
    );
  } finally {
    await a.close();
    await b.close();
  }
}
