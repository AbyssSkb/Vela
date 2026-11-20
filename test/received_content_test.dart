import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vela/desktop_platform.dart';
import 'package:vela/incoming_offer_prompt.dart';
import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/main.dart';
import 'package:vela/peer_confirmation.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/src/rust/api/folder.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/frb_generated.dart';
import 'package:vela/transfer_history.dart';

import 'peer_test_utils.dart';
import 'support/fakes.dart';
import 'support/home_environment.dart' show unmountTestHome, waitForHome;

class ContentOffer implements IncomingRequest {
  ContentOffer(this.kind, this.files, {this.failReceive = false});

  final String kind;
  final Map<String, List<int>> files;
  final bool failReceive;

  @override
  Future<void> waitForConnectionClose() => Completer<void>().future;

  @override
  IncomingRequestInfo info() => IncomingRequestInfo(
    name: kind == 'batch' ? 'Files' : files.keys.single,
    size: BigInt.from(
      files.values.fold<int>(0, (size, file) => size + file.length),
    ),
    sender: peerId,
    kind: kind,
    files: kind == 'batch' ? files.keys.toList() : const [],
  );

  @override
  Future<String> receiveFile({
    required String directory,
    required TransferJob job,
  }) async {
    if (failReceive) throw const FileSystemException('Could not save file');
    final file = File('$directory/${files.keys.single}');
    await file.writeAsBytes(files.values.single);
    return file.path;
  }

