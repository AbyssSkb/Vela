import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  final driver = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  try {
    await driver.waitFor(find.byTooltip('我的设备'));
    await driver.tap(find.byTooltip('我的设备'));
    await driver.waitFor(find.byType('QrImageView'));
    final id = await driver.getText(find.byValueKey('device-id'));
    await File(args[1]).writeAsBytes(await driver.screenshot());
    await File(args[2]).writeAsString('vela:1:$id');
  } finally {
    await driver.close();
  }
}
