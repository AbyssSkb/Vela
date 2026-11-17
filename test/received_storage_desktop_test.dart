import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = ReceivedStorage(platform: TargetPlatform.windows);
  const files = MethodChannel('vela/files');
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
    await temporary.delete(recursive: true);
  });

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
