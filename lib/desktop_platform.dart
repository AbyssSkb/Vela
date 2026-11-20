import 'dart:io';

class DesktopPlatform {
  static bool get isWindowsOrLinux => Platform.isWindows || Platform.isLinux;

  static bool get isDesktop => Platform.isMacOS || isWindowsOrLinux;

  static String openAfterReceiveKey(String profile) =>
      'desktop_open_after_receive_$profile';
}
