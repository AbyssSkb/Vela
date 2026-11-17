import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/notification_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
        find.text('Not allowed; standard notifications are used'),
        findsOneWidget,
      );
      await tester.tap(find.text('Incoming requests'));
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
      await tester.ensureVisible(
        find.text('This system uses standard notifications'),
      );
      expect(
        find.text('This system uses standard notifications'),
        findsOneWidget,
      );
      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Live updates'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.onTap, isNull);
    },
  );
}
