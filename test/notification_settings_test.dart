import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/received_storage.dart';
import 'package:vela/settings_page.dart';

void main() {
  const channel = MethodChannel('vela/background');
  const persistent = 'Persistent notification';
  const live = 'Live updates';
  const transfers = 'Transfer progress and results';
  const requests = 'Incoming requests';
  late Map<String, bool> status;
  late List<String> opened;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    status = {
      'allNotifications': true,
      'serviceNotifications': true,
      'requestNotifications': true,
      'progressNotifications': true,
      'resultNotifications': true,
      'liveSupported': true,
      'liveAllowed': true,
      'showLive': true,
      'showRequests': true,
      'showTransfers': true,
    };
    opened = [];
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'status':
          return status;
        case 'settings':
          opened.add((call.arguments as Map)['section'] as String);
        case 'setNotificationPreference':
          final choice = call.arguments as Map;
          status[choice['category'] as String] = choice['enabled'] as bool;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(
          profile: 'default',
          language: 'en',
          appearance: 'light',
          deviceName: 'Phone',
          systemDeviceName: 'Phone',
          changeSetting: (_, _) async {},
          rename: (_) async {},
          relaySettings: () async {},
          diagnostics: () async {},
          backgroundChanged: () async {},
          receivedStorage: const ReceivedStorage(
            platform: TargetPlatform.android,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String title) => find.widgetWithText(SwitchListTile, title);
  bool active(WidgetTester tester, String title) =>
      tester.widget<SwitchListTile>(row(title)).value;
  Future<void> tap(WidgetTester tester, String title) async {
    await tester.ensureVisible(row(title));
    await tester.tap(row(title));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows four switches on Android settings and stores choices independently',
    (tester) async {
      await pumpSettings(tester);
      for (final title in [requests, transfers, live]) {
        expect(active(tester, title), isTrue);
        await tap(tester, title);
        expect(active(tester, title), isFalse);
      }
      expect(status['showRequests'], isFalse);
      expect(status['showTransfers'], isFalse);
      expect(status['showLive'], isFalse);
      expect(active(tester, persistent), isTrue);
      expect(opened, isEmpty);
    },
  );

  testWidgets(
    'routes system-owned controls and refreshes from their actual state',
    (tester) async {
      status['liveAllowed'] = false;
      status['requestNotifications'] = false;
      await pumpSettings(tester);
      await tap(tester, persistent);
      await tap(tester, live);
      await tap(tester, requests);
      expect(opened, [
        'notification_service',
        'notification_live',
        'notification_requests',
      ]);
      expect(active(tester, live), isFalse);
      expect(active(tester, requests), isFalse);
      status['liveAllowed'] = true;
      status['requestNotifications'] = true;
      status['serviceNotifications'] = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(active(tester, live), isTrue);
      expect(active(tester, requests), isTrue);
      expect(active(tester, persistent), isFalse);
    },
  );

  testWidgets(
    'omits unavailable live updates and opens app settings when notifications are blocked',
    (tester) async {
      status['liveSupported'] = false;
      status['allNotifications'] = false;
      status['serviceNotifications'] = false;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await pumpSettings(tester);
      expect(row(live), findsNothing);
      expect(active(tester, transfers), isFalse);
      await tap(tester, transfers);
      expect(opened, ['notification_app']);
      expect(tester.takeException(), isNull);
    },
  );
}
