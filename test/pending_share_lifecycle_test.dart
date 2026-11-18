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

import 'peer_test_utils.dart';
import 'support/fakes.dart';

class SharedTextJob extends FakeTransferJob {
  String? text, kind, path;
  int sends = 0;

  @override
  Future<void> sendFile({
    required String peerId,
    required String path,
    required String kind,
  }) async {
    sends++;
    this.path = path;
    this.kind = kind;
    text = await File(path).readAsString();
  }
}

class SharedTextNode extends FakeNode {
  final job = SharedTextJob();

  @override
  TransferJob newTransferJob() => job;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  for (final send in [false, true]) {
    testWidgets(
      send
          ? 'sending a macOS URL share cleans its stage and temporary snapshot'
          : 'cancelling a macOS text share cleans its stage',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync('vela-share-');
        final node = SharedTextNode();
        final text = send ? 'https://example.com' : 'Shared text';
        const stage = 'text-stage';
        final cleaned = <String>[];
        final preparing = Completer<void>();
        final release = Completer<void>();
        var pending = true;
        databaseFactory = databaseFactoryFfi;
        await seedPeerState(
          tester,
          directory,
          PeerState(peers: {peerId: 'Phone'}),
        );
        SharedPreferences.setMockInitialValues({});
        RustLib.initMock(api: FakeRustApi(node));
        const path = MethodChannel('plugins.flutter.io/path_provider');
        const secure = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        const background = MethodChannel('vela/background');
        const device = MethodChannel('vela/device');
        const share = MethodChannel('vela/share');
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(path, (call) async {
          if (send && call.method == 'getTemporaryDirectory') {
            if (!preparing.isCompleted) preparing.complete();
            await release.future;
          }
          return directory.path;
        });
        messenger.setMockMethodCallHandler(secure, (_) async => null);
        messenger.setMockMethodCallHandler(
          background,
          (call) async =>
              call.method == 'getWindowVisible' || call.method == 'isVisible'
              ? true
              : null,
        );
        messenger.setMockMethodCallHandler(
          device,
          (_) async => {'name': 'MacBook', 'type': 'desktop'},
        );
        messenger.setMockMethodCallHandler(share, (call) async {
          if (call.method == 'take' && pending) {
            pending = false;
            return {'text': text, 'stage': stage};
          }
          if (call.method == 'cleanup') {
            cleaned.add((call.arguments as Map)['stage'] as String);
          }
          return null;
        });
        Future<void> waitUntil(bool Function() ready) async {
          for (var i = 0; i < 100 && !ready(); i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(ready(), isTrue);
        }

        try {
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
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
            () => find
                .byKey(const ValueKey('peer-$peerId'))
                .evaluate()
                .isNotEmpty,
          );
          final dynamic state = tester.state(find.byType(HomePage));
          expect(state.pendingShare.text, text);
          expect(state.pendingShare.stage, stage);
          expect(find.text('Ready to send: Text'), findsOneWidget);
          if (send) {
            final choose = find.byKey(const ValueKey('choose-share-device'));
            await tester.tap(choose);
            await waitUntil(() => preparing.isCompleted);
            await tester.pump();
            expect(tester.widget<FilledButton>(choose).onPressed, isNull);
            expect(
              tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, 'Cancel share'),
                  )
                  .onPressed,
              isNull,
            );
            await tester.tap(find.byKey(const ValueKey('peer-$peerId')));
            release.complete();
          } else {
            await tester.tap(find.text('Cancel share'));
          }
          await waitUntil(
            () => cleaned.isNotEmpty && !state.contentOperationActive,
          );
          expect(cleaned, [stage]);
          expect(state.pendingShare, isNull);
          if (send) {
            expect(node.job.sends, 1);
            expect(node.job.text, text);
            expect(node.job.kind, 'text');
            expect(File(node.job.path!).existsSync(), isFalse);
          } else {
            expect(node.job.text, isNull);
          }
        } finally {
          if (!release.isCompleted) release.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          RustLib.dispose();
          for (final channel in [path, secure, background, device, share]) {
            messenger.setMockMethodCallHandler(channel, null);
          }
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        }
      },
      skip: !Platform.isMacOS,
    );
  }
}
