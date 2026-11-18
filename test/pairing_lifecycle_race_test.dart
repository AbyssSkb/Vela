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
import 'package:vela/src/rust/frb_generated.dart';

import 'support/fakes.dart' show FakeNode, FakeRustApi, peerId;
import 'peer_test_utils.dart';

class GatedUnpairNode extends FakeNode {
  final taken = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> revokeIfUnpaired({required String peerId}) async {
    final result = await super.revokeIfUnpaired(peerId: peerId);
    if (result) {
      taken.complete();
      await release.future;
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('re-pair while unpair result is pending restores current trust', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('vela-pair-race-');
    final node = GatedUnpairNode();
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
        () => find.byKey(const ValueKey('peer-$peerId')).evaluate().isNotEmpty,
      );
      node.publish(info: null, proofValidUntilNs: null, unpaired: true);
      await waitUntil(() => node.taken.isCompleted);
      expect(node.peerTrusted, isFalse);
      final cancelPairing = find.byKey(const ValueKey('cancel-pairing'));
      final peer = find.byKey(const ValueKey('peer-$peerId'));

      await tester.tap(find.byKey(const ValueKey('add-device')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byKey(const ValueKey('peer-id')), peerId);
      await tester.tap(find.byKey(const ValueKey('confirm-peer')));
      await tester.pump();
      await waitUntil(() => cancelPairing.evaluate().isNotEmpty);
      expect(peer, findsOneWidget);
      node.release.complete();
      await waitUntil(
        () => cancelPairing.evaluate().isEmpty && node.peerTrusted,
      );
      expect(
        find.descendant(
          of: peer,
          matching: find.byIcon(Icons.phone_android_rounded),
        ),
        findsOneWidget,
      );
    } finally {
      if (!node.release.isCompleted) node.release.complete();
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
