import 'dart:async';
import 'dart:io';

import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/main.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/api/folder.dart';
import 'package:vela/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart' as fakes;
import 'peer_test_utils.dart';

class LinkOffer implements IncomingRequest {
  @override
  IncomingRequestInfo info() => IncomingRequestInfo(
    name: 'link.txt',
    size: BigInt.from(19),
    sender: fakes.peerId,
    kind: 'text',
    files: const [],
  );
  @override
  Future<String> receiveFile({
    required String directory,
    required TransferJob job,
  }) async {
    final file = File('$directory/received-link.txt');
    await file.writeAsString('https://example.com');
    return file.path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LinkNode extends fakes.FakeNode {
  final offer = Completer<IncomingRequest>();
  final later = Completer<IncomingRequest>();
  final typed = Completer<IncomingRequest>();
  final clipboardText = Completer<IncomingRequest>();
  final image = Completer<IncomingRequest>();
  final batch = Completer<IncomingRequest>();
  final failedCopy = Completer<IncomingRequest>();
  final never = Completer<IncomingRequest>();
  int delivered = 0;
  @override
  Future<IncomingRequest> nextRequest() {
    delivered++;
    return delivered == 1
        ? offer.future
        : delivered == 2
        ? later.future
        : delivered == 3
        ? typed.future
        : delivered == 4
        ? clipboardText.future
        : delivered == 5
        ? image.future
        : delivered == 6
        ? batch.future
        : delivered == 7
        ? failedCopy.future
        : never.future;
  }
}

class TextOffer implements IncomingRequest {
  @override
  IncomingRequestInfo info() => IncomingRequestInfo(
    name: 'message.txt',
    size: BigInt.from(14),
    sender: fakes.peerId,
    kind: 'typed_text',
    files: const [],
  );
  @override
  Future<String> receiveFile({
    required String directory,
    required TransferJob job,
  }) async {
    final file = File('$directory/message.txt');
    await file.writeAsString('A typed message');
    return file.path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FolderOffer implements IncomingRequest {
  @override
  IncomingRequestInfo info() => IncomingRequestInfo(
    name: 'Photos.vela-folder.zip',
    size: BigInt.from(7),
    sender: fakes.peerId,
    kind: 'file',
    files: const [],
  );
  @override
  Future<String> receiveFile({
    required String directory,
    required TransferJob job,
  }) async {
    final file = File('$directory/Photos.vela-folder.zip');
    await file.writeAsString('archive');
    return file.path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ClipboardTextOffer implements IncomingRequest {
  @override
  IncomingRequestInfo info() => IncomingRequestInfo(
    name: 'clipboard.txt',
    size: BigInt.from(15),
    sender: fakes.peerId,
    kind: 'text',
    files: const [],
  );
  @override
  Future<String> receiveFile({
    required String directory,
    required TransferJob job,
  }) async {
    final file = File('$directory/clipboard.txt');
    await file.writeAsString('Clipboard words');
    return file.path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ClipboardImageOffer implements IncomingRequest {
  @override
  IncomingRequestInfo info() => IncomingRequestInfo(
    name: 'clipboard.png',
    size: BigInt.from(4),
    sender: fakes.peerId,
    kind: 'image',
    files: const [],
  );
  @override
  Future<String> receiveFile({
    required String directory,
    required TransferJob job,
  }) async {
    final file = File('$directory/clipboard.png');
    await file.writeAsBytes([1, 2, 3, 4]);
    return file.path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BatchOffer implements IncomingRequest {
  @override
  IncomingRequestInfo info() => IncomingRequestInfo(
    name: 'Files',
    size: BigInt.from(8),
    sender: fakes.peerId,
    kind: 'batch',
    files: const ['one.txt', 'two.pdf'],
  );
  @override
  Future<List<String>> receiveFiles({
    required String directory,
    required TransferJob job,
  }) async {
    final files = [File('$directory/one.txt'), File('$directory/two.pdf')];
    for (final file in files) {
      await file.writeAsString('data');
    }
    return files.map((file) => file.path).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RestoreJob implements FolderArchiveJob {
  String? archive;
  @override
  Future<void> cancel() async {}
  @override
  Future<String> restore({
    required String archive,
    required String outputDir,
  }) async {
    this.archive = archive;
    return (await Directory('$outputDir/Photos').create()).path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RestoreApi extends fakes.FakeRustApi {
  RestoreApi(super.node, this.job);
  final RestoreJob job;
  @override
  Future<FolderArchiveJob> crateApiFolderNewFolderArchiveJob() async => job;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets('received HTTP link offers an explicit browser action', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('vela-link-test-');
    final node = LinkNode();
    final restore = RestoreJob();
    databaseFactory = databaseFactoryFfi;
    await seedPeerState(tester, dir, PeerState(peers: {fakes.peerId: 'Phone'}));
    SharedPreferences.setMockInitialValues({'auto_accept_test': true});
    RustLib.initMock(api: RestoreApi(node, restore));
    const path = MethodChannel('plugins.flutter.io/path_provider');
    const secure = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    const background = MethodChannel('vela/background');
    const device = MethodChannel('vela/device');
    const share = MethodChannel('vela/share');
    const files = MethodChannel('vela/files');
    const storage = MethodChannel('vela/storage');
    const pasteboard = MethodChannel('pasteboard');
    String? opened;
    var clipboardWrites = 0;
    final copiedFiles = <List<String>>[];
    var copiedImages = 0;
    var failCopy = false;
    final menuStates = <Object>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(path, (_) async => dir.path);
    messenger.setMockMethodCallHandler(secure, (_) async => null);
    messenger.setMockMethodCallHandler(background, (call) async {
      if (call.method == 'setNodeStatus' || call.method == 'setTransferring') {
        menuStates.add(call.arguments as Object);
      }
      return call.method == 'getWindowVisible' || call.method == 'isVisible'
          ? true
          : null;
    });
    messenger.setMockMethodCallHandler(
      device,
      (_) async => {'name': 'MacBook', 'type': 'desktop'},
    );
    messenger.setMockMethodCallHandler(share, (_) async => null);
    messenger.setMockMethodCallHandler(
      storage,
      (call) async => call.method == 'location'
          ? {
              'isDefault': true,
              'displayPath': dir.path,
              'directoryPath': dir.path,
            }
          : null,
    );
    messenger.setMockMethodCallHandler(pasteboard, (call) async {
      if (call.method == 'writeFiles') {
        if (failCopy) throw PlatformException(code: 'clipboard');
        copiedFiles.add((call.arguments as List).cast<String>());
      }
      if (call.method == 'writeImage') copiedImages++;
      return null;
    });
    messenger.setMockMethodCallHandler(files, (call) async {
      if (call.method == 'openUrl') {
        opened = (call.arguments as Map)['url'] as String;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardWrites++;
      return null;
    });
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
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (find
              .byKey(const ValueKey('peer-${fakes.peerId}'))
              .evaluate()
              .isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        find.byKey(const ValueKey('peer-${fakes.peerId}')),
        findsOneWidget,
      );
      node.offer.complete(LinkOffer());
      while (find.text('View').evaluate().isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.text('View'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('View'));
      await tester.pump();
      expect(opened, 'https://example.com');
      if (Platform.isMacOS) {
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byKey(const ValueKey('transfer-history')));
        await tester.pump(const Duration(milliseconds: 400));
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        await tester.pump();
        await tester.tap(find.text('https://example.com'));
        while (find.text('Open link').evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pump(const Duration(milliseconds: 400));
        final open = find.text('Open link'), copy = find.text('Copy');
        expect(open, findsOneWidget);
        expect(copy, findsOneWidget);
        expect(
          tester.getCenter(open).dy,
          closeTo(tester.getCenter(copy).dy, 1),
          reason: 'Link actions stay on one line',
        );
        await tester.tap(find.byTooltip('Close').last);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byTooltip('Back'));
        await tester.pump(const Duration(milliseconds: 400));
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pump();
        expect(
          menuStates,
          containsAllInOrder(['starting', 'ready', true, false]),
        );
        node.later.complete(FolderOffer());
        final folderDeadline = DateTime.now().add(const Duration(seconds: 15));
        while (!((tester.state(find.byType(HomePage)) as dynamic).receivedPath
                        as String? ??
                    '')
                .endsWith('Photos.vela-folder.zip') &&
            DateTime.now().isBefore(folderDeadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('View'), findsOneWidget);
        expect(
          copiedFiles.single.single,
          endsWith('Photos.vela-folder.zip'),
          reason: 'Received files are copied to the clipboard',
        );
        await tester.tap(find.text('View'));
        while (restore.archive == null &&
            DateTime.now().isBefore(folderDeadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(restore.archive, isNotNull);
        expect(
          File(restore.archive!).existsSync(),
          isTrue,
          reason: 'The received ZIP remains after restoration',
        );
        while ((tester.state(
              find.byType(HomePage),
            ) as dynamic).contentOperationActive &&
            DateTime.now().isBefore(folderDeadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        final before = clipboardWrites;
        node.typed.complete(TextOffer());
        while ((tester.state(find.byType(HomePage)) as dynamic).lastMessage !=
                'Text received' &&
            DateTime.now().isBefore(folderDeadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.text('View'),
          findsOneWidget,
          reason:
              'offers=${node.delivered} busy=${(tester.state(find.byType(HomePage)) as dynamic).contentOperationActive} message=${(tester.state(find.byType(HomePage)) as dynamic).lastMessage}',
        );
        expect(
          clipboardWrites,
          before,
          reason: 'Typed text does not replace the clipboard',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('View'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('A typed message'), findsOneWidget);
        await tester.tap(find.byTooltip('Close').last);
        await tester.pump(const Duration(milliseconds: 300));
        node.clipboardText.complete(ClipboardTextOffer());
        while ((tester.state(find.byType(HomePage)) as dynamic).lastMessage !=
                'Clipboard received' &&
            DateTime.now().isBefore(folderDeadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.text('View'),
          findsOneWidget,
          reason: 'Clipboard text should have an explicit viewing action',
        );
        expect(
          clipboardWrites,
          before + 1,
          reason: 'Clipboard text is still copied automatically',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('View'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Clipboard words'), findsOneWidget);
        await tester.tap(find.byTooltip('Close').last);
        await tester.pump(const Duration(milliseconds: 300));
        node.image.complete(ClipboardImageOffer());
        while (!((tester.state(find.byType(HomePage)) as dynamic).receivedPath
                        as String? ??
                    '')
                .endsWith('clipboard.png') &&
            DateTime.now().isBefore(folderDeadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(
          find.text('View'),
          findsOneWidget,
          reason: 'A clipboard image should have the same action label',
        );
        expect(
          (tester.state(find.byType(HomePage)) as dynamic).receivedPath,
          endsWith('clipboard.png'),
        );
        expect(copiedImages, 1);
        node.batch.complete(BatchOffer());
        while (copiedFiles.length < 2 &&
            DateTime.now().isBefore(folderDeadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(
          copiedFiles.last.map((path) => File(path).uri.pathSegments.last),
          ['one.txt', 'two.pdf'],
        );
        failCopy = true;
        node.failedCopy.complete(BatchOffer());
        while ((tester.state(find.byType(HomePage)) as dynamic).lastMessage !=
                'Could not write to the clipboard.' &&
            DateTime.now().isBefore(folderDeadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(
          (tester.state(find.byType(HomePage)) as dynamic).lastMessage,
          'Could not write to the clipboard.',
        );
        expect(
          File(copiedFiles.last.first).existsSync(),
          isTrue,
          reason: 'A clipboard error must not discard received files',
        );
      }
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox.shrink());
      RustLib.dispose();
      for (final channel in [
        path,
        secure,
        background,
        device,
        share,
        files,
        pasteboard,
        storage,
      ]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });
}
