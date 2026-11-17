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

  test(
    'saved resources preserve document URIs and validate the response',
    () async {
      messenger.setMockMethodCallHandler(
        storageChannel,
        (call) async => [
          {'path': 'content://downloads/1', 'name': 'photo.png'},
        ],
      );
      final saved = await storage.saveReceived(['/private/photo.png']);
      expect(saved.single.reference, 'content://downloads/1');
      expect(saved.single.name, 'photo.png');

      messenger.setMockMethodCallHandler(
        storageChannel,
        (call) async => [
          {'path': '', 'name': 'photo.png'},
        ],
      );
      await expectLater(
        storage.saveReceived(['/private/photo.png']),
        throwsFormatException,
      );
      messenger.setMockMethodCallHandler(storageChannel, (call) async => []);
      await expectLater(
        storage.saveReceived(['/private/photo.png']),
        throwsFormatException,
      );
    },
  );

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
