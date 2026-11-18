import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.widgetWithText(ListTile, 'Phone').last);
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
          await openHome(tester);
          await tester.tap(find.byKey(const ValueKey('send-text')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          await tester.enterText(find.byType(TextField), 'Hello from Vela');
          await tester.pump();
          final send = find.widgetWithText(FilledButton, 'Send to Phone');
          expect(send.hitTestable(), findsOneWidget);
          expect(node.attemptedPath, isNull);
          await tester.tap(send);
          await waitForHome(tester, () => node.attemptedPath != null);
          expect(find.text('Connecting to Phone'), findsOneWidget);
          node.currentProgress = TransferProgress(
            done: BigInt.zero,
            total: BigInt.from(80),
            path: 'direct',
            udpBytesSent: BigInt.zero,
          );
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.text('Waiting for Phone to respond'), findsOneWidget);
          node.currentProgress = TransferProgress(
            done: BigInt.from(40),
            total: BigInt.from(80),
            path: 'direct',
            udpBytesSent: BigInt.from(42),
          );
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.text('Sending to Phone'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(ActivityNotice),
              matching: find.text('Text'),
            ),
            findsOneWidget,
          );
          gate.complete();
          await waitForSend(tester);
          await tester.pump(const Duration(seconds: 6));
          final receipt = find.byKey(const ValueKey('send-receipt'));
          expect(
            find.byKey(const ValueKey('peer-${fakes.peerId}')).hitTestable(),
            findsOneWidget,
          );
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
        } finally {
          if (!gate.isCompleted) gate.complete();
        }
      },
    );
  });

  testWidgets('going back from device selection keeps the draft for sending', (
    tester,
  ) async {
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
        final recipient = find.byKey(const ValueKey('text-recipient'));
        await tester.tap(recipient);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('Phone · '), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Hello from Vela'), findsOneWidget);
        expect(node.sentText, isNull);
        await tester.tap(recipient);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.textContaining('Phone · '));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.widgetWithText(FilledButton, 'Send to Phone'));
        await waitForSend(tester);
        expect(node.sentText, 'Hello from Vela');
        expect(node.sentKind, 'typed_text');
        expect(node.sentName, endsWith('.txt'));
      },
    );
  });

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
        await tester.tap(find.byKey(const ValueKey('text-recipient')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.textContaining('Phone · '));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.widgetWithText(FilledButton, 'Send to Phone'));
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
        await tester.tap(find.widgetWithText(FilledButton, 'Send to Phone'));
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
          expect(find.text('Ready to send: Report.txt'), findsOneWidget);
          expect(find.text('Send to Phone'), findsOneWidget);
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
          expect(find.text('Ready to send: source'), findsOneWidget);
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
