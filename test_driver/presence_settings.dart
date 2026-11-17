import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'two_apps.dart' as pair;

Future<Map> state(FlutterDriver d) async =>
    jsonDecode(await d.requestData(jsonEncode({'action': 'state'}))) as Map;
Future<void> waitUntil(Future<bool> Function() check, String error) async {
  final deadline = DateTime.now().add(const Duration(seconds: 80));
  while (!await check()) {
    if (DateTime.now().isAfter(deadline)) throw StateError(error);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

Future<void> main(List<String> args) async {
  final a = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final b = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  try {
    await a.runUnsynchronized(
      () => b.runUnsynchronized(() async {
        stdout.writeln('step final idA =');
        final idA = await pair.readId(a);
        final idB = await pair.readId(b);
        final nameA =
            (jsonDecode(await a.requestData(jsonEncode({'action': 'device'})))
                    as Map)['name']
                as String;
        final nameB =
            (jsonDecode(await b.requestData(jsonEncode({'action': 'device'})))
                    as Map)['name']
                as String;
        stdout.writeln('step await pair.addPeer');
        await pair.addPeer(a, b, idB, nameA, nameB);
        await Future<void>.delayed(const Duration(seconds: 2));
        stdout.writeln('step await waitUntil(() async => ((await state(a))');
        await waitUntil(
          () async => ((await state(a))['presence'] as Map)[idB] == 'reachable',
          'peer never became reachable',
        );
        stdout.writeln("step await a.waitFor(find.byTooltip('可连接'))");
        await a.waitFor(find.byTooltip('可连接'));
        stdout.writeln('step await b.tap(find.byValueKey');
        await b.tap(find.byValueKey('peer-$idA'));
        await b.waitFor(find.text('重命名'), timeout: const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        stdout.writeln("step await b.tap(find.text('重命名'))");
        await b.tap(find.text('重命名'));
        await b.waitFor(
          find.text('重命名设备'),
          timeout: const Duration(seconds: 10),
        );
        await b.tap(find.byType('TextField'));
        await b.enterText('Local alias');
        await b.tap(find.text('保存'));
        await b.waitFor(find.text('Local alias'));
        stdout.writeln("step await a.tap(find.byTooltip('设置'))");
        await a.tap(find.byTooltip('设置'));
        await a.tap(find.text('设备名称'));
        await a.waitFor(
          find.byType('TextField'),
          timeout: const Duration(seconds: 10),
        );
        await a.tap(find.byType('TextField'));
        await a.enterText('Renamed device');
        await a.tap(find.text('保存'));
        await a.waitFor(find.text('Renamed device'));
        await waitUntil(
          () async =>
              ((await state(b))['peers'] as Map)[idA] == 'Renamed device',
          'renamed device not synchronized',
        );
        await b.waitFor(find.text('Local alias'));
        stdout.writeln("step await a.tap(find.text('语言'))");
        await a.tap(find.text('语言'));
        await a.tap(find.text('English'));
        await a.waitFor(find.text('Settings'));
        await a.waitFor(find.text('Device name'));
        stdout.writeln('PRESENCE_RENAME_LANGUAGE_OK');
      }),
    );
  } finally {
    await a.close();
    await b.close();
  }
}
