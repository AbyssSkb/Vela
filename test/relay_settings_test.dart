import 'dart:async';

import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/relay_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('relay editing is disabled while the switch is being applied', (
    tester,
  ) async {
    final changing = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RelaySettingsPage(
          enabled: true,
          setEnabled: (_) => changing.future,
          relays: const ['https://relay.example.com/'],
          add: (url, token) async => url,
          readToken: (_) async => null,
          update: (_, url, _) async => url,
          remove: (_) async {},
          test: (_, _) async => 'connected',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('relay-enabled')));
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('relay-enabled')))
          .onChanged,
      isNull,
    );
    expect(
      tester.widget<ListTile>(find.byKey(const ValueKey('add-relay'))).onTap,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('test-relay-https://relay.example.com/')),
          )
          .onPressed,
      isNull,
    );
    changing.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('relay-enabled')))
          .value,
      isFalse,
    );
  });

  test('custom relay mode requires the switch and a configured relay', () {
    expect(useCustomRelays(false, ['https://relay.example.com/']), isFalse);
    expect(useCustomRelays(true, []), isFalse);
    expect(useCustomRelays(true, ['https://relay.example.com/']), isTrue);
  });

  testWidgets('relay switch tells the user when a transfer is active', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RelaySettingsPage(
          enabled: true,
          setEnabled: (_) async => throw RelayBusyException(),
          relays: const [],
          add: (url, token) async => url,
          readToken: (_) async => null,
          update: (_, url, _) async => url,
          remove: (_) async {},
          test: (_, _) async => 'connected',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('relay-enabled')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('relay-enabled')))
          .value,
      isTrue,
    );
    expect(
      find.text('Finish the current transfer or pairing first'),
      findsOneWidget,
    );
  });

  testWidgets('relay switch applies changes and preserves state on failure', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RelaySettingsPage(
          enabled: true,
          setEnabled: (enabled) async {
            changes.add(enabled);
            if (enabled) throw StateError('save failed');
          },
          relays: const [],
          add: (url, token) async => url,
          readToken: (_) async => null,
          update: (_, url, _) async => url,
          remove: (_) async {},
          test: (_, _) async => 'connected',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('relay-enabled')));
    await tester.pumpAndSettle();
    expect(changes, [false]);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('relay-enabled')))
          .value,
      isFalse,
    );
    expect(find.text('Currently using Iroh public relays'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('relay-enabled')));
    await tester.pumpAndSettle();
    expect(changes, [false, true]);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('relay-enabled')))
          .value,
      isFalse,
    );
    expect(find.text('Could not change relay settings'), findsOneWidget);
  });

  testWidgets('tests a saved relay with its token and reports the result', (
    tester,
  ) async {
    String? testedUrl, testedToken;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RelaySettingsPage(
          enabled: true,
          setEnabled: (_) async {},
          relays: const ['https://relay.example.com/'],
          add: (url, token) async => url,
          readToken: (_) async => 'secret',
          update: (old, url, token) async => url,
          remove: (_) async {},
          test: (url, token) async {
            testedUrl = url;
            testedToken = token;
            return 'auth';
          },
        ),
      ),
    );
    expect(find.text('Currently using custom relays'), findsOneWidget);
    expect(
      find.text(
        'Only custom relays are used. Configure the same relay list on your other devices.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('test-relay-https://relay.example.com/')),
    );
    await tester.pumpAndSettle();
    expect(testedUrl, 'https://relay.example.com/');
    expect(testedToken, 'secret');
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'relay.example.com'),
        matching: find.text('Access denied. Check the token.'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('relay.example.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Access denied. Check the token.'), findsNothing);
  });

  testWidgets('tests unsaved relay settings without saving them', (
    tester,
  ) async {
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RelaySettingsPage(
          enabled: true,
          setEnabled: (_) async {},
          relays: const [],
          add: (url, token) async {
            saved = true;
            return url;
          },
          readToken: (_) async => null,
          update: (old, url, token) async => url,
          remove: (_) async {},
          test: (url, token) async =>
              url == 'https://relay.example.com' && token == 'secret'
              ? 'connected'
              : 'failed',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('add-relay')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'https://relay.example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'secret');
    await tester.tap(find.byKey(const ValueKey('test-relay-form')));
    await tester.pumpAndSettle();
    expect(find.text('This device can reach the relay.'), findsOneWidget);
    expect(saved, isFalse);
    await tester.enterText(find.byType(TextFormField).last, 'changed');
    await tester.pump();
    expect(find.text('This device can reach the relay.'), findsNothing);
  });

  testWidgets('add, edit and remove a relay', (tester) async {
    String? added, secret, removed, updatedFrom;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RelaySettingsPage(
          enabled: true,
          setEnabled: (_) async {},
          relays: const [],
          add: (url, token) async {
            added = url;
            secret = token;
            return '$url/';
          },
          readToken: (_) async => secret,
          update: (old, url, token) async {
            updatedFrom = old;
            secret = token;
            return '$url/';
          },
          remove: (url) async {
            removed = url;
          },
          test: (url, token) async => 'connected',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('add-relay')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'http://example.com',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid HTTPS relay address'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).first,
      'https://example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'test-token');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(added, 'https://example.com');
    expect(secret, 'test-token');
    expect(find.text('Currently using custom relays'), findsOneWidget);
    await tester.tap(find.text('example.com'));
    await tester.pumpAndSettle();
    expect(find.text('Edit relay'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller!
          .text,
      'test-token',
    );
    await tester.enterText(
      find.byType(TextFormField).first,
      'https://relay.example.com',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(updatedFrom, 'https://example.com/');
    expect(secret, 'test-token');
    await tester.tap(find.text('relay.example.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove relay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(removed, 'https://relay.example.com/');
    expect(find.text('relay.example.com'), findsNothing);
    expect(find.text('Currently using Iroh public relays'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save failure keeps the form and token for retry', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RelaySettingsPage(
          enabled: true,
          setEnabled: (_) async {},
          relays: const [],
          add: (url, token) async {
            if (++attempts == 1) throw StateError('failed');
            return '$url/';
          },
          readToken: (_) async => null,
          update: (old, url, token) async => url,
          remove: (_) async {},
          test: (_, _) async => 'connected',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('add-relay')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'https://example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'secret');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save the relay. Try again.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller!
          .text,
      'secret',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('example.com'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
}
