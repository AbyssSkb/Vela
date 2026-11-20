import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  final driver = await FlutterDriver.connect(dartVmServiceUrl: args.single);
  Future<Map> menu() async => jsonDecode(
    await driver.requestData(jsonEncode({'action': 'mac-menu-test'})),
  ) as Map;
  Future<Map> window() async => jsonDecode(
    await driver.requestData(jsonEncode({'action': 'mac-status-test'})),
  ) as Map;
  try {
    var item = await menu();
    if (item['exists'] != true ||
        item['visible'] != true ||
        item['hasImage'] != true ||
        item['windowVisible'] != true ||
        (item['lightColor'] as String).isEmpty) {
      throw StateError('Menu item not visible: $item');
    }
    final idleColor = item['lightColor'];
    await driver.requestData(
      jsonEncode({'action': 'mac-menu-incoming-test', 'value': true}),
    );
    if ((await menu())['lightColor'] == idleColor) {
      throw StateError('Incoming request did not change the status light');
    }
    await driver.requestData(
      jsonEncode({'action': 'mac-menu-incoming-test', 'value': false}),
    );
    if ((await menu())['lightColor'] != idleColor) {
      throw StateError('Status light did not return to idle');
    }
    await driver.requestData(jsonEncode({'action': 'mac-close-test'}));
    if ((await window())['visible'] != false) {
      throw StateError('Closing the window did not hide it');
    }
    item = await menu();
    if (item['visible'] != true || item['windowVisible'] != true) {
      throw StateError('Menu item disappeared after closing the window: $item');
    }
    await driver.requestData(jsonEncode({'action': 'mac-show-test'}));
    if ((await window())['visible'] != true) {
      throw StateError('The window did not reopen');
    }
    stdout.writeln('MAC_MENU_ITEM_CLOSE_REOPEN_OK');
  } finally {
    await driver.close();
  }
}
