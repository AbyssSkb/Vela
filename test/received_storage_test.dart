import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela/received_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storageChannel = MethodChannel('vela/storage');
  const filesChannel = MethodChannel('vela/files');
  const storage = ReceivedStorage(platform: TargetPlatform.android);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(storageChannel, null);
    messenger.setMockMethodCallHandler(filesChannel, null);
  });

  test('display location is not treated as a local IO directory', () async {
    messenger.setMockMethodCallHandler(
      storageChannel,
      (call) async => {'isDefault': false, 'displayPath': 'Downloads/Vela'},
    );
    final location = await storage.location();
    expect(location.displayPath, 'Downloads/Vela');
    expect(location.directoryPath, isNull);
    await expectLater(storage.writableDirectory(), throwsStateError);
  });

  group('finalizing received files', () {
    late Directory staging;
    late List<String> paths;

    setUp(() async {
      staging = await Directory.systemTemp.createTemp('vela-staged-files-');
      paths = [
        for (final name in ['first', 'second'])
          (await File('${staging.path}/$name').writeAsString(name)).path,
      ];
    });

    tearDown(() => staging.delete(recursive: true));

    test(
      'publishes the complete batch before removing staging files',
      () async {
        messenger.setMockMethodCallHandler(storageChannel, (call) async {
          expect(call.method, 'saveReceived');
          expect(call.arguments, {'paths': paths});
          return [
            {
              'path': 'content://documents/1',
              'name': 'first (1)',
              'folderLabel': 'Incoming files',
            },
            {
              'path': 'content://documents/2',
              'name': 'second',
              'folderLabel': 'Incoming files',
            },
          ];
        });
        final result = await storage.finishReceive(
          paths,
          publishFromStaging: true,
          isCancelled: () => false,
        );
        expect(result.savedPrivately, isFalse);
        expect(result.files.map((f) => (f.reference, f.name, f.size)), [
          ('content://documents/1', 'first (1)', 5),
          ('content://documents/2', 'second', 6),
        ]);
        expect(result.files.map((file) => file.folderLabel).toSet(), {
          'Incoming files',
        });
        expect(await staging.list().toList(), isEmpty);
      },
    );

    test(
      'keeps every private file on a failed or incomplete publication',
      () async {
        for (final reply in <Object>[
          PlatformException(code: 'storage'),
          [],
          [
            {'path': 'content://downloads/1', 'name': 'first'},
            {'path': '', 'name': 'second'},
          ],
        ]) {
          messenger.setMockMethodCallHandler(storageChannel, (_) async {
            if (reply is PlatformException) throw reply;
            return reply;
          });
          final result = await storage.finishReceive(
            paths,
            publishFromStaging: true,
            isCancelled: () => false,
          );
          expect(result.savedPrivately, isTrue);
          expect(result.files.map((f) => f.reference), paths);
          expect(await File(paths.first).readAsString(), 'first');
          expect(await File(paths.last).readAsString(), 'second');
        }
      },
    );

    for (final alreadyCancelled in [true, false]) {
      test(
        'removes staging on cancellation ${alreadyCancelled ? 'before' : 'during'} publication',
        () async {
          var calls = 0;
          messenger.setMockMethodCallHandler(storageChannel, (_) async {
            calls++;
            throw PlatformException(code: 'cancelled');
          });
          await expectLater(
            storage.finishReceive(
              paths,
              publishFromStaging: true,
              isCancelled: () => alreadyCancelled,
            ),
            throwsA(
              isA<PlatformException>().having(
                (e) => e.code,
                'code',
                'cancelled',
              ),
            ),
          );
          expect(calls, alreadyCancelled ? 0 : 1);
          expect(await staging.list().toList(), isEmpty);
        },
      );
    }

    test('direct receives keep the file at its final location', () async {
      final result = await storage.finishReceive(
        paths,
        publishFromStaging: false,
        isCancelled: () => false,
      );
      expect(result.savedPrivately, isFalse);
      expect(result.files.first.reference, paths.first);
      expect(await File(paths.first).readAsString(), 'first');
    });
  });

  test(
    'document access and reveal stay behind the platform contract',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(filesChannel, (call) async {
        calls.add(call);
        if (call.method == 'existsUri') return true;
        return null;
      });
      messenger.setMockMethodCallHandler(storageChannel, (call) async {
        calls.add(call);
        return null;
      });
      const reference = 'content://downloads/1';
      expect(await storage.exists(reference), isTrue);
      await storage.delete(reference);
      await storage.open(reference);
      await storage.openFolder(reference: reference);
      expect(calls.map((call) => call.method), [
        'existsUri',
        'deleteUri',
        'openPath',
        'openFolder',
      ]);
      expect(calls.last.arguments, {'path': reference});
    },
  );
}
