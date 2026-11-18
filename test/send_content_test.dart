import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela/main.dart';
import 'package:vela/peer_state.dart';
import 'package:vela/src/rust/api/folder.dart';
import 'package:vela/src/rust/api/node.dart';

import 'support/fakes.dart' as fakes;
import 'support/home_environment.dart';

class RecordingNode extends fakes.FakeNode {
  String? sentText;
  String? sentKind;
  String? sentName;
  @override
  TransferJob newTransferJob() => RecordingTransferJob(this);
}

class RecordingTransferJob extends fakes.FakeTransferJob {
  RecordingTransferJob(this.node);
  final RecordingNode node;
  @override
  Future<void> sendFile({
    required String peerId,
    required String path,
    required String kind,
  }) async {
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

Future<void> choosePhoneAndWaitForSend(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.widgetWithText(ListTile, 'Phone').last);
  await waitForHome(
    tester,
    () => find
        .descendant(
          of: find.byType(SnackBar),
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

  testWidgets('composed text is sent as a typed_text .txt file', (
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
        await tester.tap(find.text('Send text').last);
        await choosePhoneAndWaitForSend(tester);
        expect(node.sentText, 'Hello from Vela');
        expect(node.sentKind, 'typed_text');
        expect(node.sentName, endsWith('.txt'));
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
          await choosePhoneAndWaitForSend(tester);
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
