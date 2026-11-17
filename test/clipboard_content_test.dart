import 'package:vela/clipboard_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes only a complete HTTP or HTTPS link', () {
    expect(
      detectHttpLink('  https://example.com/a?q=1  '),
      'https://example.com/a?q=1',
    );
    expect(detectHttpLink('HTTPS://example.com'), 'https://example.com');
    expect(detectHttpLink('https://'), isNull);
    expect(detectHttpLink('https://example.com other text'), isNull);
    expect(detectHttpLink('javascript:alert(1)'), isNull);
  });
}
