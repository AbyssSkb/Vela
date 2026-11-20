import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

class PlatformClipboard {
  const PlatformClipboard({this.platform});

  final TargetPlatform? platform;
  static const channel = MethodChannel('vela/clipboard');

  String get _os => platform?.name.toLowerCase() ?? Platform.operatingSystem;
  bool get _usesDocumentProvider => _os == 'android';

  Future<({List<String> files, Uint8List? image, String? text})> read() async {
    final androidImage = _usesDocumentProvider ? await Pasteboard.image : null;
    final files = androidImage == null ? await readFiles() : const <String>[];
    if (files.isNotEmpty) return (files: files, image: null, text: null);
    final image = _usesDocumentProvider ? androidImage : await Pasteboard.image;
    final text = image == null
        ? (await Clipboard.getData(Clipboard.kTextPlain))?.text
        : null;
    return (files: files, image: image, text: text);
  }

  Future<List<String>> readFiles() async => _usesDocumentProvider
      ? await channel.invokeListMethod<String>('files') ?? const []
      : Pasteboard.files();

  Future<void> writeText(String text) => _usesDocumentProvider
      ? channel.invokeMethod<void>('writeText', {'text': text})
      : Clipboard.setData(ClipboardData(text: text));

  Future<void> writeImage(Uint8List image) => _os == 'linux'
      ? channel.invokeMethod<void>('writeImage', {'bytes': image})
      : Pasteboard.writeImage(image);

  Future<void> writeFiles(List<String> references) async {
    if (_usesDocumentProvider) {
      await channel.invokeMethod<void>('writeFiles', {'paths': references});
    } else if (!await Pasteboard.writeFiles(references)) {
      throw StateError('Clipboard rejected received files');
    }
  }
}

String? detectHttpLink(String text) {
  final value = text.trim();
  if (value.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(value);
  return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty
      ? uri.toString()
      : null;
}
