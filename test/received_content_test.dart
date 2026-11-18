import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/main.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/src/rust/api/folder.dart';
import 'package:vela/src/rust/api/node.dart';
import 'package:vela/src/rust/frb_generated.dart';
import 'package:vela/transfer_history.dart';

import 'peer_test_utils.dart';
import 'support/fakes.dart';
import 'support/home_environment.dart' show unmountTestHome, waitForHome;

class ContentOffer implements IncomingRequest {
  ContentOffer(this.kind, this.files);

  final String kind;
  final Map<String, List<int>> files;

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
  final menuStates = <Object>[];
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
}) {
  testWidgets(description, (tester) async {
    final dir = Directory.systemTemp.createTempSync('vela-received-content-');
    final effects = ReceiveEffects();
    databaseFactory = databaseFactoryFfi;
    await seedPeerState(tester, dir, PeerState(peers: {peerId: 'Phone'}));
    SharedPreferences.setMockInitialValues({'auto_accept_test': true});
    final node = ReceivingNode(offer);
    RustLib.initMock(api: RestoreApi(node, effects.restored));

    final channels = <MethodChannel, Future<Object?> Function(MethodCall)>{
      const MethodChannel('plugins.flutter.io/path_provider'): (_) async =>
          dir.path,
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'): (
        _,
      ) async => null,
      const MethodChannel('vela/background'): (call) async {
        if (call.method == 'setNodeStatus' ||
            call.method == 'setTransferring') {
          effects.menuStates.add(call.arguments as Object);
        }
        return call.method == 'getWindowVisible' || call.method == 'isVisible'
            ? true
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

  final link = ContentOffer('text', {
    'link.txt': utf8.encode('https://example.com'),
  });
  testReceiving('received HTTP link opens only when View is tapped', link, (
    tester,
    effects,
  ) async {
    expect(effects.openedUrl, isNull);
    await tester.tap(find.text('View'));
    await tester.pump();
    expect(effects.openedUrl, 'https://example.com');
  });

  testReceiving(
    'link history keeps Open link and Copy on one row on a narrow screen',
    link,
    (tester, _) async {
      await tester.tap(find.byKey(const ValueKey('transfer-history')));
      await waitFor(tester, find.text('https://example.com'));
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      await tester.pump();
      await tester.tap(find.text('https://example.com'));
      final open = find.text('Open link'), copy = find.text('Copy');
      await waitFor(tester, open);
      expect(copy, findsOneWidget);
      expect(tester.getCenter(open).dy, closeTo(tester.getCenter(copy).dy, 1));
    },
    macOnly: true,
  );

  testReceiving(
    'macOS menu reflects node readiness and an active receive',
    link,
    (_, effects) async {
      expect(
        effects.menuStates,
        containsAllInOrder(['starting', 'ready', true, false]),
      );
    },
    macOnly: true,
  );

  testReceiving(
    'restoring a received folder preserves the copied ZIP',
    ContentOffer('file', {'Photos.vela-folder.zip': utf8.encode('archive')}),
    (tester, effects) async {
      final archive = effects.fileCopyAttempts.single.single;
      expect(archive, endsWith('Photos.vela-folder.zip'));
      await tester.tap(find.text('View'));
      await waitFor(tester, find.text('Folder restored'));
      expect(effects.restored.archive, archive);
      expect(File(archive).readAsStringSync(), 'archive');
    },
    macOnly: true,
  );

  testReceiving(
    'typed text can be viewed without changing the clipboard',
    ContentOffer('typed_text', {'message.txt': utf8.encode('A typed message')}),
    (tester, effects) async {
      expect(effects.copiedTexts, isEmpty);
      await tester.tap(find.text('View'));
      await waitFor(tester, find.text('A typed message'));
    },
    macOnly: true,
  );

  testReceiving(
    'clipboard text is copied automatically and can be viewed',
    ContentOffer('text', {'clipboard.txt': utf8.encode('Clipboard words')}),
    (tester, effects) async {
      expect(effects.copiedTexts, ['Clipboard words']);
      await tester.tap(find.text('View'));
      await waitFor(tester, find.text('Clipboard words'));
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
    (_, effects) async {
      expect(effects.copiedImage, [1, 2, 3, 4]);
      final prefs = await SharedPreferences.getInstance();
      final history = TransferRecord.decode(prefs.getString('history_test'));
      final image = File(history.single.fileReference!);
      expect(image.uri.pathSegments.last, 'clipboard.png');
      expect(image.readAsBytesSync(), [1, 2, 3, 4]);
    },
    macOnly: true,
  );

  final batch = ContentOffer('batch', {
    'one.txt': utf8.encode('first'),
    'two.pdf': utf8.encode('second'),
  });
  testReceiving('a received batch copies both files to the clipboard', batch, (
    _,
    effects,
  ) async {
    expect(
      effects.fileCopyAttempts.single.map(
        (path) => File(path).uri.pathSegments.last,
      ),
      ['one.txt', 'two.pdf'],
    );
  }, macOnly: true);

  testReceiving(
    'clipboard failure leaves every file of the received batch intact',
    batch,
    (tester, effects) async {
      expect(
        find.text("Received, but couldn't copy to the clipboard."),
        findsOneWidget,
      );
      expect(
        effects.fileCopyAttempts.single.map(
          (path) => File(path).readAsStringSync(),
        ),
        ['first', 'second'],
      );
    },
    failClipboardFiles: true,
    macOnly: true,
  );
}
