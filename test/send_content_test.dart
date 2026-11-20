import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela/main.dart';
import 'package:vela/notice.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/src/rust/api/folder.dart';
import 'package:vela/src/rust/api/node.dart';

import 'support/fakes.dart' as fakes;
import 'support/home_environment.dart';

class RecordingNode extends fakes.FakeNode {
  String? sentText;
  String? sentKind;
  String? sentName;
  String? sentPeer;
  String? attemptedPath;
  Completer<void>? sendGate;
  String? nextFailure;
  TransferProgress? currentProgress;
  @override
  TransferJob newTransferJob() => RecordingTransferJob(this);
}

class RecordingTransferJob extends fakes.FakeTransferJob {
  RecordingTransferJob(this.node);
  final RecordingNode node;
  @override
  TransferProgress progress() => node.currentProgress ?? super.progress();

  @override
  Future<void> sendFile({
    required String peerId,
    required String path,
    required String kind,
  }) async {
    node.attemptedPath = path;
    await node.sendGate?.future;
    if (node.nextFailure case final failure?) {
      node.nextFailure = null;
      throw Exception(failure);
    }
    node.sentText = await File(path).readAsString();
    node.sentPeer = peerId;
    node.sentKind = kind;
    node.sentName = File(path).uri.pathSegments.last;
  }
}

class FolderPicker extends FilePickerPlatform {
  FolderPicker(this.path);
  final String path;
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => path;
}

class FilesPicker extends FilePickerPlatform {
  FilesPicker(this.paths);
  final List<String> paths;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => [for (final path in paths) PickedFile(path)];
}

final class PickedFile extends PlatformFile {
  PickedFile(String path) : uri = File(path).uri;

