import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vela/content_kind.dart';
import 'package:vela/received_storage.dart';

class DirectoryPicker extends FilePickerPlatform {
  String? path;

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

class DownloadsProvider extends PathProviderPlatform {
  DownloadsProvider(this.path);
  final String path;

  @override
  Future<String?> getDownloadsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async =>
      '${Directory(path).parent.path}/Support';

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      '${Directory(path).parent.path}/Documents';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = ReceivedStorage(platform: TargetPlatform.windows);
  const files = MethodChannel('vela/files');
  const nativeStorage = MethodChannel('vela/storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temporary;
  late DirectoryPicker picker;
  late FilePickerPlatform previousPicker;
  late PathProviderPlatform previousPaths;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('vela-receive-location-');
    previousPicker = FilePickerPlatform.instance;
    picker = DirectoryPicker();
    FilePickerPlatform.instance = picker;
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = DownloadsProvider(
      '${temporary.path}/Downloads',
    );
  });

  tearDown(() async {
    FilePickerPlatform.instance = previousPicker;
    PathProviderPlatform.instance = previousPaths;
    messenger.setMockMethodCallHandler(files, null);
    messenger.setMockMethodCallHandler(nativeStorage, null);
    await temporary.delete(recursive: true);
  });

  test('receive storage selects the destination and publication together', () async {
    final downloads = await Directory('${temporary.path}/Downloads').create();
    messenger.setMockMethodCallHandler(nativeStorage, (call) async {
      expect(call.method, 'location');
      return {
        'isDefault': true,
        'displayPath': 'Downloads',
        'directoryPath': downloads.path,
      };
    });

    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      final storage = ReceivedStorage(platform: platform);
      final file = await storage.receiveDirectory('test', TransferKind.file);
      final text = await storage.receiveDirectory(
        'test',
        TransferKind.typedText,
      );
      final android = platform == TargetPlatform.android;
      final ios = platform == TargetPlatform.iOS;
      expect(storage.supportsReceiveLocation, !ios);
      expect(storage.supportsSaveAs, android);
      expect(file.publishFromStaging, android);
      expect(
        file.path,
        android
            ? '${temporary.path}/Support/Vela/test'
            : ios
            ? '${temporary.path}/Documents/Vela/test'
            : downloads.path,
      );
      expect(text.publishFromStaging, isFalse);
      expect(
        text.path,
        '${temporary.path}/${android || ios ? 'Support' : 'Documents'}/Vela/test',
      );
    }
  });

  test(
    'an unavailable macOS location keeps the incoming file private',
    () async {
      messenger.setMockMethodCallHandler(nativeStorage, (_) async {
        throw PlatformException(code: 'unavailable');
      });
      final destination = await const ReceivedStorage(
        platform: TargetPlatform.macOS,
      ).receiveDirectory('test', TransferKind.file);
      expect(destination.privateFallback, isTrue);
      expect(destination.publishFromStaging, isFalse);
      expect(destination.path, '${temporary.path}/Documents/Vela/test');
    },
  );

  test('persists selected directories, rejects missing paths, and resets to Downloads', () async {
    final selected = await Directory('${temporary.path}/chosen').create();
    picker.path = selected.path;
    expect(await storage.chooseLocation(), isTrue);
    expect((await storage.location()).directoryPath, selected.path);
    expect((await storage.location()).isDefault, isFalse);
    expect((await storage.writableDirectory()).path, selected.path);
    expect(await selected.list().toList(), isEmpty);
    await selected.delete();
    await expectLater(storage.writableDirectory(), throwsStateError);
    await storage.resetLocation();
    expect((await storage.location()).isDefault, isTrue);
    final downloads = await storage.writableDirectory();
    expect(downloads.path, '${temporary.path}/Downloads');
    expect(await downloads.exists(), isTrue);
  });

  test(
    'cancelled or invalid selections preserve the previous destination',
    () async {
      picker.path = temporary.path;
      await storage.chooseLocation();
      picker.path = null;
      expect(await storage.chooseLocation(), isFalse);
      picker.path = 'relative-path';
      await expectLater(storage.chooseLocation(), throwsStateError);
      expect((await storage.location()).directoryPath, temporary.path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('desktop_receive_directory', 'relative-path');
      await expectLater(storage.location(), throwsFormatException);
    },
  );

  test(
    'Windows opens received filenames literally through the native channel',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(files, (call) async {
        calls.add(call);
        return null;
      });
      const reference = r'C:\Downloads\notes & %TEMP% (final).txt';
      await storage.open(reference);
      expect(calls.single.method, 'openPath');
      expect(calls.single.arguments, {'path': reference});
    },
  );

  test(
    'desktop history reveals files through the native file manager',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(files, (call) async {
        calls.add(call);
        return null;
      });
      final reference = '${temporary.path}/file.txt';
      await storage.openFolder(reference: reference);
      expect(await storage.export(reference, 'file.txt'), isFalse);
      expect(calls.map((call) => call.method), ['reveal', 'reveal']);
      expect(calls.last.arguments, {'path': reference});
    },
  );
}
