import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'two_apps.dart' show showDeviceCode;

Future<void> main(List<String> args) async {
  final driver = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  try {
    await showDeviceCode(driver);
    await driver.waitFor(find.byType('QrImageView'));
    final id = await driver.getText(
      find.descendant(
        of: find.byValueKey('device-id'),
        matching: find.byType('EditableText'),
      ),
    );
    await File(args[1]).writeAsBytes(await driver.screenshot());
    await File(args[2]).writeAsString('vela:1:$id');
  } finally {
    await driver.close();
  }
}
