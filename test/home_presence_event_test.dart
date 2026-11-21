import 'dart:async';
import 'dart:io';

import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/main.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'peer_test_utils.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets(
    'home uses current authenticated snapshots for status while fresh checks only control the spinner',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync(
        'vela-home-presence-test-',
      );
      final node = FakeNode();
      final database = GatedDatabaseFactory(databaseFactoryFfi);
      databaseFactory = database;
      await seedPeerState(
        tester,
        dir,
        PeerState(peers: {peerId: 'Phone'}, types: {peerId: 'mobile'}),
      );
      SharedPreferences.setMockInitialValues({'device_view_test': 'list'});
      final api = FakeRustApi(node);
      RustLib.initMock(api: api);
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const secureChannel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const backgroundChannel = MethodChannel('vela/background');
      List<Object?> menuDevices = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        backgroundChannel,
        (call) async {
          if (call.method == 'setMenuDevices') {
            menuDevices = call.arguments as List<Object?>;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          backgroundChannel,
          null,
        );
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathChannel,
        (call) async => dir.path,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        secureChannel,
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
              diagnosticsEnabled: true,
              changeDiagnosticsEnabled: (_) async {},
            ),
          ),
        );
        for (
          var i = 0;
          i < 100 &&
              find
                  .byKey(const ValueKey('device-presence-check'))
                  .evaluate()
                  .isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.text('Phone'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('device-presence-check')),
          findsOneWidget,
        );

        const online = DeviceInfo(name: 'Phone', deviceType: 'mobile');
        node.fresh.complete(online);
        await tester.pump();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('device-presence-check')),
          findsNothing,
        );
        expect(
          find.byTooltip('Temporarily unreachable'),
          findsOneWidget,
          reason: 'fresh check completion alone must not override the authoritative offline snapshot',
        );

        node.publish(info: online, proofValidUntilNs: BigInt.from(999999999));
        await tester.pump();
        expect(
          find.byTooltip('Reachable'),
          findsNothing,
          reason: 'a proof that expired before delivery must never briefly turn green',
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        expect(
          find.byTooltip('Temporarily unreachable'),
          findsOneWidget,
          reason: 'a proof that expired before delivery must not turn green',
        );

        node.publish(info: online, proofValidUntilNs: BigInt.from(9000000000));
        await tester.pump();
        expect(
          find.byTooltip('Reachable'),
          findsOneWidget,
          reason: 'an event should update the indicator without waiting for a 250 ms polling tick',
        );
        expect(find.text('Reachable'), findsNothing);
        if (Platform.isMacOS) {
          expect(menuDevices, [
            {'name': 'Phone', 'presence': 'reachable', 'label': 'Reachable'},
          ]);
        }

        // A temporarily unavailable proof clock must not leave the device
        // offline forever when no new snapshot revision arrives.
        final freshCallsBeforeClockFailure = node.freshCalls.length;
        api.clockNow = (BigInt.one << 64) - BigInt.one;
        node.publish(info: online, proofValidUntilNs: BigInt.from(9000000000));
        await tester.pump();
        expect(find.byTooltip('Reachable'), findsNothing);
        api.clockNow = BigInt.from(1000000000);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        expect(
          find.byTooltip('Reachable'),
          findsOneWidget,
          reason:
              'clock recovery must re-read the snapshot without a new revision',
        );
        expect(
          node.freshCalls.length,
          freshCallsBeforeClockFailure,
          reason: 'clock recovery only reads local state and must not probe the network',
        );

        // A later snapshot may restore the old name while an intermediate name
        // is still being persisted. The last snapshot must win on disk and UI.
        database.gateNextWrite = true;
        node.publish(
          info: const DeviceInfo(name: 'Temporary', deviceType: 'mobile'),
          proofValidUntilNs: BigInt.from(9000000000),
        );
        for (var i = 0; i < 100 && !database.writeStarted.isCompleted; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(database.writeStarted.isCompleted, isTrue);
        node.publish(info: online, proofValidUntilNs: BigInt.from(9000000000));
        await tester.pump();
        database.releaseWrite.complete();
        for (var i = 0; i < 100 && database.writesAfterGate < 2; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(database.writesAfterGate, greaterThanOrEqualTo(2));
        await tester.pump();
        expect(find.text('Phone'), findsOneWidget);
        expect(find.text('Temporary'), findsNothing);
        final dynamic homeState = tester.state(find.byType(HomePage));
        expect((homeState.peerState as PeerState).peers[peerId], 'Phone');
        expect(
          PeerState.decode(database.lastSavedValue!).peers[peerId],
          'Phone',
        );

        await tester.tap(find.byKey(const ValueKey('refresh-devices')));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('device-presence-check')),
          findsOneWidget,
        );
        expect(node.freshCalls.length, 2);
        node.holdWatch = true;
        node.publish(info: null, proofValidUntilNs: null);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('device-presence-check')),
          findsOneWidget,
        );
        node.freshCalls.last.complete(online);
        await tester.pump();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('device-presence-check')),
          findsNothing,
        );
        expect(
          find.byTooltip('Temporarily unreachable'),
          findsOneWidget,
          reason: 'fresh completion must read the newest snapshot before removing the spinner, even when the watch is delayed',
        );
        if (Platform.isMacOS) {
          expect(menuDevices, [
            {
              'name': 'Phone',
              'presence': 'unavailable',
              'label': 'Temporarily unreachable',
            },
          ]);
        }
        node.holdWatch = false;
        node.releaseWatch.complete();
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('peer-$peerId')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final sheet = find.byType(BottomSheet);
        expect(
          find.descendant(
            of: sheet,
            matching: find.text('Temporarily unreachable'),
          ),
          findsNothing,
        );
        final dot = find.descendant(
          of: sheet,
          matching: find.byIcon(Icons.circle),
        );
        expect(tester.widget<Icon>(dot).color, Colors.red.shade600);
        await tester.tap(
          find.descendant(
            of: sheet,
            matching: find.byTooltip('Refresh this device'),
          ),
        );
        await tester.pump();
        expect(node.freshCalls.length, 3);
        expect(
          find.descendant(of: sheet, matching: find.text('Checking')),
          findsNothing,
        );
        expect(dot, findsNothing);
        node.publish(info: online, proofValidUntilNs: BigInt.from(9000000000));
        node.freshCalls.last.complete(online);
        await tester.pump();
        await tester.pump();
        expect(tester.widget<Icon>(dot).color, Colors.green.shade700);
        expect(
          find.descendant(of: sheet, matching: find.text('Reachable')),
          findsNothing,
        );
        Navigator.of(tester.element(sheet)).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        // A snapshot from the old relationship must not delete a new pairing.
        node.releaseWatch = Completer<void>();
        node.watchHeld = false;
        node.holdWatch = true;
        node.publish(info: null, proofValidUntilNs: null, unpaired: true);
        await tester.pump();
        expect(node.watchHeld, isTrue);
        await tester.tap(find.byKey(const ValueKey('peer-$peerId')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove device'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove').last);
        for (
          var i = 0;
          i < 100 &&
              find.byKey(const ValueKey('peer-$peerId')).evaluate().isNotEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.byKey(const ValueKey('peer-$peerId')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('add-device')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('peer-id')), peerId);
        await tester.tap(find.byKey(const ValueKey('confirm-peer')));
        for (
          var i = 0;
          i < 100 &&
              find.byKey(const ValueKey('peer-$peerId')).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.byKey(const ValueKey('peer-$peerId')), findsOneWidget);
        node.holdWatch = false;
        node.releaseWatch.complete();
        await tester.pump();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('peer-$peerId')),
          findsOneWidget,
          reason: 'a delayed unpaired snapshot from before re-pairing must be ignored',
        );
        expect(node.unpairedTaken, 0);

        node.releaseWatch = Completer<void>();
        node.watchHeld = false;
        node.holdWatch = true;
        node.publish(info: online, proofValidUntilNs: BigInt.from(9000000000));
        await tester.pump();
        expect(node.watchHeld, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.detached,
        );
        await tester.pump();
        expect(node.monitoring, isFalse);
        node.publish(info: null, proofValidUntilNs: null);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        for (final check in node.freshCalls.where((c) => !c.isCompleted)) {
          check.complete(online);
        }
        await tester.pump();
        await tester.pump();
        expect(node.monitoring, isTrue);
        expect(find.byTooltip('Temporarily unreachable'), findsOneWidget);
        node.holdWatch = false;
        node.releaseWatch.complete();
        await tester.pump();
        expect(
          find.byTooltip('Reachable'),
          findsNothing,
          reason: 'a snapshot issued before monitoring stopped must not revive stale state after resume',
        );
      } finally {
        if (!database.releaseWrite.isCompleted) {
          database.releaseWrite.complete();
        }
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        RustLib.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pathChannel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          secureChannel,
          null,
        );
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    },
  );

  testWidgets(
    'home waits for monitoring to start before fresh checking and does not show stale status',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync(
        'vela-home-presence-test-',
      );
      final gate = Completer<void>();
      final node = FakeNode(enableGate: gate);
      final database = GatedDatabaseFactory(databaseFactoryFfi);
      databaseFactory = database;
      await seedPeerState(tester, dir, PeerState(peers: {peerId: 'Phone'}));
      SharedPreferences.setMockInitialValues({'device_view_test': 'list'});
      RustLib.initMock(api: FakeRustApi(node));
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const secureChannel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathChannel,
        (call) async => dir.path,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        secureChannel,
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
              diagnosticsEnabled: true,
              changeDiagnosticsEnabled: (_) async {},
            ),
          ),
        );
        for (var i = 0; i < 100 && !node.enableStarted.isCompleted; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(node.enableStarted.isCompleted, isTrue);
        expect(
          find.byKey(const ValueKey('device-presence-check')),
          findsOneWidget,
        );
        expect(find.byTooltip('Reachable'), findsNothing);
        expect(find.byTooltip('Temporarily unreachable'), findsNothing);
        expect(
          node.freshCalls,
          isEmpty,
          reason: 'fresh checks cannot run before monitoring is ready',
        );

        gate.complete();
        await tester.pump();
        await tester.pump();
        expect(node.freshCalls.length, 1);
        const online = DeviceInfo(name: 'Phone', deviceType: 'mobile');
        node.publish(info: online, proofValidUntilNs: BigInt.from(9000000000));
        node.fresh.complete(online);
        await tester.pump();
        await tester.pump();
        expect(find.byTooltip('Reachable'), findsOneWidget);
        database.failNextWrite = true;
        node.publish(info: null, proofValidUntilNs: null, unpaired: true);
        for (
          var i = 0;
          i < 100 && (database.failedWrites == 0 || !node.peerTrusted);
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(database.failedWrites, 1);
        expect(
          node.peerTrusted,
          isTrue,
          reason: 'failed persistence must restore native trust',
        );
        expect(find.byKey(const ValueKey('peer-$peerId')), findsOneWidget);
        await tester.pump();
        await tester.pump();

        node.failTrustOnCall = node.trustCalls + 2;
        node.publish(info: null, proofValidUntilNs: null, unpaired: true);
        for (
          var i = 0;
          i < 100 &&
              (find
                      .byKey(const ValueKey('peer-$peerId'))
                      .evaluate()
                      .isNotEmpty ||
                  node.failedTrustCalls == 0);
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(
          node.unpairedTaken,
          2,
          reason: 'the later unpaired snapshot must be consumed',
        );
        expect(
          find.byKey(const ValueKey('peer-$peerId')),
          findsNothing,
          reason: 'an authenticated unpaired snapshot removes the device',
        );
        expect(node.failedTrustCalls, 1);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(
          node.trustCalls,
          greaterThan(node.failTrustOnCall!),
          reason: 'a failed post-save trust update must be retried',
        );
        expect(
          find.byKey(const ValueKey('peer-$peerId')),
          findsNothing,
          reason: 'the committed removal must survive a trust sync failure',
        );
      } finally {
        if (!gate.isCompleted) gate.complete();
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        RustLib.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pathChannel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          secureChannel,
          null,
        );
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    },
  );
}
