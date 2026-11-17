import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  for (final url in args) {
    final driver = await FlutterDriver.connect(dartVmServiceUrl: url);
    try {
      await driver.waitFor(find.text('连接你的设备'));
      final before = await driver.getTopLeft(find.text('连接你的设备'));
      await driver.scroll(
        find.byType('CustomScrollView'),
        0,
        -100,
        const Duration(milliseconds: 300),
      );
      final after = await driver.getTopLeft(find.text('连接你的设备'));
      if ((before.dy - after.dy).abs() > 1) {
        throw StateError('Empty page scrolls unnecessarily');
      }
      await driver.tap(find.byValueKey('add-device'));
      await driver.waitFor(find.byValueKey('peer-id'));
      await driver.tap(find.text('取消'));
    } finally {
      await driver.close();
    }
  }
}
