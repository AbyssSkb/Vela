import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'content_kind.dart';
import 'desktop_platform.dart';

class ReceiveLocation {
  const ReceiveLocation({
    required this.isDefault,
    required this.displayPath,
    this.directoryPath,
  });

  final bool isDefault;
  final String displayPath;
  // Android document trees have no path that Dart file IO can use.
  final String? directoryPath;

  factory ReceiveLocation.fromMap(Map<dynamic, dynamic> value) {
    if (value['isDefault'] is! bool ||
        value['displayPath'] is! String ||
        (value['directoryPath'] != null &&
            (value['directoryPath'] is! String ||
                value['directoryPath'] == ''))) {
      throw const FormatException('Invalid receive location');
    }
    return ReceiveLocation(
      isDefault: value['isDefault'] as bool,
      displayPath: value['displayPath'] as String,
      directoryPath: value['directoryPath'] as String?,
    );
  }
}

class SavedReceivedFile {
  const SavedReceivedFile({
    required this.reference,
    required this.name,
    required this.size,
  });

  // A local path or a platform document URI; use ReceivedStorage to access it.
  final String reference;
  final String name;
  final int size;

  factory SavedReceivedFile._fromPlatform(Object? value, int size) {
    if (value is! Map ||
        value['path'] is! String ||
        value['path'] == '' ||
        value['name'] is! String ||
        value['name'] == '') {
      throw const FormatException('Invalid saved file');
    }
    return SavedReceivedFile(
      reference: value['path'] as String,
      name: value['name'] as String,
      size: size,
    );
  }
}

class ReceivedStorage {
  const ReceivedStorage({this.platform});

  final TargetPlatform? platform;
  TargetPlatform get _platform => platform ?? defaultTargetPlatform;
  bool get _desktop =>
      _platform == TargetPlatform.windows || _platform == TargetPlatform.linux;
  static const _storage = MethodChannel('vela/storage');
  static const _files = MethodChannel('vela/files');
  static const _directoryKey = 'desktop_receive_directory';

  Future<ReceiveLocation> location() async {
    if (_desktop) {
      final prefs = await SharedPreferences.getInstance();
      final selected = prefs.getString(_directoryKey);
      final directory = selected == null
          ? await getDownloadsDirectory() ??
                await getApplicationDocumentsDirectory()
          : Directory(selected);
      if (!directory.isAbsolute) {
        throw const FormatException('Receive directory must be absolute');
      }
      return ReceiveLocation(
        isDefault: selected == null,
        displayPath: directory.path,
        directoryPath: directory.path,
      );
    }
    final value = await _storage.invokeMapMethod<dynamic, dynamic>('location');
    if (value == null) throw const FormatException('Missing receive location');
    return ReceiveLocation.fromMap(value);
  }

  Future<({String path, bool privateFallback})> receiveDirectory(
    String profile,
    TransferKind kind,
  ) async {
    final base = Platform.isAndroid
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final privateDir = await Directory('${base.path}/Vela/$profile')
        .create(recursive: true);
    if (DesktopPlatform.isDesktop && kind.isFile) {
      try {
        return (path: (await writableDirectory()).path, privateFallback: false);
      } catch (e) {
        debugPrint('Save location unavailable: $e');
        return (path: privateDir.path, privateFallback: true);
      }
    }
    return (path: privateDir.path, privateFallback: false);
  }

  Future<Directory> writableDirectory() async {
    final current = await location();
    final path = current.directoryPath;
    if (path == null)
      throw StateError('Receive location has no local directory');
    final directory = Directory(path);
    if (!await directory.exists()) {
      if (_desktop && current.isDefault) {
        await directory.create(recursive: true);
      } else {
        throw StateError('Selected folder is unavailable');
      }
    }
    final probe = File(
      '${directory.path}/.vela-write-${DateTime.now().microsecondsSinceEpoch}',
    );
    await probe.create(exclusive: true);
    await probe.delete();
    return directory;
  }

