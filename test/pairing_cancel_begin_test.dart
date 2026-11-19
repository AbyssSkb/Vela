import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/main.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/frb_generated.dart';

import 'support/fakes.dart'
    show FakeNode, FakeRustApi, GatedDatabaseFactory, peerId;
import 'peer_test_utils.dart';

class TrackingPairing implements OutgoingPairing {
  int cancels = 0;
  int requests = 0;
  @override
  void cancel() {
    cancels++;
  }

  @override
  Future<DeviceInfo> request({
    required String name,
    required String deviceType,
  }) async {
    requests++;
    return const DeviceInfo(name: 'Phone', deviceType: 'mobile');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class GatedBeginNode extends FakeNode {
  final started = Completer<void>();
  final release = Completer<OutgoingPairing>();
  final pendingChanges = <bool>[];
  @override
  Future<OutgoingPairing> beginOutgoingPairing({required String peerId}) {
    started.complete();
    return release.future;
  }

  @override
  Future<void> beginPairing({required String peerId}) async {
    pendingChanges.add(true);
  }

  @override
  Future<void> endPairing({required String peerId}) async {
    pendingChanges.add(false);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    'cancel before outgoing pairing handle returns stops the request',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('vela-cancel-begin-');
      final node = GatedBeginNode();
      final handle = TrackingPairing();
      databaseFactory = databaseFactoryFfi;
      await seedPeerState(tester, dir, PeerState(peers: {peerId: 'Phone'}));
      SharedPreferences.setMockInitialValues({'device_view_test': 'list'});
      RustLib.initMock(api: FakeRustApi(node));
      const path = MethodChannel('plugins.flutter.io/path_provider');
      const secure = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        path,
        (_) async => dir.path,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        secure,
        (_) async => null,
      );
      Future<void> waitUntil(bool Function() ready) async {
        for (var i = 0; i < 100 && !ready(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(ready(), isTrue);
      }

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
        await waitUntil(
          () =>
              find.byKey(const ValueKey('peer-$peerId')).evaluate().isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('add-device')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byKey(const ValueKey('peer-id')), peerId);
        await tester.tap(find.byKey(const ValueKey('confirm-peer')));
        await waitUntil(() => node.started.isCompleted);
        expect(node.pendingChanges, [true]);
        await waitUntil(
          () => find
              .byKey(const ValueKey('cancel-pairing'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('cancel-pairing')));
        await tester.pump();
        expect(handle.cancels, 0);
        expect(handle.requests, 0);
        node.release.complete(handle);
        await waitUntil(
          () => node.pendingChanges.isNotEmpty && !node.pendingChanges.last,
        );
        expect(handle.cancels, greaterThanOrEqualTo(1));
        expect(handle.requests, 0);
        expect(node.pendingChanges, [true, false]);
        await waitUntil(
          () => find.byKey(const ValueKey('cancel-pairing')).evaluate().isEmpty,
        );
      } finally {
        if (!node.release.isCompleted) node.release.complete(handle);
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
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    },
  );

  testWidgets('failed peer save cancels outgoing pairing and reports failure', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('vela-pair-save-failure-');
    final node = GatedBeginNode();
    final handle = TrackingPairing();
    final database = GatedDatabaseFactory(databaseFactoryFfi);
    databaseFactory = database;
    await seedPeerState(tester, dir, PeerState());
    SharedPreferences.setMockInitialValues({'device_view_test': 'list'});
    RustLib.initMock(api: FakeRustApi(node));
    const path = MethodChannel('plugins.flutter.io/path_provider');
    const secure = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      path,
      (_) async => dir.path,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      secure,
      (_) async => null,
    );
    Future<void> waitUntil(bool Function() ready) async {
      for (var i = 0; i < 100 && !ready(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(ready(), isTrue);
    }

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
      await waitUntil(() => home.node != null);
      await tester.tap(find.byKey(const ValueKey('add-device')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byKey(const ValueKey('peer-id')), peerId);
      await tester.tap(find.byKey(const ValueKey('confirm-peer')));
      await waitUntil(() => node.started.isCompleted);
      database.failNextWrite = true;
      node.release.complete(handle);
      await waitUntil(
        () =>
            database.failedWrites == 1 &&
            node.pendingChanges.isNotEmpty &&
            !node.pendingChanges.last,
      );
      expect(handle.requests, 1);
      expect(handle.cancels, greaterThanOrEqualTo(1));
      expect(node.pendingChanges, [true, false]);
      await waitUntil(
        () => find.byKey(const ValueKey('cancel-pairing')).evaluate().isEmpty,
      );
      await tester.pump();
      expect(
        find.text(
          'Could not connect. Check the device code and make sure Vela is open and online on both devices.',
        ),
        findsOneWidget,
      );
      expect(find.text('Added Phone'), findsNothing);
      expect(find.byKey(const ValueKey('peer-$peerId')), findsNothing);
      expect(node.peerTrusted, isFalse);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('notice-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('peer-id')))
            .controller
            ?.text,
        peerId,
      );
    } finally {
      if (!node.release.isCompleted) node.release.complete(handle);
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
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });
}
