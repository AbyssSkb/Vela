import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/src/rust/frb_generated.dart';

import '../peer_test_utils.dart';
import 'fakes.dart';

Future<void> withHomeTestEnvironment(
  WidgetTester tester, {
  required PeerState devices,
  required FakeRustApi api,
  required Future<void> Function(Directory directory) run,
}) async {
  final directory = Directory.systemTemp.createTempSync('vela-home-test-');
  final messenger = tester.binding.defaultBinaryMessenger;
  const path = MethodChannel('plugins.flutter.io/path_provider');
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const background = MethodChannel('vela/background');
  const deviceInfo = MethodChannel('vela/device');
  const share = MethodChannel('vela/share');
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await seedPeerState(tester, directory, devices);
  SharedPreferences.setMockInitialValues({});
  RustLib.initMock(api: api);
  try {
    messenger.setMockMethodCallHandler(path, (_) async => directory.path);
    messenger.setMockMethodCallHandler(secure, (_) async => null);
    messenger.setMockMethodCallHandler(
      background,
      (call) async => call.method == 'getWindowVisible' ? true : null,
    );
    messenger.setMockMethodCallHandler(
      deviceInfo,
      (call) async =>
          call.method == 'info' ? {'name': 'MacBook', 'type': 'desktop'} : null,
    );
    messenger.setMockMethodCallHandler(share, (_) async => null);
    tester.view.devicePixelRatio = 1;
    await run(directory);
  } finally {
    try {
      await unmountTestHome(tester, api.node);
    } finally {
      RustLib.dispose();
      for (final channel in [path, secure, background, deviceInfo, share]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  }
}

Future<void> unmountTestHome(WidgetTester tester, FakeNode node) async {
  await tester.pumpWidget(const SizedBox.shrink());
  if (node.trustCalls > 0) await waitForHome(tester, () => node.closed);
}

Future<void> waitForHome(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: 'Home did not reach the expected state');
}