  Future<bool> chooseLocation() async {
    if (_desktop) {
      final path = await FilePicker.getDirectoryPath();
      if (path == null) return false;
      if (!Directory(path).isAbsolute || !await Directory(path).exists()) {
        throw StateError('Selected folder is unavailable');
      }
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_directoryKey, path)) {
        throw StateError('Could not save receive directory');
      }
      return true;
    }
    return await _storage.invokeMethod<bool>('choose') ?? false;
  }

  Future<void> resetLocation() async {
    if (_desktop) {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.remove(_directoryKey)) {
        throw StateError('Could not reset receive directory');
      }
      return;
    }
    await _storage.invokeMethod<void>('reset');
  }

  Future<({List<SavedReceivedFile> files, bool savedPrivately})> finishReceive(
    List<String> paths, {
    required bool publishFromStaging,
    required bool Function() isCancelled,
  }) async {
    final local = await Future.wait(
      paths.map((path) async {
        final file = File(path);
        return SavedReceivedFile(
          reference: path,
          name: file.uri.pathSegments.last,
          size: await file.length(),
        );
      }),
    );
    if (!publishFromStaging) return (files: local, savedPrivately: false);

    try {
      if (isCancelled()) throw PlatformException(code: 'cancelled');
      final values = await _storage.invokeListMethod<dynamic>('saveReceived', {
        'paths': paths,
      });
      if (values == null || values.length != paths.length) {
        throw const FormatException('Save did not finish');
      }
      final saved = [
        for (var i = 0; i < values.length; i++)
          SavedReceivedFile._fromPlatform(values[i], local[i].size),
      ];
      await _deleteStagedFiles(paths);
      return (files: saved, savedPrivately: false);
    } catch (error) {
      if (isCancelled() ||
          (error is PlatformException && error.code == 'cancelled')) {
        await _deleteStagedFiles(paths);
        rethrow;
      }
      debugPrint('Could not save to selected location: $error');
      return (files: local, savedPrivately: true);
    }
  }

  Future<void> _deleteStagedFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        await File(path).delete();
      } on FileSystemException catch (error) {
        debugPrint('Could not remove temporary file: $error');
      }
    }
  }

  Future<void> cancelSave() => _storage.invokeMethod<void>('cancelSave');

  Future<bool> exists(String reference) async {
    if (_isDocumentUri(reference)) {
      return await _files.invokeMethod<bool>('existsUri', {
            'path': reference,
          }) ??
          false;
    }
    return File(reference).exists();
  }

  Future<void> delete(String reference) async {
    if (_isDocumentUri(reference)) {
      await _files.invokeMethod<void>('deleteUri', {'path': reference});
    } else {
      await File(reference).delete();
    }
  }

  Future<void> open(String reference) async {
    if (_platform == TargetPlatform.android ||
        _platform == TargetPlatform.windows) {
      await _files.invokeMethod<void>('openPath', {'path': reference});
      return;
    }
    final result = await OpenFilex.open(reference);
    if (result.type != ResultType.done) {
      throw PlatformException(
        code: result.type == ResultType.noAppToOpen ? 'no_app' : 'open',
        message: result.message,
      );
    }
  }

  Future<void> openFolder({String? reference}) async {
    if ((_platform == TargetPlatform.macOS || _desktop) && reference != null) {
      await _files.invokeMethod<void>('reveal', {'path': reference});
    } else if (_desktop) {
      await _files.invokeMethod<void>('reveal', {
        'path': (await location()).directoryPath,
      });
    } else {
      await _storage.invokeMethod<void>(
        'openFolder',
        reference == null ? null : {'path': reference},
      );
    }
  }

  Future<bool> export(String reference, String name) async {
    if (_platform == TargetPlatform.android) {
      return await _files.invokeMethod<bool>('saveAs', {
            'path': reference,
            'name': name,
          }) ??
          false;
    }
    if (_platform == TargetPlatform.macOS || _desktop) {
      await openFolder(reference: reference);
    }
    return false;
  }

  bool _isDocumentUri(String reference) => reference.startsWith('content:');
}
