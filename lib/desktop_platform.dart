import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DesktopPlatform {
  static bool get isWindowsOrLinux => Platform.isWindows || Platform.isLinux;

  static Future<void> restoreBackgroundSettings(SharedPreferences prefs) async {
    if (!isWindowsOrLinux) return;
    try {
      await const MethodChannel('vela/background').invokeMethod<void>(
        'setDesktopBackground',
        prefs.getBool('desktop_background_receiving') ?? true,
      );
    } on PlatformException catch (error) {
      debugPrint('Could not restore background reception: $error');
    }
  }

  static Future<void> writeClipboardImage(Uint8List bytes) async {
    if (Platform.isLinux) {
      await const MethodChannel('vela/clipboard')
          .invokeMethod<void>('writeImage', {'bytes': bytes});
    } else {
      await Pasteboard.writeImage(bytes);
    }
  }
}
