import 'dart:convert';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  final mac = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final android = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  final macName =
      (jsonDecode(await mac.requestData(jsonEncode({'action': 'device'})))
              as Map)['name']
          as String;
  try {
    await android.waitFor(
      find.text('已选择文字，点击设备发送'),
      timeout: const Duration(seconds: 30),
    );
    await android.tap(find.text(macName));
    await mac.waitFor(
      find.byValueKey('accept-offer'),
      timeout: const Duration(seconds: 60),
    );
    await mac.tap(find.byValueKey('accept-offer'));
    await mac.waitFor(find.text('剪贴板内容已接收'));
    final text = await mac.requestData(
      jsonEncode({'action': 'get-clipboard', 'kind': 'text'}),
    );
    if (text != 'cold-start-test') throw StateError('cold share mismatch');
    print('ANDROID_COLD_SHARE_TEST_OK'); // ignore: avoid_print
  } finally {
    await mac.close();
    await android.close();
  }
}
