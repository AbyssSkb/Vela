import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/main.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/frb_generated.dart';

import 'support/fakes.dart' show FakeNode, FakeRustApi;

class FlakyRustApi extends FakeRustApi {
  FlakyRustApi() : super(FakeNode());

  var starts = 0;

  @override
  Future<VelaNode> crateApiNodeStartNode({required List<int> secret}) async {
    if (++starts == 1) throw StateError('temporary initialization failure');
    return FakeNode();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const path = MethodChannel('plugins.flutter.io/path_provider');
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const background = MethodChannel('vela/background');
  const storage = MethodChannel('vela/storage');

  Future<void> mount(
    WidgetTester tester,
    Directory dir,
    String language,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(path, (_) async => dir.path);
    messenger.setMockMethodCallHandler(secure, (_) async => null);
    messenger.setMockMethodCallHandler(background, (_) async => null);
    messenger.setMockMethodCallHandler(
      storage,
      (_) async => {'isDefault': true, 'displayPath': ''},
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomePage(
          profile: 'test',
          language: language,
          appearance: 'light',
          changeSetting: (_, _) async {},
          diagnosticsEnabled: false,
          changeDiagnosticsEnabled: (_) async {},
        ),
      ),
    );
  }

  Future<void> waitFor(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(condition(), isTrue, reason: 'Timed out waiting for startup');
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }

  Future<void> cleanUp(WidgetTester tester, Directory dir) async {
    await unmount(tester);
    RustLib.dispose();
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final channel in [path, secure, background, storage]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  for (final language in ['en', 'zh']) {
    testWidgets(
      'legacy notice survives failed startup and is dismissed once ($language)',
      (tester) async {
        final dir = Directory.systemTemp.createTempSync('vela-legacy-notice-');
        final legacy = File('${dir.path}/peer_state.sqlite3');
        legacy.writeAsStringSync('not a database');
        databaseFactory = databaseFactoryFfi;
        SharedPreferences.setMockInitialValues({});
        final api = FlakyRustApi();
        RustLib.initMock(api: api);
        try {
          await mount(tester, dir, language);
          final dynamic failedHome = tester.state(find.byType(HomePage));
          await waitFor(tester, () => failedHome.error != null);
          expect(
            File('${dir.path}/peer_state_v2.sqlite3').existsSync(),
            isTrue,
          );
          expect(
            (await SharedPreferences.getInstance()).getBool(
              'legacy_pairing_notice_test',
            ),
            isNull,
          );
          await unmount(tester);

          await mount(tester, dir, language);
          final notice = language == 'en'
              ? 'Existing device pairings need to be set up again. Your files and history are unchanged.'
              : '检测到旧版设备数据，请重新配对设备。接收的文件和历史记录不受影响。';
          await waitFor(tester, () => find.text(notice).evaluate().isNotEmpty);
          expect(api.starts, 2);
          expect(
            (await SharedPreferences.getInstance()).getBool(
              'legacy_pairing_notice_test',
            ),
            isNull,
          );
          await tester.tap(find.text(language == 'en' ? 'Close' : '关闭'));
          await tester.pumpAndSettle();
          expect(
            (await SharedPreferences.getInstance()).getBool(
              'legacy_pairing_notice_test',
            ),
            isTrue,
          );
          expect(legacy.readAsStringSync(), 'not a database');
          await unmount(tester);

          await mount(tester, dir, language);
          final dynamic home = tester.state(find.byType(HomePage));
          await waitFor(tester, () => home.node != null);
          await tester.pump();
          expect(find.text(notice), findsNothing);
        } finally {
          await cleanUp(tester, dir);
        }
      },
    );
  }

  testWidgets('fresh installation does not show a legacy notice', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('vela-fresh-notice-');
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    RustLib.initMock(api: FakeRustApi(FakeNode()));
    try {
      await mount(tester, dir, 'en');
      final dynamic home = tester.state(find.byType(HomePage));
      await waitFor(tester, () => home.node != null);
      await tester.pump();
      expect(
        find.text(
          'Existing device pairings need to be set up again. Your files and history are unchanged.',
        ),
        findsNothing,
      );
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'legacy_pairing_notice_test',
        ),
        isNull,
      );
    } finally {
      await cleanUp(tester, dir);
    }
  });
}
