import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'two_apps.dart' as pair;

Future<Map> status(FlutterDriver driver) async => jsonDecode(
  await driver.requestData(jsonEncode({'action': 'mac-status-test'})),
) as Map;
Future<Map> menu(FlutterDriver driver) async => jsonDecode(
  await driver.requestData(jsonEncode({'action': 'mac-menu-test'})),
) as Map;
Future<void> until(Future<bool> Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(end)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  throw StateError('Timed out waiting for Mac status');
}

Future<void> main(List<String> args) async {
  final a = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final b = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  try {
    await a.runUnsynchronized(
      () => b.runUnsynchronized(() async {
        final id = await pair.readId(b);
        final nameA =
            (jsonDecode(await a.requestData(jsonEncode({'action': 'device'})))
                    as Map)['name']
                as String;
        final nameB =
            (jsonDecode(await b.requestData(jsonEncode({'action': 'device'})))
                    as Map)['name']
                as String;
        await pair.addPeer(a, b, id, nameA, nameB);
        await b.requestData(jsonEncode({'action': 'mac-close-test'}));
        if ((await status(b))['visible'] != false) {
          throw StateError('Close did not hide window');
        }
        final idleMenu = await menu(b);
        if (idleMenu['windowVisible'] != true) {
          throw StateError('Menu item disappeared after closing');
        }
        await a.requestData(
          jsonEncode({'action': 'send', 'peer': id, 'content': 'status test'}),
        );
        await until(() async => (await status(b))['incoming'] == true);
        final incomingMenu = await menu(b);
        if (incomingMenu['hasImage'] != true ||
            incomingMenu['windowVisible'] != true ||
            (incomingMenu['lightColor'] as String).isEmpty ||
            incomingMenu['lightColor'] == idleMenu['lightColor']) {
          throw StateError(
            'Incoming request did not change the visible status light',
          );
        }
        if ((await status(b))['visible'] != false) {
          throw StateError('Incoming request opened the window');
        }
        await a.tap(find.byValueKey('cancel-transfer'));
        await until(() async => (await status(b))['incoming'] == false);
        await until(
          () async =>
              (jsonDecode(await a.requestData(jsonEncode({'action': 'state'})))
                  as Map)['busy'] ==
              false,
        );
        await a.requestData(
          jsonEncode({
            'action': 'send',
            'peer': id,
            'content': 'status test 2',
          }),
        );
        await until(() async => (await status(b))['incoming'] == true);
        await b.requestData(jsonEncode({'action': 'mac-show-test'}));
        await b.waitFor(
          find.byValueKey('accept-offer'),
          timeout: const Duration(seconds: 30),
        );
        await b.tap(find.byValueKey('accept-offer'));
        await until(() async => (await status(b))['incoming'] == false);
        stdout.writeln('MAC_HIDDEN_INCOMING_AND_CANCEL_OK');
      }),
    );
  } finally {
    await a.close();
    await b.close();
  }
}
