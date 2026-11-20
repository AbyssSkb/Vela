import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

class DesktopPlatform {
  static bool get isWindowsOrLinux => Platform.isWindows || Platform.isLinux;

  static bool get isDesktop => Platform.isMacOS || isWindowsOrLinux;

  static String openAfterReceiveKey(String profile) =>
      'desktop_open_after_receive_$profile';

  static Future<void> writeClipboardImage(Uint8List bytes) async {
    if (Platform.isLinux) {
      await const MethodChannel('vela/clipboard')
          .invokeMethod<void>('writeImage', {'bytes': bytes});
    } else {
      await Pasteboard.writeImage(bytes);
    }
  }
}
