import 'dart:async';

import 'package:vela/diagnostics_page.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> clearEvents(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('diagnostics-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diagnostics-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diagnostics-confirm-clear')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'diagnostics offers the next action for an unavailable node or peer',
    (tester) async {
      var ready = false;
      var reachable = 0;
      var guideOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: DiagnosticsPage(
            load: () async => DiagnosticsSnapshot(
              nodeReady: ready,
              peerCount: 1,
              reachableCount: reachable,
              relayCount: 1,
              readyRelayCount: 1,
              events: [],
              unreachableDeviceNames: ready && reachable == 0
                  ? ['Travel phone']
                  : [],
            ),
            retryStartup: () async => ready = true,
            refreshDevices: () async => reachable = 1,
            clear: () async {},
            initialEnabled: false,
            setEnabled: (_) async {},
            openGuide: () => guideOpened = true,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Try starting Vela again'));
      await tester.pumpAndSettle();
      expect(find.text('0 / 1'), findsOneWidget);
      expect(
        find.text('Temporarily unreachable · Travel phone'),
        findsOneWidget,
      );
      await tester.tap(find.text('User guide'));
      expect(guideOpened, isTrue);
      await tester.tap(find.text('Refresh device status'));
      await tester.pumpAndSettle();
      expect(find.text('Refresh device status'), findsNothing);
      expect(find.text('Try starting Vela again'), findsNothing);
      expect(find.text('1 / 1'), findsNWidgets(2));
    },
  );

  test(
    'connection events show readable device status without internal fields',
    () {
      DiagnosticEvent event(
        String kind, {
        String details = '',
        int trace = 7,
      }) => DiagnosticEvent(
        timestampMs: BigInt.from(1760000000000),
        monotonicMs: BigInt.from(42),
        kind: kind,
        details: details,
        trace: BigInt.from(trace),
        attempt: BigInt.from(2),
        elapsedMs: BigInt.from(1234),
        rttMs: BigInt.from(50),
        pingFailures: BigInt.zero,
        relaysBefore: 1,
        relaysAfter: 2,
      );
      final events = describeConnectionEvents(
        [
          event('dial_start', details: '{"peer_id":"secret-device-id"}'),
          event('path_ip', details: '{"remote":"192.0.2.5"}'),
          event('dial_connected', details: 'internal details'),
          event('dial_failed', details: '192.0.2.5'),
          event('dial_timeout', trace: 99),
          event('session_closed'),
        ],
        {'secret-device-id': 'Phone'},
        chinese: true,
      );
      expect(events.map((event) => event.$3), [
        'Phone：连接已建立',
        'Phone：连接失败',
        '设备连接超时',
        'Phone：连接已断开',
      ]);
      final text = events.map((event) => event.$3).join(' ');
      expect(text, isNot(contains('192.0.2.5')));
      expect(text, isNot(contains('secret-device-id')));
      expect(text, isNot(contains('42')));
    },
  );

  testWidgets(
    'long diagnostics list builds on demand and preserves all copied events',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final events = List.generate(120, (index) => 'event-$index');
      Future<DiagnosticsSnapshot> load() async => DiagnosticsSnapshot(
        nodeReady: true,
        peerCount: 0,
        reachableCount: 0,
        relayCount: 0,
        readyRelayCount: 0,
        events: events,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: DiagnosticsPage(
            load: load,
            clear: () async {},
            initialEnabled: true,
            setEnabled: (_) async {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('event-119'), findsOneWidget);
      expect(find.text('event-0'), findsNothing);
      expect(
        find.byType(SelectableText).evaluate().length,
        lessThan(events.length),
      );
      await tester.tap(find.byKey(const ValueKey('diagnostics-copy')));
      await tester.pump();
      expect(copied, contains('event-0'));
      expect(copied, contains('event-119'));
      await tester.scrollUntilVisible(
        find.text('event-0'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('event-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('displays and copies diagnostics, then clears events', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    var events = [
      '00:01 relay {"url":"https://relay.example.com","error":"connection refused"}',
      '00:02 status updated',
    ];
    var failRefresh = false;
    Future<DiagnosticsSnapshot> load() async {
      if (failRefresh) throw StateError('could not refresh');
      return DiagnosticsSnapshot(
        nodeReady: true,
        peerCount: 2,
        reachableCount: 1,
        relayCount: 1,
        readyRelayCount: null,
        events: List.of(events),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: DiagnosticsPage(
          load: load,
          clear: () async => events = [],
          initialEnabled: true,
          setEnabled: (_) async {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('— / 1'), findsOneWidget);
    expect(find.text(events.first), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('00:02 status updated')).dy,
      lessThan(tester.getTopLeft(find.text(events.first)).dy),
    );
    expect(find.textContaining('Updated at '), findsOneWidget);
    failRefresh = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.textContaining('Refresh failed'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    failRefresh = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.textContaining('Refresh failed'), findsNothing);
    expect(find.textContaining('Updated at '), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diagnostics-copy')));
    await tester.pump();
    expect(copied, contains('Reachable devices: 1 / 2'));
    expect(copied, contains(events.first));
    expect(
      copied!.indexOf(events.first),
      lessThan(copied!.indexOf('00:02 status updated')),
    );
    expect(find.text('Copied'), findsOneWidget);
    await clearEvents(tester);
    await tester.pump();
    expect(find.text('No events'), findsOneWidget);
    expect(
      find.text(
        '00:01 relay {"url":"https://relay.example.com","error":"connection refused"}',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing discards an older in-flight snapshot', (tester) async {
    var events = ['旧事件'];
    var loads = 0;
    final old = Completer<DiagnosticsSnapshot>();
    DiagnosticsSnapshot current() => DiagnosticsSnapshot(
      nodeReady: true,
      peerCount: 1,
      reachableCount: 1,
      relayCount: 0,
      readyRelayCount: null,
      events: List.of(events),
    );
    Future<DiagnosticsSnapshot> load() {
      loads++;
      return loads == 2 ? old.future : Future.value(current());
    }

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: DiagnosticsPage(
          load: load,
          clear: () async => events = [],
          initialEnabled: true,
          setEnabled: (_) async {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('诊断'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await clearEvents(tester);
    await tester.pump();
    expect(find.text('暂无事件'), findsOneWidget);
    old.complete(
      DiagnosticsSnapshot(
        nodeReady: true,
        peerCount: 1,
        reachableCount: 1,
        relayCount: 0,
        readyRelayCount: null,
        events: const ['旧事件'],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('旧事件'), findsNothing);
    expect(find.text('暂无事件'), findsOneWidget);
  });

  testWidgets('logging switch saves changes and keeps earlier events', (
    tester,
  ) async {
    final events = ['earlier event'];
    var enabled = true;
    Future<DiagnosticsSnapshot> load() async => DiagnosticsSnapshot(
      nodeReady: true,
      peerCount: 0,
      reachableCount: 0,
      relayCount: 0,
      readyRelayCount: 0,
      events: events,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: DiagnosticsPage(
          load: load,
          clear: () async => events.clear(),
          initialEnabled: enabled,
          setEnabled: (value) async => enabled = value,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diagnostics-enabled')));
    await tester.pump();
    expect(enabled, isFalse);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('diagnostics-enabled')),
          )
          .value,
      isFalse,
    );
    expect(find.text('earlier event'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diagnostics-enabled')));
    await tester.pump();
    expect(enabled, isTrue);
    expect(find.text('earlier event'), findsOneWidget);
  });

  testWidgets(
    'logging switch stays unchanged when the setting cannot be saved',
    (tester) async {
      Future<DiagnosticsSnapshot> load() async => const DiagnosticsSnapshot(
        nodeReady: true,
        peerCount: 0,
        reachableCount: 0,
        relayCount: 0,
        readyRelayCount: 0,
        events: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: DiagnosticsPage(
            load: load,
            clear: () async {},
            initialEnabled: true,
            setEnabled: (_) async => throw StateError('save failed'),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('diagnostics-enabled')));
      await tester.pump();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('diagnostics-enabled')),
            )
            .value,
        isTrue,
      );
      expect(find.text('Could not save setting'), findsOneWidget);
    },
  );

  testWidgets('logging switch updates immediately while saving', (
    tester,
  ) async {
    final pending = Completer<void>();
    Future<DiagnosticsSnapshot> load() async => const DiagnosticsSnapshot(
      nodeReady: true,
      peerCount: 0,
      reachableCount: 0,
      relayCount: 0,
      readyRelayCount: 0,
      events: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: DiagnosticsPage(
          load: load,
          clear: () async {},
          initialEnabled: false,
          setEnabled: (_) => pending.future,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diagnostics-enabled')));
    await tester.pump();
    var tile = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('diagnostics-enabled')),
    );
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNull);
    pending.complete();
    await tester.pump();
    tile = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('diagnostics-enabled')),
    );
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNotNull);
  });

  testWidgets('logging switch rolls back after a delayed save failure', (
    tester,
  ) async {
    final pending = Completer<void>();
    Future<DiagnosticsSnapshot> load() async => const DiagnosticsSnapshot(
      nodeReady: true,
      peerCount: 0,
      reachableCount: 0,
      relayCount: 0,
      readyRelayCount: 0,
      events: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: DiagnosticsPage(
          load: load,
          clear: () async {},
          initialEnabled: false,
          setEnabled: (_) => pending.future,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diagnostics-enabled')));
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('diagnostics-enabled')),
          )
          .value,
      isTrue,
    );
    pending.completeError(StateError('save failed'));
    await tester.pump();
    final tile = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('diagnostics-enabled')),
    );
    expect(tile.value, isFalse);
    expect(tile.onChanged, isNotNull);
    expect(find.text('Could not save setting'), findsOneWidget);
  });

  testWidgets('logging switch reflects a saved disabled setting', (
    tester,
  ) async {
    Future<DiagnosticsSnapshot> load() async => const DiagnosticsSnapshot(
      nodeReady: true,
      peerCount: 0,
      reachableCount: 0,
      relayCount: 0,
      readyRelayCount: 0,
      events: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: DiagnosticsPage(
          load: load,
          clear: () async {},
          initialEnabled: false,
          setEnabled: (_) async {},
        ),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('diagnostics-enabled')),
          )
          .value,
      isFalse,
    );
  });
}