  @override
  final Uri uri;
  @override
  String get name => uri.pathSegments.last;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FolderJob implements FolderArchiveJob {
  String? source;
  @override
  Future<void> cancel() async {}
  @override
  Future<String> pack({
    required String source,
    required String outputDir,
  }) async {
    this.source = source;
    final file = File('$outputDir/test.vela-folder.zip');
    await file.writeAsString('archive');
    return file.path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingApi extends fakes.FakeRustApi {
  RecordingApi(super.node, this.folderJob);
  final FolderJob folderJob;
  @override
  Future<FolderArchiveJob> crateApiFolderNewFolderArchiveJob() async =>
      folderJob;
}

Future<void> openHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  await tester.pumpWidget(
    const VelaApp(
      profile: 'test',
      initialLanguage: 'en',
      initialAppearance: 'light',
      initialDiagnosticsEnabled: false,
    ),
  );
  await waitForHome(
    tester,
    () => find
        .byKey(const ValueKey('peer-${fakes.peerId}'))
        .evaluate()
        .isNotEmpty,
  );
}

Future<void> choosePhone(WidgetTester tester) async {
  await waitForHome(
    tester,
    () =>
        find.byKey(const ValueKey('home-send-recipient')).evaluate().isNotEmpty,
  );
  await finishTransition(tester);
  await tester.tap(find.byKey(const ValueKey('peer-${fakes.peerId}')));
}

Future<void> finishTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> waitForSend(WidgetTester tester) async {
  await waitForHome(
    tester,
    () => find
        .descendant(
          of: find.byKey(const ValueKey('send-receipt')),
          matching: find.text('Sent to Phone'),
        )
        .evaluate()
        .isNotEmpty,
  );
}

void main() {
  final devices = PeerState(
    peers: {fakes.peerId: 'Phone', 'c' * 64: 'Laptop'},
    types: {fakes.peerId: 'mobile', 'c' * 64: 'desktop'},
  );
  final onlyPhone = PeerState(
    peers: {fakes.peerId: 'Phone'},
    types: {fakes.peerId: 'mobile'},
  );

  testWidgets('one recipient is named before sending and on its receipt', (
    tester,
  ) async {
    final gate = Completer<void>();
    final node = RecordingNode()..sendGate = gate;
    await withHomeTestEnvironment(
      tester,
      devices: onlyPhone,
      api: fakes.FakeRustApi(node),
      run: (_) async {
        try {
          tester.view.viewPadding = const FakeViewPadding(bottom: 24);
          tester.view.padding = const FakeViewPadding(bottom: 24);
          addTearDown(tester.view.resetViewPadding);
          addTearDown(tester.view.resetPadding);
          await openHome(tester);
          final deviceViewport = find.byKey(const ValueKey('home-devices'));
          final peer = find.byKey(const ValueKey('peer-${fakes.peerId}'));
          final textAction = find.byKey(const ValueKey('send-text'));
          final viewportBounds = tester.getRect(deviceViewport);
          final peerPosition = tester.getTopLeft(peer);
          final textActionPosition = tester.getTopLeft(textAction);
          await tester.tap(textAction);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          await tester.enterText(find.byType(TextField), 'Hello from Vela');
          await tester.pump();
          final send = find.widgetWithText(FilledButton, 'Done');
          expect(send.hitTestable(), findsOneWidget);
          expect(node.attemptedPath, isNull);
          await tester.tap(send);
          await choosePhone(tester);
          await waitForHome(tester, () => node.attemptedPath != null);
          await tester.pump();
          expect(find.text('Connecting to Phone'), findsOneWidget);
          node.currentProgress = TransferProgress(
            done: BigInt.zero,
            total: BigInt.from(80),
            path: 'direct',
            udpBytesSent: BigInt.zero,
          );
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pump();
          expect(find.text('Waiting for Phone to respond'), findsOneWidget);
          node.currentProgress = TransferProgress(
            done: BigInt.from(40),
            total: BigInt.from(80),
            path: 'direct',
            udpBytesSent: BigInt.from(42),
          );
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pump();
          expect(find.text('Sending to Phone'), findsOneWidget);
          expect(tester.getRect(deviceViewport), viewportBounds);
          expect(tester.getTopLeft(peer), peerPosition);
          expect(tester.getTopLeft(textAction), textActionPosition);
          expect(
            find.descendant(
              of: find.byType(ActivityNotice),
              matching: find.text('Text'),
            ),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('home-more')));
          await finishTransition(tester);
          await tester.tap(find.byKey(const ValueKey('transfer-history')));
          await finishTransition(tester);
          expect(find.text('Sending to Phone').hitTestable(), findsOneWidget);
          expect(
            find.byKey(const ValueKey('cancel-transfer')).hitTestable(),
            findsOneWidget,
          );
          await tester.binding.handlePopRoute();
          await finishTransition(tester);
          gate.complete();
          await waitForSend(tester);
          await tester.pump(const Duration(seconds: 6));
          final receipt = find.byKey(const ValueKey('send-receipt'));
          expect(tester.getRect(deviceViewport), viewportBounds);
          expect(tester.getTopLeft(peer), peerPosition);
          expect(tester.getTopLeft(textAction), textActionPosition);
          expect(peer.hitTestable(), findsOneWidget);
          expect(
            find.descendant(
              of: receipt,
              matching: find.text('Hello from Vela'),
            ),
            findsOneWidget,
          );
          expect(find.text('Sent to Phone'), findsOneWidget);
          expect(node.sentText, 'Hello from Vela');
          await tester.tap(
            find.descendant(of: receipt, matching: find.byTooltip('Close')),
          );
          await tester.pump();
          expect(receipt, findsNothing);
          expect(tester.getRect(deviceViewport), viewportBounds);
          expect(tester.getTopLeft(peer), peerPosition);
          expect(tester.getTopLeft(textAction), textActionPosition);
        } finally {
          if (!gate.isCompleted) gate.complete();
        }
      },
    );
  });

  testWidgets(
    'a text draft sends only when its recipient is tapped on the home page',
    (tester) async {
      final node = RecordingNode();
      await withHomeTestEnvironment(
        tester,
        devices: devices,
        api: fakes.FakeRustApi(node),
        run: (_) async {
          await openHome(tester);
          await tester.tap(find.byKey(const ValueKey('send-text')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.enterText(find.byType(TextField), 'Hello from Vela');
          await tester.pump();
          expect(find.byType(DropdownButtonFormField<String>), findsNothing);
          await tester.tap(find.widgetWithText(FilledButton, 'Done'));
          await finishTransition(tester);
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.text('Choose a device'), findsOneWidget);
          expect(find.text('Hello from Vela'), findsNothing);
          expect(node.attemptedPath, isNull);
          await choosePhone(tester);
          await waitForSend(tester);
          expect(node.sentText, 'Hello from Vela');
          expect(node.sentKind, 'typed_text');
          expect(node.sentName, endsWith('.txt'));
        },
      );
    },
  );

  testWidgets('retry keeps the prepared send after another notice', (
    tester,
  ) async {
    final node = RecordingNode()..nextFailure = 'Connection interrupted';
    await withHomeTestEnvironment(
      tester,
      devices: devices,
      api: fakes.FakeRustApi(node),
      run: (_) async {
        await openHome(tester);
        await tester.tap(find.byKey(const ValueKey('send-text')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byType(TextField), 'Original retry text');
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Done'));
        await choosePhone(tester);
        final retry = find.text('Retry');
        await waitForHome(tester, () => retry.evaluate().isNotEmpty);
        final prepared = File(node.attemptedPath!);
        expect(prepared.existsSync(), isTrue);

        showNotice(tester.element(find.byType(HomePage)), 'Another notice');
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 1));
        expect(prepared.existsSync(), isTrue);
        expect(retry.hitTestable(), findsOneWidget);
        await tester.tap(retry);
        await waitForSend(tester);
        expect(node.sentText, 'Original retry text');
        expect(node.attemptedPath, prepared.path);
        expect(prepared.existsSync(), isFalse);
      },
    );
  });

  testWidgets('explicit decline closes the send and preserves the result', (
    tester,
  ) async {
    final node = RecordingNode()
      ..nextFailure = '[vela:declined] Transfer declined';
    await withHomeTestEnvironment(
      tester,
      devices: onlyPhone,
      api: fakes.FakeRustApi(node),
      run: (_) async {
        await openHome(tester);
        await tester.tap(find.byKey(const ValueKey('send-text')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byType(TextField), 'Meeting notes');
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Done'));
        await choosePhone(tester);
        final rejected = find.text('Phone declined the transfer.');
        await waitForHome(tester, () => rejected.evaluate().isNotEmpty);
        expect(find.byKey(const ValueKey('retry-send')), findsNothing);
        expect(
          find.byKey(const ValueKey('send-text')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('send-receipt')),
            matching: find.text('Meeting notes'),
          ),
          findsOneWidget,
        );
        await waitForHome(
          tester,
          () => !File(node.attemptedPath!).existsSync(),
        );
      },
    );
  });

  testWidgets('file selection names the content and keeps originals on Back', (
    tester,
  ) async {
    final node = RecordingNode();
    await withHomeTestEnvironment(
      tester,
      devices: onlyPhone,
      api: fakes.FakeRustApi(node),
      run: (directory) async {
        final originalPicker = FilePickerPlatform.instance;
        final file = File('${directory.path}/Report.txt')
          ..writeAsStringSync('Report');
        FilePickerPlatform.instance = FilesPicker([file.path]);
        try {
          await openHome(tester);
          await tester.tap(find.byKey(const ValueKey('send-file')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Report.txt'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('peer-${fakes.peerId}')).hitTestable(),
            findsOneWidget,
          );
          expect(node.attemptedPath, isNull);
          await tester.binding.handlePopRoute();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(node.attemptedPath, isNull);
          expect(file.readAsStringSync(), 'Report');
        } finally {
          FilePickerPlatform.instance = originalPicker;
        }
      },
    );
  });

  testWidgets('large text can scroll to and distinguish recipients', (
    tester,
  ) async {
    final node = RecordingNode();
    await withHomeTestEnvironment(
      tester,
      devices: PeerState(
        peers: {fakes.peerId: 'Pixel 9', 'c' * 64: 'Pixel 9'},
        types: {fakes.peerId: 'mobile', 'c' * 64: 'mobile'},
      ),
      api: fakes.FakeRustApi(node),
      run: (directory) async {
        final first = File(
          '${directory.path}/Trip itinerary and accommodation confirmations.pdf',
        )..writeAsStringSync('Report');
        final picker = FilePickerPlatform.instance;
        FilePickerPlatform.instance = FilesPicker([first.path]);
        addTearDown(() => FilePickerPlatform.instance = picker);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openHome(tester);
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('send-file')));
        final firstDevice = find.byKey(const ValueKey('peer-${fakes.peerId}'));
        await waitForHome(tester, () => firstDevice.evaluate().isNotEmpty);
        await finishTransition(tester);
        await tester.ensureVisible(firstDevice);
        await tester.pump();
        expect(firstDevice.hitTestable(), findsOneWidget);
        expect(find.textContaining('aaaaaaaa…aaaaaaaa'), findsOneWidget);
        expect(node.attemptedPath, isNull);
        expect(
          find.text('Trip itinerary and accommodation confirmations.pdf'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.textContaining('cccccccc…cccccccc'));
        expect(
          find.textContaining('cccccccc…cccccccc').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('clipboard preview shows the captured text before sending', (
    tester,
  ) async {
    final node = RecordingNode();
    final messenger = tester.binding.defaultBinaryMessenger;
    const pasteboard = MethodChannel('pasteboard');
    messenger.setMockMethodCallHandler(pasteboard, (_) async => null);
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? {'text': 'Original clipboard'}
          : null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(pasteboard, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await withHomeTestEnvironment(
      tester,
      devices: onlyPhone,
      api: fakes.FakeRustApi(node),
      run: (_) async {
        await openHome(tester);
        await tester.tap(find.byKey(const ValueKey('send-clipboard')));
        final preview = find.text('Original clipboard');
        await waitForHome(tester, () => preview.evaluate().isNotEmpty);
        expect(preview, findsOneWidget);
        expect(node.attemptedPath, isNull);
        await choosePhone(tester);
        await waitForSend(tester);
        expect(node.sentText, 'Original clipboard');
      },
    );
  });

  testWidgets('a failed file can be resent after its device is removed', (
    tester,
  ) async {
    final node = RecordingNode()..nextFailure = 'Connection interrupted';
    await withHomeTestEnvironment(
      tester,
      devices: devices,
      api: fakes.FakeRustApi(node),
      run: (directory) async {
        final file = File('${directory.path}/Report.txt')
          ..writeAsStringSync('Report');
        final picker = FilePickerPlatform.instance;
        FilePickerPlatform.instance = FilesPicker([file.path]);
        addTearDown(() => FilePickerPlatform.instance = picker);
        await openHome(tester);
        await tester.tap(find.byKey(const ValueKey('send-file')));
        await choosePhone(tester);
        final retry = find.byKey(const ValueKey('retry-send'));
        await waitForHome(tester, () => retry.evaluate().isNotEmpty);
        expect(find.text('Report.txt'), findsOneWidget);
        final peer = find.byKey(const ValueKey('peer-${fakes.peerId}'));
        await tester.tap(peer);
        await finishTransition(tester);
        await tester.tap(find.text('Remove device'));
        await finishTransition(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
        await waitForHome(tester, () => peer.evaluate().isEmpty);
        final reselect = find.byKey(const ValueKey('choose-retry-device'));
        expect(retry, findsNothing);
        expect(find.text('Send to Laptop instead'), findsOneWidget);
        expect(node.sentPeer, isNull);
        await tester.tap(reselect);
        await waitForHome(
          tester,
          () => find.text('Sent to Laptop').evaluate().isNotEmpty,
        );
        expect(node.sentPeer, 'c' * 64);
        expect(node.attemptedPath, file.path);
        expect(file.existsSync(), isTrue);
      },
    );
  });

  testWidgets(
    'a system share waits for the open chooser and loads names later',
    (tester) async {
      final node = RecordingNode();
      await withHomeTestEnvironment(
        tester,
        devices: devices,
        api: fakes.FakeRustApi(node),
        run: (directory) async {
          final file = File('${directory.path}/Report.txt')
            ..writeAsStringSync('Report');
          final picker = FilePickerPlatform.instance;
          FilePickerPlatform.instance = FilesPicker([file.path]);
          addTearDown(() => FilePickerPlatform.instance = picker);
          await openHome(tester);
          await tester.tap(find.byKey(const ValueKey('send-file')));
          await finishTransition(tester);
          final messenger = tester.binding.defaultBinaryMessenger;
          final names = Completer<List<String>>();
          const filesChannel = MethodChannel('vela/files');
          const shareChannel = MethodChannel('vela/share');
          messenger.setMockMethodCallHandler(filesChannel, (_) => names.future);
          addTearDown(
            () => messenger.setMockMethodCallHandler(filesChannel, null),
          );
          messenger.setMockMethodCallHandler(shareChannel, (call) async {
            if (call.method != 'take') return null;
            return {
              'uris': ['content://test/second'],
            };
          });
          unawaited(
            messenger.handlePlatformMessage(
              shareChannel.name,
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('available'),
              ),
              (_) {},
            ),
          );
          await finishTransition(tester);
          expect(find.text('Report.txt'), findsOneWidget);
          expect(node.attemptedPath, isNull);
          await tester.binding.handlePopRoute();
          await finishTransition(tester);
          await finishTransition(tester);
          expect(
            find.text('Ready to send: 1 file').hitTestable(),
            findsOneWidget,
          );
          expect(find.text('Send to Laptop').hitTestable(), findsOneWidget);
          names.complete(['Screenshot.jpg']);
          await tester.pump();
          expect(
            find.text('Ready to send: Screenshot.jpg').hitTestable(),
            findsOneWidget,
          );
          expect(node.attemptedPath, isNull);
        },
      );
    },
    skip: !(Platform.isMacOS || Platform.isAndroid),
  );

  testWidgets(
    'a device drop keeps its target and a later drop keeps its file',
    (tester) async {
      final node = RecordingNode();
      await withHomeTestEnvironment(
        tester,
        devices: devices,
        api: fakes.FakeRustApi(node),
        run: (directory) async {
          await openHome(tester);
          await finishTransition(tester);
          final target = tester.widget<DropTarget>(find.byType(DropTarget));
          final phone = find.byKey(const ValueKey('peer-${fakes.peerId}'));
          final position = tester.getCenter(phone);
          final first = File('${directory.path}/First.txt')
            ..writeAsStringSync('First');
          final second = File('${directory.path}/Second.txt')
            ..writeAsStringSync('Second');
          for (final (file, at) in [
            (first, position),
            (second, const Offset(5, 5)),
          ]) {
            target.onDragDone!(
              DropDoneDetails(
                files: [DropItemFile(file.path)],
                localPosition: at,
                globalPosition: at,
              ),
            );
          }
          final button = find.widgetWithText(FilledButton, 'Send to Phone');
          await waitForHome(tester, () => button.evaluate().isNotEmpty);
          expect(find.text('Ready to send: First.txt'), findsOneWidget);
          await tester.tap(button);
          await waitForHome(tester, () => node.sentText == 'First');
          await finishTransition(tester);
          await waitForHome(
            tester,
            () => find
                .text('Ready to send: Second.txt')
                .hitTestable()
                .evaluate()
                .isNotEmpty,
          );
          expect(node.sentPeer, fakes.peerId);
          expect(first.existsSync(), isTrue);
          expect(second.existsSync(), isTrue);
        },
      );
    },
    skip: !(Platform.isMacOS || Platform.isWindows || Platform.isLinux),
  );

  for (final targetStillPaired in [true, false]) {
    testWidgets(
      targetStillPaired
          ? 'a confirmed Android share sends without a second recipient click'
          : 'a stale confirmed Android share keeps the file for a named replacement',
      (tester) async {
        final node = RecordingNode();
        await withHomeTestEnvironment(
          tester,
          devices: onlyPhone,
          api: fakes.FakeRustApi(node),
          run: (directory) async {
            await openHome(tester);
            final staged = File('${directory.path}/Shared.jpg')
              ..writeAsStringSync('shared photo');
            final messenger = tester.binding.defaultBinaryMessenger;
            const share = MethodChannel('vela/share');
            const clipboard = MethodChannel('vela/clipboard');
            var waiting = true;
            String? completed;
            messenger.setMockMethodCallHandler(share, (call) async {
              if (call.method == 'completeConfirmed') {
                completed = call.arguments as String;
              }
              if (!waiting || call.method != 'takeConfirmed') return null;
              waiting = false;
              return {
                'uris': ['content://test/photo'],
                'preferredPeer': targetStillPaired ? fakes.peerId : 'c' * 64,
                'serviceRequest': 'native-request',
              };
            });
            messenger.setMockMethodCallHandler(
              clipboard,
              (_) async => staged.path,
            );
            addTearDown(
              () => messenger.setMockMethodCallHandler(clipboard, null),
            );
            unawaited(
              messenger.handlePlatformMessage(
                share.name,
                const StandardMethodCodec().encodeMethodCall(
                  const MethodCall('confirmedAvailable'),
                ),
                (_) {},
              ),
            );
            await waitForHome(tester, () => completed != null);
            expect(completed, 'native-request');
            expect(find.text('Choose device'), findsNothing);
            if (!targetStillPaired) {
              expect(node.attemptedPath, isNull);
              expect(staged.existsSync(), isTrue);
              await tester.pump();
              await tester.tap(find.text('Send to Phone instead'));
            }
            await waitForSend(tester);
            expect(node.sentPeer, fakes.peerId);
            expect(node.sentText, 'shared photo');
            expect(staged.existsSync(), isFalse);
          },
        );
      },
      skip: !(Platform.isMacOS || Platform.isAndroid),
    );
  }

  testWidgets('sending a folder deletes the temporary archive after success', (
    tester,
  ) async {
    final node = RecordingNode();
    final folderJob = FolderJob();
    await withHomeTestEnvironment(
      tester,
      devices: devices,
      api: RecordingApi(node, folderJob),
      run: (directory) async {
        final originalPicker = FilePickerPlatform.instance;
        final source = '${directory.path}/source';
        FilePickerPlatform.instance = FolderPicker(source);
        try {
          await openHome(tester);
          await tester.tap(find.byKey(const ValueKey('send-folder')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('source'), findsOneWidget);
          await choosePhone(tester);
          await waitForSend(tester);
          expect(folderJob.source, source);
          expect(node.sentText, 'archive');
          expect(node.sentKind, 'file');
          expect(node.sentName, 'test.vela-folder.zip');
          expect(
            File('${directory.path}/test.vela-folder.zip').existsSync(),
            isFalse,
          );
        } finally {
          FilePickerPlatform.instance = originalPicker;
        }
      },
    );
  }, skip: !Platform.isMacOS);
}
