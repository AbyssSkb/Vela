import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  const SavedReceivedFile({required this.reference, required this.name});

  // A local path or a platform document URI; use ReceivedStorage to access it.
  final String reference;
  final String name;

  factory SavedReceivedFile.fromMap(Map<dynamic, dynamic> value) {
    if (value['path'] is! String ||
        value['path'] == '' ||
        value['name'] is! String ||
        value['name'] == '') {
      throw const FormatException('Invalid saved file');
    }
    return SavedReceivedFile(
      reference: value['path'] as String,
      name: value['name'] as String,
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

  Future<List<SavedReceivedFile>> saveReceived(List<String> paths) async {
    final values = await _storage.invokeListMethod<dynamic>('saveReceived', {
      'paths': paths,
    });
    if (values == null || values.length != paths.length) {
      throw const FormatException('Save did not finish');
    }
    return values.map((value) {
      if (value is! Map) throw const FormatException('Invalid saved file');
      return SavedReceivedFile.fromMap(value);
    }).toList();
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