  @override
  Future<List<String>> receiveFiles({
    required String directory,
    required TransferJob job,
  }) async {
    final paths = <String>[];
    for (final entry in files.entries) {
      final file = File('$directory/${entry.key}');
      await file.writeAsBytes(entry.value);
      paths.add(file.path);
    }
    return paths;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ReceivingNode extends FakeNode {
  ReceivingNode(this.offer);
  IncomingRequest? offer;

  @override
  Future<IncomingRequest> nextRequest() {
    final next = offer;
    offer = null;
    return next == null ? super.nextRequest() : Future.value(next);
  }
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

class RestoreApi extends FakeRustApi {
  RestoreApi(super.node, this.job);
  final RestoreJob job;

  @override
  Future<FolderArchiveJob> crateApiFolderNewFolderArchiveJob() async => job;
}

class ReceiveEffects {
  final restored = RestoreJob();
  final menuStates = <(String, Object?)>[];
  final copiedTexts = <String>[];
  final fileCopyAttempts = <List<String>>[];
  List<int>? copiedImage;
  String? openedUrl;
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  await waitForHome(tester, () => finder.evaluate().isNotEmpty);
  expect(finder, findsOneWidget);
  await tester.pump(const Duration(milliseconds: 400));
}

void testReceiving(
  String description,
  ContentOffer offer,
  Future<void> Function(WidgetTester, ReceiveEffects) verify, {
  bool macOnly = false,
  bool failClipboardFiles = false,
  bool failClipboardText = false,
  bool inBackground = false,
  bool? openAfterReceive,
}) {
  testWidgets(description, (tester) async {
    final dir = Directory.systemTemp.createTempSync('vela-received-content-');
    final effects = ReceiveEffects();
    databaseFactory = databaseFactoryFfi;
    await seedPeerState(tester, dir, PeerState(peers: {peerId: 'Phone'}));
    SharedPreferences.setMockInitialValues({
      'auto_accept_test': true,
      if (openAfterReceive != null)
        DesktopPlatform.openAfterReceiveKey('test'): openAfterReceive,
    });
    final node = ReceivingNode(offer);
    RustLib.initMock(api: RestoreApi(node, effects.restored));

    final channels = <MethodChannel, Future<Object?> Function(MethodCall)>{
      const MethodChannel('plugins.flutter.io/path_provider'): (_) async =>
          dir.path,
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'): (
        _,
      ) async => null,
      const MethodChannel('vela/background'): (call) async {
        effects.menuStates.add((call.method, call.arguments));
        return call.method == 'getWindowVisible' || call.method == 'isVisible'
            ? !inBackground
            : null;
      },
      const MethodChannel('vela/device'): (_) async => {
        'name': 'MacBook',
        'type': 'desktop',
      },
      const MethodChannel('vela/share'): (_) async => null,
      const MethodChannel('vela/storage'): (call) async =>
          call.method == 'location'
          ? {
              'isDefault': true,
              'displayPath': dir.path,
              'directoryPath': dir.path,
            }
          : null,
      const MethodChannel('pasteboard'): (call) async {
        if (call.method == 'writeFiles') {
          effects.fileCopyAttempts.add((call.arguments as List).cast<String>());
          if (failClipboardFiles) throw PlatformException(code: 'clipboard');
        }
        if (call.method == 'writeImage') {
          effects.copiedImage = call.arguments as Uint8List;
        }
        return null;
      },
      const MethodChannel('vela/files'): (call) async {
        if (call.method == 'openUrl') {
          effects.openedUrl = (call.arguments as Map)['url'] as String;
        }
        return null;
      },
      SystemChannels.platform: (call) async {
        if (call.method == 'Clipboard.setData') {
          if (failClipboardText) throw PlatformException(code: 'clipboard');
          effects.copiedTexts.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    };
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final entry in channels.entries) {
      messenger.setMockMethodCallHandler(entry.key, entry.value);
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
      await waitFor(tester, find.byType(SnackBar));
      await verify(tester, effects);
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await unmountTestHome(tester, node);
      RustLib.dispose();
      for (final channel in channels.keys) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  }, skip: macOnly && !Platform.isMacOS);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('batch approval shows the complete scrollable file list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final names = [for (var i = 1; i <= 20; i++) 'File $i.pdf'];
    PeerDecision? decision;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                decision =
                    await IncomingOfferPrompt(
                      const MethodChannel('vela/background'),
                    ).confirm(
                      context,
                      offer: ContentOffer('batch', {
                        for (final name in names) name: [0],
                      }),
                      senderName: () => 'Phone',
                      contentName: '20 files',
                      batchFiles: names,
                      size: '20 B',
                      inBackground: false,
                      autoAccept: false,
                    );
              },
              child: const Text('Offer'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Offer'));
    await tester.pumpAndSettle();
    final extraNames = find.text(names.skip(3).join('\n'));
    expect(extraNames, findsNothing);
    await tester.tap(find.text('Show 17 more files'));
    await tester.pumpAndSettle();
    expect(extraNames, findsOneWidget);
    expect(find.text('Show fewer files'), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
    final accept = find.byKey(const ValueKey('accept-offer'));
    expect(accept.hitTestable(), findsOneWidget);
    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(decision, PeerDecision.accepted);
  });

  final link = ContentOffer('text', {
    'link.txt': utf8.encode('https://example.com'),
  });
  testReceiving(
    'received HTTP link opens only when Open link is tapped',
    link,
    (tester, effects) async {
      expect(effects.openedUrl, isNull);
      await tester.tap(find.text('Open link'));
      await tester.pump();
      expect(effects.openedUrl, 'https://example.com');
    },
  );

  testReceiving(
    'link history keeps Open link and Copy reachable on a narrow screen',
    link,
    (tester, _) async {
      await tester.tap(find.byKey(const ValueKey('transfer-history')));
      await waitFor(tester, find.text('https://example.com'));
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      await tester.tap(find.text('https://example.com'));
      final open = find.text('Open link'), copy = find.text('Copy');
      await waitFor(tester, open);
      expect(copy.hitTestable(), findsOneWidget);
      expect(open.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final showWindow in [null, true]) {
    testReceiving(
      'background receive reports completion with show window set to $showWindow',
      link,
      (_, effects) async {
        expect(
          effects.menuStates,
          containsAllInOrder([
            ('setNodeStatus', 'starting'),
            ('setNodeStatus', 'ready'),
            ('setTransferring', true),
            ('transferCompleted', showWindow ?? false),
          ]),
        );
        expect(
          effects.menuStates.where((state) => state.$1 == 'offer'),
          isEmpty,
        );
      },
      inBackground: true,
      openAfterReceive: showWindow,
    );
  }

  testReceiving(
    'failed background receive clears progress without showing a window',
    ContentOffer('file', {
      'photo.jpg': [1],
    }, failReceive: true),
    (tester, effects) async {
      expect(
        effects.menuStates,
        containsAllInOrder([
          ('setTransferring', true),
          ('setTransferring', false),
        ]),
      );
      expect(
        effects.menuStates.where((state) => state.$1 == 'transferCompleted'),
        isEmpty,
      );
      await tester.pump(const Duration(seconds: 1));
    },
    inBackground: true,
    openAfterReceive: true,
  );

  testReceiving(
    'restoring a received folder preserves its original ZIP and clipboard',
    ContentOffer('file', {'Photos.vela-folder.zip': utf8.encode('archive')}),
    (tester, effects) async {
      expect(effects.fileCopyAttempts, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      final archive = TransferRecord.decode(prefs.getString('history_test'))
          .single
          .fileReference!;
      expect(archive, endsWith('Photos.vela-folder.zip'));
      await tester.tap(find.text('Restore folder'));
      await waitFor(tester, find.text('Folder restored'));
      expect(effects.restored.archive, archive);
      expect(File(archive).readAsStringSync(), 'archive');
    },
    macOnly: true,
  );

  testReceiving(
    'explicit clipboard files are still copied when accepted',
    ContentOffer('clipboard_file', {'notes.txt': utf8.encode('Notes')}),
    (_, effects) async {
      expect(effects.fileCopyAttempts.single.single, endsWith('notes.txt'));
    },
    macOnly: true,
  );

  testReceiving(
    'typed text can be viewed without changing the clipboard',
    ContentOffer('typed_text', {'message.txt': utf8.encode('A typed message')}),
    (tester, effects) async {
      expect(effects.copiedTexts, isEmpty);
      await tester.tap(find.text('View text'));
      await waitFor(tester, find.text('A typed message'));
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('Text')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('From Phone')),
        findsOneWidget,
      );
    },
    macOnly: true,
  );

  testReceiving(
    'clipboard text is copied automatically and can be viewed',
    ContentOffer('text', {'clipboard.txt': utf8.encode('Clipboard words')}),
    (tester, effects) async {
      expect(effects.copiedTexts, ['Clipboard words']);
      await tester.tap(find.text('View text'));
      await waitFor(tester, find.text('Clipboard words'));
      expect(find.text('Clipboard text'), findsOneWidget);
    },
    macOnly: true,
  );

  testReceiving(
    'received clipboard text stays accessible when copying fails',
    ContentOffer('text', {'clipboard.txt': utf8.encode('Still received')}),
    (tester, effects) async {
      expect(effects.copiedTexts, isEmpty);
      expect(
        find.text("Received, but couldn't copy to the clipboard."),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('transfer-history')));
      final preview = find.text('Still received');
      await waitFor(tester, preview);
      await tester.tap(preview);
      await waitFor(tester, find.text('Copy'));
    },
    failClipboardText: true,
    macOnly: true,
  );

  testReceiving(
    'clipboard images are copied and offered for viewing',
    ContentOffer('image', {
      'clipboard.png': [1, 2, 3, 4],
    }),
    (tester, effects) async {
      expect(effects.copiedImage, [1, 2, 3, 4]);
      expect(find.text('Open file'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final history = TransferRecord.decode(prefs.getString('history_test'));
      final image = File(history.single.fileReference!);
      expect(image.uri.pathSegments.last, 'clipboard.png');
      expect(image.readAsBytesSync(), [1, 2, 3, 4]);
    },
    macOnly: true,
  );

  testReceiving(
    'dismisses the receive receipt when composing the next send',
    ContentOffer('file', {
      'a-very-long-screenshot-file-name-' * 4 + '.jpg': [1],
    }),
    (tester, effects) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      tester.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      await tester.pump();
      final receiveNotice = find.byKey(const ValueKey('message-notice'));
      final sendNotice = find.byKey(const ValueKey('send-receipt'));
      expect(tester.getBottomLeft(receiveNotice), const Offset(0, 640));
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('notice-action'))).dy,
        lessThanOrEqualTo(616),
      );

      final completed = effects.menuStates
          .where((state) => state.$1 == 'transferCompleted')
          .length;
      await tester.tap(find.byKey(const ValueKey('send-text')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(receiveNotice, findsNothing);
      await tester.enterText(find.byType(TextField), 'Reply from Vela');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('peer-$peerId')));
      await waitForHome(
        tester,
        () =>
            effects.menuStates
                .where((state) => state.$1 == 'transferCompleted')
                .length >
            completed,
      );
      await tester.pump();
      expect(receiveNotice, findsNothing);
      expect(sendNotice, findsOneWidget);
      expect(tester.getBottomLeft(sendNotice).dy, 616);
      expect(
        tester.getBottomRight(find.byKey(const ValueKey('activity-notice'))),
        const Offset(320, 640),
      );
      expect(tester.takeException(), isNull);
    },
    macOnly: true,
  );

  final batch = ContentOffer('batch', {
    'one.txt': utf8.encode('first'),
    'two.pdf': utf8.encode('second'),
  });
  testReceiving('received batch offers both files in Received', batch, (
    tester,
    effects,
  ) async {
    expect(effects.fileCopyAttempts, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    final records = TransferRecord.decode(prefs.getString('history_test'));
    final saved = File(records.first.fileReference!).parent.path;
    expect(find.text('Saved to $saved'), findsOneWidget);
    await tester.tap(find.text('View this batch'));
    await waitFor(tester, find.text('one.txt'));
    expect(find.text('two.pdf'), findsOneWidget);
    expect(find.text('Received batch'), findsOneWidget);
    final batchIds = records.map((record) => record.batchId).toSet();
    expect(batchIds.single, isNotNull);
    await tester.tap(find.byTooltip('Copy files'));
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(TransferHistoryPage),
        matching: find.text('Copied'),
      ),
    );
    expect(
      effects.fileCopyAttempts.single.map(
        (path) => File(path).uri.pathSegments.last,
      ),
      unorderedEquals(['one.txt', 'two.pdf']),
    );
  }, macOnly: true);

  testReceiving(
    'explicit copy failure leaves every file in the received batch intact',
    batch,
    (tester, effects) async {
      expect(effects.fileCopyAttempts, isEmpty);
      await tester.tap(find.text('View this batch'));
      final copy = find.byTooltip('Copy files');
      await waitFor(tester, copy);
      await tester.tap(copy);
      await waitFor(
        tester,
        find.descendant(
          of: find.byType(TransferHistoryPage),
          matching: find.text('Couldn’t copy to the clipboard. Try again.'),
        ),
      );
      expect(
        effects.fileCopyAttempts.single.map(
          (path) => File(path).readAsStringSync(),
        ),
        unorderedEquals(['first', 'second']),
      );
    },
    failClipboardFiles: true,
    macOnly: true,
  );
}
