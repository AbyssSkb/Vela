import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/notification_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('blocked notifications show a status at large text sizes', (
    tester,
  ) async {
    const channel = MethodChannel('vela/background');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'allNotifications': false, 'requestNotifications': true},
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NotificationSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsNWidgets(4));
    expect(find.text('On'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification statuses refresh when returning from settings', (
    tester,
  ) async {
    const channel = MethodChannel('vela/background');
    final messenger = tester.binding.defaultBinaryMessenger;
    var enabled = false;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'allNotifications': enabled, 'requestNotifications': true},
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NotificationSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsNWidgets(4));
    enabled = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('On'), findsNWidgets(2));
    expect(find.text('Off'), findsNothing);
  });

  testWidgets(
    'notification categories open their corresponding system settings',
    (tester) async {
      const channel = MethodChannel('vela/background');
      final opened = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'status') {
          return {
            'allNotifications': true,
            'requestNotifications': true,
            'progressNotifications': true,
            'resultNotifications': false,
            'liveSupported': true,
            'liveAllowed': false,
          };
        }
        if (call.method == 'settings') {
          opened.add((call.arguments as Map)['section'] as String);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NotificationSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'Incoming request notifications'),
            )
            .subtitle,
        isNull,
      );
      expect(find.text('Off'), findsNWidgets(2));
      final results = find.widgetWithText(ListTile, 'Transfer results');
      expect(
        find.descendant(of: results, matching: find.text('Off')),
        findsOneWidget,
      );
      await tester.tap(find.text('Incoming request notifications'));
      await tester.tap(find.text('Transfer results'));
      await tester.ensureVisible(find.text('Live updates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Live updates'));
      expect(opened, [
        'notification_requests',
        'notification_results',
        'notification_live',
      ]);
    },
  );

  testWidgets(
    'older systems use standard notifications without a live-update control',
    (tester) async {
      const channel = MethodChannel('vela/background');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async =>
            call.method == 'status' ? {'liveSupported': false} : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NotificationSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Uses standard notifications'), findsNothing);
      expect(find.text('Live updates'), findsNothing);
    },
  );
}
