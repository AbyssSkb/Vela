import 'package:vela/background_settings.dart';
import 'package:vela/desktop_platform.dart';
import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/page_layout.dart';
import 'package:vela/received_storage.dart';
import 'package:vela/settings_page.dart';
import 'package:vela/settings_row_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class FailingFirstWriteStore extends InMemorySharedPreferencesStore {
  FailingFirstWriteStore(this.throws)
    : super.withData({'flutter.background_receive_test': false});
  final bool throws;
  var writes = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (writes++ == 0) {
      if (throws) throw StateError('disk error');
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  const channel = MethodChannel('vela/background');

  testWidgets('wide desktop headers reach the edges of the centered page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const header = ValueKey('page-header');
    const body = ValueKey('page-body');
    for (final (platform, left) in [
      (TargetPlatform.macOS, 0.0),
      (TargetPlatform.android, 220.0),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: const PageLayout(
            header: SizedBox(key: header, width: double.infinity, height: 48),
            body: SizedBox(key: body, width: double.infinity, height: 80),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(header)).dx, left);
      expect(tester.getTopLeft(find.byKey(body)), const Offset(220, 48));
      expect(tester.getSize(find.byKey(body)).width, 560);
    }
  });

  testWidgets('a short setting label leaves room for the full device name', (
    tester,
  ) async {
    const name = 'sdk_gphone64_arm64';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 450,
              child: SettingsRowTitle('Device name', value: Text(name)),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.text(name)).width, greaterThan(450 * .46));
  });
  test(
    'background receiving defaults on and honors a saved off choice',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      for (final setting in BackgroundReceiving.values) {
        expect(setting.enabled(prefs, 'test'), isTrue);
        await prefs.setBool(setting.preferenceKey('test'), false);
        expect(setting.enabled(prefs, 'test'), isFalse);
      }
    },
  );

  testWidgets('device name reports empty or whitespace-only input inline', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => TextButton(
            child: const Text('Rename'),
            onPressed: () async => saved = await showDialog<String>(
              context: context,
              builder: (_) =>
                  const NameDialog(title: 'Device name', current: 'Phone'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    await tester.enterText(field, '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).decoration?.errorText, isNotNull);
    expect(saved, isNull);
    await tester.enterText(field, ' Travel phone ');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).decoration?.errorText, isNull);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 'Travel phone');
  });

  testWidgets('settings keep Back visible and repair an unavailable folder', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    const storage = MethodChannel('vela/storage');
    final messenger = tester.binding.defaultBinaryMessenger;
    var chosen = false;
    var notificationsEnabled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setRequestNotifications') {
        notificationsEnabled = call.arguments as bool;
        return null;
      }
      if (call.method == 'settings')
        fail('The switch should update Vela directly');
      return {'active': true, 'notifications': notificationsEnabled};
    });
    messenger.setMockMethodCallHandler(storage, (call) async {
      if (call.method == 'choose') {
        chosen = true;
        return true;
      }
      if (!chosen) throw PlatformException(code: 'unavailable');
      return {'isDefault': false, 'displayPath': 'Shared files'};
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(storage, null);
      messenger.setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(
          profile: 'test',
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
            platform: TargetPlatform.macOS,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('Language')).dy,
      tester.getCenter(find.text('English')).dy,
    );
    final notifications = find.widgetWithText(SwitchListTile, 'Notifications');
    await tester.ensureVisible(notifications);
    expect(tester.widget<SwitchListTile>(notifications).value, isFalse);
    await tester.tap(notifications);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(notifications).value, isTrue);
    await tester.tap(notifications);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(notifications).value, isFalse);
    final autoAccept = find.widgetWithText(SwitchListTile, 'Auto accept');
    expect(tester.widget<SwitchListTile>(autoAccept).subtitle, isNull);
    expect(
      find.byTooltip(
        'Automatically accept incoming transfers from paired devices.',
      ),
      findsNothing,
    );
    final choose = find.text('Save location');
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(chosen, isTrue);
    expect(find.text('Shared files'), findsOneWidget);
    final showWindow = find.widgetWithText(
      SwitchListTile,
      'Show window after receiving',
    );
    await tester.ensureVisible(showWindow);
    expect(tester.widget<SwitchListTile>(showWindow).value, isFalse);
    await tester.tap(showWindow);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DesktopPlatform.openAfterReceiveKey('test')), isTrue);
    await tester.ensureVisible(find.text('Diagnostics'));
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  test(
    'background summaries do not equate configuration with availability',
    () {
      final t = lookupAppLocalizations(const Locale('en'));
      final android = BackgroundReceiving.androidService;
      const notificationBlocked = {
        'running': true,
        'nodeReady': true,
        'notifications': false,
        'batteryExempt': true,
      };
      expect(
        android.statusText(t, true, notificationBlocked),
        'Service running',
      );
      const lowPowerStandby = {
        ...notificationBlocked,
        'lowPowerStandbyEnabled': true,
        'lowPowerStandbyExempt': false,
      };
      expect(
        android.statusText(t, true, lowPowerStandby),
        'Low Power Standby restricts network access while locked',
      );
      expect(android.recoverySettings(lowPowerStandby), isNull);
      expect(
        BackgroundReceiving.desktopTray.statusText(t, true, {
          'running': true,
          'trayAvailable': false,
        }),
        'Keep the window open',
      );
    },
  );

  testWidgets(
    'settings show unknown status and refresh after toggling background receiving',
    (tester) async {
      SharedPreferences.setMockInitialValues({'background_receive_test': true});
      final messenger = tester.binding.defaultBinaryMessenger;
      var statusUnavailable = true;
      var running = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'status') {
          if (statusUnavailable) throw PlatformException(code: 'unavailable');
          return {'running': running, 'nodeReady': true, 'notifications': true};
        }
        if (call.method == 'stop') running = false;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(
            profile: 'test',
            language: 'en',
            appearance: 'light',
            deviceName: 'Phone',
            systemDeviceName: 'Phone',
            changeSetting: (_, _) async {},
            rename: (_) async {},
            relaySettings: () async {},
            diagnostics: () async {},
            backgroundChanged: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Status unknown'), findsOneWidget);
      statusUnavailable = false;
      await tester.tap(find.text('Background receiving'));
      await tester.pumpAndSettle();
      final service = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile).first,
      );
      expect(service.value, isTrue);
      expect(service.subtitle, isNull);
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Off'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  Future<void> showPage(
    WidgetTester tester,
    Future<void> Function() onChanged,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BackgroundSettingsPage(profile: 'test', onChanged: onChanged),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showDesktopSettings(
    WidgetTester tester,
    Future<void> Function() onChanged,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(
          profile: 'test',
          language: 'en',
          appearance: 'light',
          deviceName: 'Computer',
          systemDeviceName: 'Computer',
          changeSetting: (_, _) async {},
          rename: (_) async {},
          relaySettings: () async {},
          diagnostics: () async {},
          backgroundChanged: onChanged,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (restricted, exempt, manufacturer) in [
    (false, false, 'Google'),
    (true, false, 'Google'),
    (false, true, 'Google'),
    (false, true, 'OnePlus'),
    (true, true, 'OPPO'),
    (false, false, 'realme'),
  ]) {
    testWidgets(
      'Android battery controls keep the two settings distinct ($restricted, $exempt, $manufacturer)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'background_receive_test': true,
        });
        final messenger = tester.binding.defaultBinaryMessenger;
        String? opened;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'status') {
            return {
              'running': !restricted,
              'nodeReady': !restricted,
              'allNotifications': false,
              'notifications': false,
              'batteryExempt': exempt,
              'restricted': restricted,
              'manufacturer': manufacturer,
            };
          }
          if (call.method == 'settings') {
            opened = (call.arguments as Map)['section'] as String;
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await showPage(tester, () async {});
        final battery = find.widgetWithText(
          ListTile,
          'Battery optimization exemption',
        );
        final restriction = find.widgetWithText(
          ListTile,
          'System background restrictions',
        );
        final oplusBattery = find.widgetWithText(
          ListTile,
          'Battery usage and auto-start',
        );
        expect(find.text('Incoming requests'), findsNothing);
        expect(
          find.descendant(
            of: battery,
            matching: find.text(exempt ? 'Exempt' : 'Not exempt'),
          ),
          findsOneWidget,
        );
        await tester.tap(battery);
        await tester.pump();
        expect(opened, 'battery_exemption');
        if (manufacturer != 'Google') {
          expect(restriction, findsNothing);
          expect(find.text('Auto-start settings'), findsNothing);
          await tester.tap(oplusBattery);
          await tester.pump();
          expect(opened, 'battery');
        } else if (restricted) {
          await tester.tap(restriction);
          await tester.pump();
          expect(opened, 'battery');
        } else {
          expect(restriction, findsNothing);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'desktop background and login controls use desktop native methods',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final calls = <String>[];
      var login = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'desktopStatus') {
          return {
            'running': true,
            'trayAvailable': true,
            'loginSupported': true,
            'loginStatus': login ? 'enabled' : 'notRegistered',
          };
        }
        if (call.method == 'setLaunchAtLogin') {
          login = call.arguments as bool;
          return login ? 'enabled' : 'notRegistered';
        }
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      var changed = false;
      await showDesktopSettings(tester, () async => changed = true);
      final receive = find.widgetWithText(
        SwitchListTile,
        'Background receiving',
      );
      await tester.ensureVisible(receive);
      expect(tester.widget<SwitchListTile>(receive).value, isTrue);
      await tester.tap(receive);
      await tester.pumpAndSettle();
      expect(changed, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'desktop_background_receiving',
        ),
        isFalse,
      );
      expect(calls, contains('setDesktopBackground'));
      final loginSwitch = find.widgetWithText(SwitchListTile, 'Open at login');
      await tester.ensureVisible(loginSwitch);
      await tester.tap(loginSwitch);
      await tester.pumpAndSettle();
      expect(login, isTrue);
      expect(calls, isNot(contains('start')));
      expect(calls, isNot(contains('status')));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('OnePlus battery and auto-start settings do not guess status', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    String? section;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'status') {
        return {'manufacturer': 'OnePlus', 'bootRecovery': 'broadcast'};
      }
      if (call.method == 'settings') {
        section = (call.arguments as Map)['section'] as String?;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await showPage(tester, () async {});
    final settings = find.text('Battery usage and auto-start');
    expect(settings.hitTestable(), findsOneWidget);
    expect(find.text('Boot signal received'), findsNothing);
    expect(find.text('Unverified'), findsNothing);
    await tester.tap(settings);
    await tester.pump();
    expect(section, 'battery');
  });

  testWidgets(
    'notifies the active app immediately after enabling and disabling background receive',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'background_receive_test': false,
      });
      final prefs = await SharedPreferences.getInstance();
      var running = false;
      final observed = <bool?>[];
      final serviceSaw = <bool?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'status') return {'running': running};
        if (call.method == 'start') {
          serviceSaw.add(prefs.getBool('background_receive_test'));
          running = true;
          return true;
        }
        if (call.method == 'stop') {
          serviceSaw.add(prefs.getBool('background_receive_test'));
          running = false;
          return null;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await showPage(tester, () async {
        observed.add(
          (await SharedPreferences.getInstance()).getBool(
            'background_receive_test',
          ),
        );
      });
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(observed, [true]);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(running, isTrue);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(observed, [true, false]);
      expect(serviceSaw, [true, false]);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(running, isFalse);
    },
  );

  testWidgets(
    'a rejected service start does not notify monitoring or persist enabled',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'background_receive_test': false,
      });
      final prefs = await SharedPreferences.getInstance();
      var notifications = 0;
      bool? valueWhenStarting;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'status') return {'running': false};
        if (call.method == 'start') {
          valueWhenStarting = prefs.getBool('background_receive_test');
          return false;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await showPage(tester, () async {
        notifications++;
      });
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(valueWhenStarting, isTrue);
      expect(notifications, 0);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'background_receive_test',
        ),
        isFalse,
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
    },
  );

  testWidgets(
    'a failed service stop restores the previous preference and service',
    (tester) async {
      SharedPreferences.setMockInitialValues({'background_receive_test': true});
      final prefs = await SharedPreferences.getInstance();
      var running = true;
      var notifications = 0;
      final observed = <(String, bool?)>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'status') return {'running': running};
        if (call.method == 'stop') {
          observed.add(('stop', prefs.getBool('background_receive_test')));
          running = false;
          throw PlatformException(code: 'failed');
        }
        if (call.method == 'start') {
          observed.add(('start', prefs.getBool('background_receive_test')));
          running = true;
          return true;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await showPage(tester, () async {
        notifications++;
      });
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(observed, [('stop', false), ('start', true)]);
      expect(prefs.getBool('background_receive_test'), isTrue);
      expect(running, isTrue);
      expect(notifications, 0);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    },
  );

  testWidgets(
    'a monitoring sync failure rolls back the service and resynchronizes',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'background_receive_test': false,
      });
      final prefs = await SharedPreferences.getInstance();
      var running = false;
      final observed = <bool?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'status') return {'running': running};
        if (call.method == 'start') {
          running = true;
          return true;
        }
        if (call.method == 'stop') {
          running = false;
          return null;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await showPage(tester, () async {
        observed.add(prefs.getBool('background_receive_test'));
        if (observed.length == 1) throw StateError('monitoring did not start');
      });
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(observed, [true, false]);
      expect(prefs.getBool('background_receive_test'), isFalse);
      expect(running, isFalse);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
    },
  );

  for (final throws in [false, true]) {
    testWidgets(
      'a preference write ${throws ? 'exception' : 'failure'} restores the cache without starting the service',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        SharedPreferencesStorePlatform.instance = FailingFirstWriteStore(
          throws,
        );
        final prefs = await SharedPreferences.getInstance();
        var serviceStarts = 0;
        var notifications = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'status') return {'running': false};
            if (call.method == 'start') {
              serviceStarts++;
              return true;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );

        await showPage(tester, () async {
          notifications++;
        });
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(serviceStarts, 0);
        expect(notifications, 0);
        expect(
          prefs.getBool('background_receive_test'),
          isFalse,
          reason: 'a failed setBool mutates the Dart cache before the platform write completes',
        );
        await prefs.reload();
        expect(prefs.getBool('background_receive_test'), isFalse);
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isFalse,
        );
      },
    );
  }
  testWidgets(
    'Mac settings expose background receiving and launch at login directly',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'mac_background_receiving': false,
      });
      var active = false;
      var login = 'notFound';
      var changes = 0;
      String? opened;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'macBackgroundStatus') {
          return {
            'active': active,
            'loginSupported': true,
            'loginStatus': login,
            'notifications': false,
          };
        }
        if (call.method == 'setMacBackground') {
          active = call.arguments as bool;
          return null;
        }
        if (call.method == 'setLaunchAtLogin') {
          login = 'requiresApproval';
          return login;
        }
        if (call.method == 'settings') {
          opened = (call.arguments as Map)['section'] as String;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await showDesktopSettings(tester, () async {
        changes++;
      });
      final receive = find.widgetWithText(
        SwitchListTile,
        'Background receiving',
      );
      await tester.ensureVisible(receive);
      await tester.tap(receive);
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'mac_background_receiving',
        ),
        isTrue,
      );
      expect(active, isTrue);
      expect(changes, 1);
      expect(find.text('Incoming requests'), findsNothing);
      final loginSwitch = find.widgetWithText(SwitchListTile, 'Open at login');
      expect(tester.widget<SwitchListTile>(loginSwitch).onChanged, isNotNull);
      expect(tester.widget<SwitchListTile>(loginSwitch).subtitle, isNull);
      expect(find.text('Open Login Items'), findsNothing);
      await tester.ensureVisible(loginSwitch);
      await tester.tap(loginSwitch);
      await tester.pumpAndSettle();
      expect(
        find.text('Allow launch at login in System Settings'),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.text('Allow launch at login in System Settings'),
          matching: find.byType(SnackBar),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Open Login Items'));
      await tester.pump();
      expect(opened, 'login');
      expect(find.text('Open Login Items'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('Mac keep-awake failure rolls back its setting', (tester) async {
    SharedPreferences.setMockInitialValues({'mac_background_receiving': false});
    var active = false;
    var changes = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'macBackgroundStatus') {
        return {
          'active': active,
          'loginSupported': false,
          'loginStatus': 'unsupported',
        };
      }
      if (call.method == 'setMacBackground') {
        active = call.arguments as bool;
        if (active) throw PlatformException(code: 'power_failed');
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await showDesktopSettings(tester, () async {
      changes++;
    });
    final receive = find.widgetWithText(SwitchListTile, 'Background receiving');
    await tester.ensureVisible(receive);
    await tester.tap(receive);
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'mac_background_receiving',
      ),
      isFalse,
    );
    expect(active, isFalse);
    expect(changes, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'Android lists actionable permissions instead of internal service checks',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'status') {
          return {
            'lowPowerStandbyEnabled': true,
            'lowPowerStandbyExempt': null,
          };
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await showPage(tester, () async {});
      expect(find.text('Low Power Standby exemption'), findsNothing);
      expect(
        find.text('Battery optimization exemption').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Incoming requests'), findsNothing);
      expect(find.text('Low Power Standby exemption'), findsNothing);
      expect(find.text('Receiving service'), findsNothing);
      expect(find.text('Receiving node'), findsNothing);
    },
  );
}
