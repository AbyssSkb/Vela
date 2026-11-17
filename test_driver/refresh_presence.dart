import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'two_apps.dart' as pair;

Future<Map> state(FlutterDriver d) async =>
    jsonDecode(await d.requestData(jsonEncode({'action': 'state'}))) as Map;
Future<void> waitForState(
  FlutterDriver d,
  bool Function(Map) matches,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (!matches(await state(d))) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(
        'timed out waiting for device status: ${await state(d)}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> main(List<String> args) async {
  final mode = args[0];
  final a = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  FlutterDriver? b;
  try {
    await a.runUnsynchronized(() async {
      if (mode == 'pair') {
        b = await FlutterDriver.connect(dartVmServiceUrl: args[2]);
        await b!.runUnsynchronized(() async {
          final idB = await pair.readId(b!);
          final nameA =
              (jsonDecode(await a.requestData(jsonEncode({'action': 'device'})))
                      as Map)['name']
                  as String;
          final nameB =
              (jsonDecode(
                    await b!.requestData(jsonEncode({'action': 'device'})),
                  ) as Map)['name']
                  as String;
          await pair.addPeer(a, b!, idB, nameA, nameB);
          await waitForState(
            a,
            (s) =>
                s['refreshingPresence'] == false &&
                (s['presence'] as Map)[idB] == 'reachable',
            const Duration(seconds: 30),
          );
          stdout.writeln('REFRESH_PAIR_READY');
        });
      } else if (mode == 'quiet') {
        await waitForState(
          a,
          (s) => s['refreshingPresence'] == false,
          const Duration(seconds: 30),
        );
        await a.requestData(jsonEncode({'action': 'refresh-auto-test'}));
        // Automatic presence updates are event-driven and have no global refresh cycle.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final automatic = await state(a);
        if (automatic['manualRefreshing'] != false ||
            (automatic['presence'] as Map).values.contains('checking')) {
          throw StateError('automatic refresh showed a spinner');
        }
        await a.waitForAbsent(find.byValueKey('manual-refresh-progress'));
        await a.tap(find.byValueKey('refresh-devices'));
        await a.waitFor(
          find.byValueKey('manual-refresh-progress'),
          timeout: const Duration(seconds: 3),
        );
        await waitForState(
          a,
          (s) => s['manualRefreshing'] == false,
          const Duration(seconds: 15),
        );
        stdout.writeln('QUIET_AUTOMATIC_REFRESH_OK');
      } else {
        final before = await state(a);
        final id = (before['peers'] as Map).keys.single as String;
        await waitForState(
          a,
          (s) => s['refreshingPresence'] == false,
          const Duration(seconds: 30),
        );
        final timer = Stopwatch()..start();
        stdout.writeln('STATUS_BEFORE ${(before['presence'] as Map)[id]}');
        await a.tap(find.byValueKey('refresh-devices'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await waitForState(
          a,
          (s) =>
              s['refreshingPresence'] == false &&
              (s['presence'] as Map)[id] == mode,
          const Duration(seconds: 20),
        );
        await a.waitFor(
          find.byTooltip(mode == 'reachable' ? '可连接' : '暂时无法连接'),
          timeout: const Duration(seconds: 5),
        );
        stdout.writeln(
          'REFRESH_${mode.toUpperCase()}_OK ${timer.elapsedMilliseconds}ms',
        );
      }
    });
  } finally {
    await a.close();
    await b?.close();
  }
}
