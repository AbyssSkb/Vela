import 'dart:convert';
import 'dart:io';

import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/transfer_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records survive serialization with legacy entries', () {
    final record = TransferRecord(
      name: 'image.png',
      peer: 'Phone',
      time: DateTime(2026, 1, 2),
      kind: HistoryKind.file,
      received: true,
      fileReference: '/image.png',
      size: 42,
    );
    final restored = TransferRecord.decode(jsonEncode([record.toJson()]))
        .single;
    expect(restored.fileReference, '/image.png');
    expect(record.toJson()['path'], '/image.png');
    expect(restored.size, 42);
    expect(restored.received, isTrue);
    final legacy = record.toJson()..remove('size');
    expect(TransferRecord.decode(jsonEncode([legacy])).single.size, isNull);
    expect(
      TransferRecord.decode(
        jsonEncode([
          {'broken': true},
          legacy,
        ]),
      ).single.name,
      'image.png',
    );
  });

  test(
    'record-only removal keeps files; failed file deletion keeps its record',
    () async {
      final dir = await Directory.systemTemp.createTemp('vela-history-test-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/received.txt');
      await file.writeAsString('keep me');
      final folder = await Directory('${dir.path}/not-a-file').create();
      TransferRecord record(String name, String path) => TransferRecord(
        name: name,
        peer: 'Phone',
        time: DateTime.now(),
        kind: HistoryKind.file,
        received: true,
        fileReference: path,
      );
      final existing = record('received.txt', file.path);
      final invalid = record('not-a-file', folder.path);
      final missing = record('missing', '${dir.path}/missing');
      final recordsOnly = await deleteFilesAndSelectRemovableRecords([
        existing,
      ], deleteFiles: false);
      expect(recordsOnly.removed, [existing]);
      expect(await file.readAsString(), 'keep me');
      final withFiles = await deleteFilesAndSelectRemovableRecords([
        existing,
        invalid,
        missing,
      ], deleteFiles: true);
      expect(withFiles.removed, [existing, missing]);
      expect(withFiles.failed, isTrue);
      expect(await file.exists(), isFalse);
      expect(await folder.exists(), isTrue);
    },
  );

  test(
    'content URI deletion is explicit and failures preserve the record',
    () async {
      final record = TransferRecord(
        name: 'photo.png',
        peer: 'Phone',
        time: DateTime.now(),
        kind: HistoryKind.file,
        received: true,
        fileReference: 'content://downloads/1',
      );
      var calls = 0;
      final keep = await deleteFilesAndSelectRemovableRecords(
        [record],
        deleteFiles: false,
        deleteFile: (_) async {
          calls++;
        },
      );
      expect(keep.removed, [record]);
      expect(calls, 0);
      final failure = await deleteFilesAndSelectRemovableRecords(
        [record],
        deleteFiles: true,
        deleteFile: (_) async {
          calls++;
          throw StateError('denied');
        },
      );
      expect(failure.removed, isEmpty);
      expect(failure.failed, isTrue);
      final deleted = await deleteFilesAndSelectRemovableRecords(
        [record],
        deleteFiles: true,
        deleteFile: (_) async {
          calls++;
        },
      );
      expect(deleted.removed, [record]);
      expect(calls, 2);
    },
  );

  testWidgets('history fits narrow screens and opens a received file', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final record = TransferRecord(
      name: '${'very-long-file-name-' * 12}.pdf',
      peer: 'Phone',
      time: DateTime.now(),
      kind: HistoryKind.file,
      received: true,
      fileReference: '/file.pdf',
      size: 1024,
    );
    final records = ValueNotifier([record]);
    TransferRecord? opened;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TransferHistoryPage(
          records: records,
          open: (item) async => opened = item,
          export: (_) async {},
          openFolder: () async {},
          reveal: (_) async {},
          remove: (_, {required bool deleteFiles}) async {},
        ),
      ),
    );
    expect(find.text('Today'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(record.name));
    expect(opened, same(record));
  });
  testWidgets('text and files share compact metadata and details', (
    tester,
  ) async {
    final records = ValueNotifier([
      TransferRecord(
        name: 'Clipboard text',
        peer: 'Phone',
        time: DateTime(2026, 1, 2, 10, 30),
        kind: HistoryKind.text,
        received: true,
        fileReference: '/clip.txt',
        size: 1024,
        preview: 'https://example.com',
      ),
      TransferRecord(
        name: 'report.pdf',
        peer: 'Mac',
        time: DateTime(2026, 1, 2, 10, 31),
        kind: HistoryKind.file,
        received: true,
        fileReference: '/report.pdf',
        size: 2048,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TransferHistoryPage(
          records: records,
          open: (_) async {},
          export: (_) async {},
          openFolder: () async {},
          reveal: (_) async {},
          remove: (_, {required bool deleteFiles}) async {},
        ),
      ),
    );
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Mac'), findsOneWidget);
    expect(find.text('From Phone'), findsNothing);
    expect(find.textContaining('KB'), findsNothing);
    await tester.tap(find.byTooltip('More options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('1.0 KB'), findsOneWidget);
    expect(find.text('Phone'), findsWidgets);
    expect(find.text('File details'), findsNothing);
  });

  testWidgets('history search keeps removal scoped to the results', (
    tester,
  ) async {
    final record = TransferRecord(
      name: 'Clipboard text',
      peer: 'Phone',
      time: DateTime.now(),
      kind: HistoryKind.text,
      received: true,
      fileReference: '/clip.txt',
      preview: 'A useful link',
    );
    final other = TransferRecord(
      name: 'report.pdf',
      peer: 'Mac',
      time: DateTime.now(),
      kind: HistoryKind.file,
      received: true,
      fileReference: '/report.pdf',
    );
    final records = ValueNotifier([record, other]);
    final removed = <TransferRecord>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TransferHistoryPage(
          records: records,
          open: (_) async {},
          export: (_) async {},
          openFolder: () async {},
          reveal: (_) async {},
          remove: (items, {required bool deleteFiles}) async {
            expect(deleteFiles, isFalse);
            removed.addAll(items);
            records.value = records.value
                .where((item) => !items.contains(item))
                .toList();
          },
        ),
      ),
    );
    expect(find.byTooltip('Clear history'), findsOneWidget);
    await tester.tap(find.byTooltip('Search history'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Clear history'), findsNothing);
    await tester.enterText(find.byType(TextField), 'useful');
    await tester.pump();
    expect(find.text('A useful link'), findsOneWidget);
    expect(find.text('report.pdf'), findsNothing);
    await tester.longPress(find.text('A useful link'));
    await tester.pump();
    await tester.tap(find.byTooltip('Select all'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove record'));
    await tester.pumpAndSettle();
    expect(find.text('Remove 1 record?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove records only'));
    await tester.pumpAndSettle();
    expect(removed, [record]);
    expect(records.value, [other]);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('No matching records'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.byTooltip('Clear history'), findsOneWidget);
  });

  testWidgets(
    'history shows received items only and keeps older sent records',
    (tester) async {
      final received = TransferRecord(
        name: 'received.pdf',
        peer: 'Phone',
        time: DateTime.now(),
        kind: HistoryKind.file,
        received: true,
        fileReference: '/received.pdf',
      );
      final sent = TransferRecord(
        name: 'sent.pdf',
        peer: 'Phone',
        time: DateTime.now(),
        kind: HistoryKind.file,
        received: false,
        fileReference: '/sent.pdf',
      );
      final records = ValueNotifier([received, sent]);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TransferHistoryPage(
            records: records,
            open: (_) async {},
            export: (_) async {},
            openFolder: () async {},
            reveal: (_) async {},
            remove: (items, {required bool deleteFiles}) async {
              records.value = records.value
                  .where((item) => !items.contains(item))
                  .toList();
            },
          ),
        ),
      );
      expect(find.text('received.pdf'), findsOneWidget);
      expect(find.text('sent.pdf'), findsNothing);
      await tester.tap(find.byTooltip('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Remove records only'),
      );
      await tester.pumpAndSettle();
      expect(find.text('No received items yet'), findsOneWidget);
      expect(records.value, [sent]);
      expect(find.byTooltip('Clear history'), findsNothing);
    },
  );

  testWidgets('long press selects received records for batch removal', (
    tester,
  ) async {
    final first = TransferRecord(
      name: 'first.pdf',
      peer: 'Phone',
      time: DateTime.now(),
      kind: HistoryKind.file,
      received: true,
      fileReference: '/first.pdf',
    );
    final second = TransferRecord(
      name: 'second.pdf',
      peer: 'Phone',
      time: DateTime.now(),
      kind: HistoryKind.file,
      received: true,
      fileReference: '/second.pdf',
    );
    final sent = TransferRecord(
      name: 'sent.pdf',
      peer: 'Phone',
      time: DateTime.now(),
      kind: HistoryKind.file,
      received: false,
      fileReference: '/sent.pdf',
    );
    final records = ValueNotifier([first, second, sent]);
    final removed = <TransferRecord>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TransferHistoryPage(
          records: records,
          open: (_) async {},
          export: (_) async {},
          openFolder: () async {},
          reveal: (_) async {},
          remove: (items, {required bool deleteFiles}) async {
            removed.addAll(items);
            records.value = records.value
                .where((item) => !removed.contains(item))
                .toList();
          },
        ),
      ),
    );
    await tester.longPress(find.text('first.pdf'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Select all'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove record'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Remove records only'));
    await tester.pumpAndSettle();
    expect(removed, containsAll([first, second]));
    expect(records.value, [sent]);
    expect(find.text('No received items yet'), findsOneWidget);
  });

  testWidgets('batch removal can explicitly include files', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final item = TransferRecord(
      name: 'photo.png',
      peer: 'Phone',
      time: DateTime.now(),
      kind: HistoryKind.file,
      received: true,
      fileReference: '/photo.png',
    );
    final records = ValueNotifier([item]);
    bool? chosenDeleteFiles;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TransferHistoryPage(
          records: records,
          open: (_) async {},
          export: (_) async {},
          openFolder: () async {},
          reveal: (_) async {},
          remove: (items, {required bool deleteFiles}) async {
            chosenDeleteFiles = deleteFiles;
            records.value = [];
          },
        ),
      ),
    );
    await tester.longPress(find.text('photo.png'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove record'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('Also delete files'));
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Delete records and files'),
    );
    await tester.pumpAndSettle();
    expect(chosenDeleteFiles, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single record uses the same unchecked file deletion option', (
    tester,
  ) async {
    final item = TransferRecord(
      name: 'one.pdf',
      peer: 'Phone',
      time: DateTime.now(),
      kind: HistoryKind.file,
      received: true,
      fileReference: '/one.pdf',
    );
    final records = ValueNotifier([item]);
    bool? chosenDeleteFiles;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TransferHistoryPage(
          records: records,
          open: (_) async {},
          export: (_) async {},
          openFolder: () async {},
          reveal: (_) async {},
          remove: (items, {required bool deleteFiles}) async {
            chosenDeleteFiles = deleteFiles;
            records.value = [];
          },
        ),
      ),
    );
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove record'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Remove records only'));
    await tester.pumpAndSettle();
    expect(chosenDeleteFiles, isFalse);
  });

  testWidgets('receive folder, file details and reveal use their own actions', (
    tester,
  ) async {
    final item = TransferRecord(
      name: 'report.pdf',
      peer: 'Phone',
      time: DateTime(2026, 1, 2, 10, 30),
      kind: HistoryKind.file,
      received: true,
      fileReference: '/report.pdf',
      size: 1024,
    );
    var openedFolder = false;
    TransferRecord? revealed;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TransferHistoryPage(
          records: ValueNotifier([item]),
          open: (_) async {},
          export: (_) async {},
          openFolder: () async {
            openedFolder = true;
          },
          reveal: (record) async {
            revealed = record;
          },
          remove: (_, {required bool deleteFiles}) async {},
        ),
      ),
    );
    await tester.tap(find.byTooltip('Open receive folder'));
    expect(openedFolder, isTrue);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('1.0 KB'), findsWidgets);
    expect(find.text('Phone'), findsWidgets);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    if (Platform.isMacOS) {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show in Finder'));
      expect(revealed, same(item));
    }
  });
}
