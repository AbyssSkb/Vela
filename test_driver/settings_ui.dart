import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  final d = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  try {
    await d.runUnsynchronized(() async {
      await d.waitFor(
        find.byTooltip('设置'),
        timeout: const Duration(seconds: 30),
      );
      await d.tap(find.byTooltip('设置'));
      await d.waitFor(find.text('设备名称'));
      await d.tap(find.text('外观'));
      await d.waitFor(find.text('深色'), timeout: const Duration(seconds: 10));
      if (args.length > 1) {
        await File(args[1]).writeAsBytes(await d.screenshot());
      }
      await d.tap(find.text('深色'));
      await d.waitFor(find.text('深色'), timeout: const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (args.length > 2) {
        await File(args[2]).writeAsBytes(await d.screenshot());
      }
      await d.tap(find.text('语言'));
      await d.waitFor(
        find.text('English'),
        timeout: const Duration(seconds: 10),
      );
      await d.tap(find.text('English'));
      await d.waitFor(
        find.text('Settings'),
        timeout: const Duration(seconds: 10),
      );
      await d.waitFor(find.text('Device name'));
      await d.tap(find.text('Language'));
      await d.waitFor(
        find.text('Simplified Chinese'),
        timeout: const Duration(seconds: 10),
      );
      await d.tap(find.text('Simplified Chinese'));
      await d.waitFor(find.text('设置'), timeout: const Duration(seconds: 10));
      await d.tap(find.text('设备名称'));
      await d.waitFor(find.text('保存'), timeout: const Duration(seconds: 10));
      await d.tap(find.byType('TextField'));
      await d.enterText('Vela test device');
      await d.tap(find.text('保存'));
      await d.waitFor(
        find.text('Vela test device'),
        timeout: const Duration(seconds: 10),
      );
      stdout.writeln('SETTINGS_INTERACTIONS_OK');
    });
  } finally {
    await d.close();
  }
}
