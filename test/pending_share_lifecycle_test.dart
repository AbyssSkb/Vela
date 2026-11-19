import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
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
import 'support/home_environment.dart';

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
          : 'inspecting a graph device keeps a share until it is cancelled',
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
        SharedPreferences.setMockInitialValues({
          'device_view_test': send ? 'list' : 'graph',
        });
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
          expect(find.text(text), findsOneWidget);
          final device = find.byKey(const ValueKey('peer-$peerId'));
          if (send) {
            expect(
              find.descendant(of: device, matching: find.text('Phone')),
              findsOneWidget,
            );
            final choose = find.byKey(const ValueKey('choose-share-device'));
            expect(
              find.widgetWithText(FilledButton, 'Send to Phone'),
              findsOneWidget,
            );
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
            await tester.tap(device);
            release.complete();
          } else {
            await tester.pump(const Duration(milliseconds: 450));
            expect(device.hitTestable(), findsOneWidget);
            await tester.tap(device);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 350));
            final sheet = find.byType(BottomSheet);
            expect(sheet, findsOneWidget);
            expect(node.job.sends, 0);
            expect(state.pendingShare.text, text);
            Navigator.of(tester.element(sheet)).pop();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 350));
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

  testWidgets('a dropped file waits for a device to be added', (tester) async {
    final node = SharedTextNode();
    await withHomeTestEnvironment(
      tester,
      devices: PeerState(),
      api: FakeRustApi(node),
      run: (directory) async {
        final file = File('${directory.path}/notes.txt')
          ..writeAsStringSync('Notes');
        await tester.pumpWidget(
          const VelaApp(
            profile: 'test',
            initialLanguage: 'en',
            initialAppearance: 'light',
            initialDiagnosticsEnabled: false,
          ),
        );
        final target = find.byType(DropTarget);
        await waitForHome(
          tester,
          () =>
              target.evaluate().isNotEmpty &&
              tester.widget<DropTarget>(target).enable,
        );
        tester.widget<DropTarget>(target).onDragDone!(
          DropDoneDetails(
            files: [DropItemFile(file.path)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
        final pending = find.byKey(const ValueKey('pending-share'));
        await waitForHome(tester, () => pending.evaluate().isNotEmpty);
        expect(find.text('Ready to send: notes.txt'), findsOneWidget);
        expect(find.text('Add a device to send this content.'), findsOneWidget);
        expect(node.job.sends, 0);
        await tester.tap(find.text('Cancel share'));
        await tester.pump();
        expect(pending, findsNothing);
        expect(file.existsSync(), isTrue);
      },
    );
  }, skip: !Platform.isMacOS && !Platform.isWindows && !Platform.isLinux);
}
