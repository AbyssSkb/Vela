import 'dart:async';
import 'dart:io';

import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/main.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart' show FakeNode, FakeRustApi;

class FlakyRustApi extends FakeRustApi {
  FlakyRustApi(super.node);
  var starts = 0;
  @override
  Future<VelaNode> crateApiNodeStartNode({required List<int> secret}) async {
    starts++;
    if (starts == 1) throw StateError('temporary initialization failure');
    return node;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  Future<void> waitFor(WidgetTester tester, bool Function() condition) async {
    final timeout = Stopwatch()..start();
    while (!condition() && timeout.elapsed < const Duration(seconds: 30)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(
      condition(),
      isTrue,
      reason: 'Timed out waiting for startup to finish',
    );
  }

  for (final scenario in ['retry', 'disabled', 'disposed']) {
    testWidgets('background initialization: $scenario', (tester) async {
      final dir = Directory.systemTemp.createTempSync('vela-startup-retry-');
      final node = FakeNode();
      final api = FlakyRustApi(node);
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({
        'mac_background_receiving': true,
      });
      RustLib.initMock(api: api);
      const path = MethodChannel('plugins.flutter.io/path_provider');
      const secure = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const background = MethodChannel('vela/background');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        path,
        (call) async => dir.path,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        secure,
        (call) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        background,
        (call) async => null,
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomePage(
              profile: 'test',
              language: 'en',
              appearance: 'light',
              changeSetting: (_, _) async {},
              diagnosticsEnabled: false,
              changeDiagnosticsEnabled: (_) async {},
            ),
          ),
        );
        final dynamic home = tester.state(find.byType(HomePage));
        var firstFinished = false;
        (home.startup as Future<void>).then((_) {
          firstFinished = true;
        });
        await waitFor(tester, () => firstFinished);
        expect(api.starts, 1);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Background receiving'), findsOneWidget);
        expect(home.error, contains('temporary initialization failure'));
        expect((home.startupRetry as Timer?)?.isActive, isTrue);
        if (scenario == 'disabled') {
          await (await SharedPreferences.getInstance()).setBool(
            'mac_background_receiving',
            false,
          );
        }
        if (scenario == 'disposed') await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        if (scenario == 'retry') await waitFor(tester, () => home.node != null);
        expect(api.starts, scenario == 'retry' ? 2 : 1);
        if (scenario == 'disabled') {
          await tester.tap(find.text('Retry'));
          await tester.pump();
          await waitFor(tester, () => home.node != null);
        }
        if (scenario != 'disposed') {
          expect(home.node, same(node));
          expect(home.error, isNull);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 1));
        expect(api.starts, scenario == 'disposed' ? 1 : 2);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        RustLib.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          path,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          secure,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          background,
          null,
        );
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    }, skip: !Platform.isMacOS);
  }
}
