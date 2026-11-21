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

import 'support/fakes.dart' show FakeNode, FakeRustApi, peerId;
import 'peer_test_utils.dart';
import 'support/home_environment.dart';

class PairOffer implements IncomingRequest {
  final closed = Completer<void>();
  bool accepted = false;

  @override
  Future<void> acceptPair({
    required String name,
    required String deviceType,
  }) async {
    accepted = true;
  }

  @override
  IncomingRequestInfo info() => IncomingRequestInfo(
    name: 'Phone',
    size: BigInt.zero,
    sender: peerId,
    kind: '',
    pairing: const DeviceInfo(name: 'Phone', deviceType: 'mobile'),
    files: const [],
  );
  @override
  Future<void> decline() async {}
  @override
  Future<void> declinePairConflict() async {}
  @override
  Future<void> waitForConnectionClose() => closed.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PairRaceNode extends FakeNode {
  final first = Completer<IncomingRequest>();
  final second = Completer<IncomingRequest>();
  final never = Completer<IncomingRequest>();
  final falseStarted = Completer<void>();
  final releaseFalse = Completer<void>();
  int requests = 0;
  bool pending = false;
  int trueCalls = 0;
  @override
  Future<IncomingRequest> nextRequest() => switch (requests++) {
    0 => first.future,
    1 => second.future,
    _ => never.future,
  };
  @override
  Future<void> beginPairing({required String peerId}) async {
    trueCalls++;
    pending = true;
  }

  @override
  Future<void> endPairing({required String peerId}) async {
    if (!falseStarted.isCompleted) {
      falseStarted.complete();
      await releaseFalse.future;
    }
    pending = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets('successful incoming pairing closes the displayed device code', (
    tester,
  ) async {
    final node = PairRaceNode();
    final offer = PairOffer();
    node.releaseFalse.complete();
    await withHomeTestEnvironment(
      tester,
      devices: PeerState(),
      api: FakeRustApi(node),
      run: (_) async {
        await tester.pumpWidget(
          const VelaApp(
            profile: 'test',
            initialLanguage: 'en',
            initialAppearance: 'light',
            initialDiagnosticsEnabled: false,
          ),
        );
        final showCode = find.byKey(const ValueKey('show-device-code'));
        final code = find.byKey(const ValueKey('device-id'));
        await waitForHome(tester, () => showCode.evaluate().isNotEmpty);
        await tester.tap(showCode);
        await tester.pumpAndSettle();
        expect(code, findsOneWidget);

        node.first.complete(offer);
        final accept = find.byKey(const ValueKey('accept-pair'));
        await waitForHome(tester, () => accept.evaluate().isNotEmpty);
        await tester.pumpAndSettle();
        expect(
          find.ancestor(of: accept, matching: find.byType(AlertDialog)),
          findsOneWidget,
        );
        await tester.tap(accept);
        await waitForHome(tester, () => offer.accepted);
        await tester.pumpAndSettle();

        expect(code, findsNothing);
        expect(find.text('Phone'), findsOneWidget);
      },
    );
  });

  testWidgets(
    'late completion of old pairing cannot clear newer pending pairing',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('vela-pair-pending-');
      final node = PairRaceNode();
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
        await waitUntil(() => node.requests > 0);
        node.first.complete(PairOffer());
        await waitUntil(
          () => find.byKey(const ValueKey('accept-pair')).evaluate().isNotEmpty,
        );
        expect(node.pending, isTrue);
        await tester.tap(find.text('Decline'));
        await tester.pump();
        await waitUntil(() => node.falseStarted.isCompleted);
        node.second.complete(PairOffer());
        // The listener asks for its third request after dispatching the second.
        await waitUntil(() => node.requests == 3);
        node.releaseFalse.complete();
        await waitUntil(
          () =>
              node.trueCalls == 2 &&
              find.byKey(const ValueKey('accept-pair')).evaluate().isNotEmpty,
        );
        expect(
          node.pending,
          isTrue,
          reason: 'the older completion must not clear the current pairing',
        );
        await tester.tap(find.text('Decline'));
        await tester.pump();
      } finally {
        if (!node.releaseFalse.isCompleted) node.releaseFalse.complete();
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
}
