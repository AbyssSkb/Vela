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

class SlotNode extends FakeNode {
  final first = Completer<IncomingRequest>();
  final second = Completer<IncomingRequest>();
  final never = Completer<IncomingRequest>();
  final jobs = <SlotJob>[];
  SlotJob? reserved;
  int delivered = 0;

  @override
  TransferJob newTransferJob() {
    if (reserved != null) throw StateError('transfer already active');
    final job = SlotJob(this);
    jobs.add(job);
    reserved = job;
    return job;
  }

  @override
  Future<IncomingRequest> nextRequest() => switch (delivered++) {
    0 => first.future,
    1 => second.future,
    _ => never.future,
  };
}

class SlotJob extends FakeTransferJob {
  SlotJob(this.node);
  final SlotNode node;
  int cancellations = 0;
  bool started = false;
  bool receiptOpen = false;

  void start() {
    if (cancellations > 0)
      throw StateError('[vela:cancelled] transfer cancelled');
    started = true;
  }

  void finish() {
    receiptOpen = true;
    if (identical(node.reserved, this)) node.reserved = null;
  }

  @override
  void cancel() {
    cancellations++;
    receiptOpen = false;
    if (!started && identical(node.reserved, this)) node.reserved = null;
  }
}

class TextOffer implements IncomingRequest {
  TextOffer(this.name);
  final String name;
  int receives = 0;

  @override
  IncomingRequestInfo info() => IncomingRequestInfo(
    name: '$name.txt',
    size: BigInt.from(7),
    sender: peerId,
    kind: 'typed_text',
    files: const [],
  );

  @override
  Future<String> receiveFile({
    required String directory,
    required TransferJob job,
  }) async {
    receives++;
    final transfer = job as SlotJob;
    transfer.start();
    final file = File('$directory/$name.txt');
    try {
      await file.writeAsString('message');
      return file.path;
    } finally {
      transfer.finish();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue, reason: 'The receive operation did not finish');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  for (final failPreparation in [true, false]) {
    testWidgets(
      failPreparation
          ? 'failed receive preparation releases its reserved job for the next offer'
          : 'successful receive leaves the receipt connection open',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'vela-transfer-job-',
        );
        final node = SlotNode();
        databaseFactory = databaseFactoryFfi;
        await seedPeerState(
          tester,
          directory,
          PeerState(peers: {peerId: 'Phone'}),
        );
        SharedPreferences.setMockInitialValues({'auto_accept_test': true});
        RustLib.initMock(api: FakeRustApi(node));
        const path = MethodChannel('plugins.flutter.io/path_provider');
        const secure = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        const background = MethodChannel('vela/background');
        const device = MethodChannel('vela/device');
        const share = MethodChannel('vela/share');
        var documentsRequests = 0;
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(path, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory' &&
              documentsRequests++ == 0 &&
              failPreparation) {
            throw PlatformException(code: 'documents_unavailable');
          }
          return directory.path;
        });
        messenger.setMockMethodCallHandler(secure, (_) async => null);
        messenger.setMockMethodCallHandler(background, (call) async {
          return call.method == 'getWindowVisible' || call.method == 'isVisible'
              ? true
              : null;
        });
        messenger.setMockMethodCallHandler(
          device,
          (_) async => {'name': 'MacBook', 'type': 'desktop'},
        );
        messenger.setMockMethodCallHandler(share, (_) async => null);
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
          await pumpUntil(
            tester,
            () => find
                .byKey(const ValueKey('peer-$peerId'))
                .evaluate()
                .isNotEmpty,
          );
          final first = TextOffer('first');
          node.first.complete(first);
          var successful = first;
          if (failPreparation) {
            await pumpUntil(
              tester,
              () => node.jobs.isNotEmpty && node.jobs.first.cancellations == 1,
            );
            expect(first.receives, 0);
            expect(node.reserved, isNull);
            final dynamic state = tester.state(find.byType(HomePage));
            expect(state.contentOperationActive, isFalse);
            expect(state.activeTransfer, isNull);
            successful = TextOffer('second');
            node.second.complete(successful);
          }
          await pumpUntil(tester, () {
            final dynamic state = tester.state(find.byType(HomePage));
            return successful.receives == 1 &&
                !state.contentOperationActive &&
                state.activeTransfer == null;
          });
          final completed = node.jobs.last;
          expect(completed.started, isTrue);
          expect(completed.cancellations, 0);
          expect(
            completed.receiptOpen,
            isTrue,
            reason: 'The sender may still be reading its successful receipt',
          );
          expect(node.reserved, isNull);
          expect(node.jobs.length, failPreparation ? 2 : 1);
          final dynamic state = tester.state(find.byType(HomePage));
          expect(state.lastMessage, 'Text received');
          expect(state.historyStore.records.value.length, 1);
          expect(
            File('${directory.path}/Vela/test/${successful.name}.txt')
                .readAsStringSync(),
            'message',
          );
        } finally {
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
    );
  }
}
