import 'package:flutter_test/flutter_test.dart';
import 'package:vela/notification_title.dart';

void main() {
  test('shortens long file names while keeping the extension', () {
    expect(notificationTitle('photo.jpg'), 'photo.jpg');
    expect(
      notificationTitle('FileApex-v0.20.5-Silicon.dmg'),
      'FileApex-v0.20.5-….dmg',
    );
    expect(notificationTitle('很长的文件名称用来测试通知显示效果.pdf'), '很长的文件名称用….pdf');
    expect(notificationTitle('👨‍👩‍👧‍👦' * 20), '👨‍👩‍👧‍👦' * 10 + '…');
  });
}
