import 'package:flutter_test/flutter_test.dart';
import 'package:vela/pending_share.dart';

void main() {
  test('reads native lists and flags without another JSON layer', () {
    final paths = ['/tmp/shared.txt'];
    final share = PendingShare.fromMap({
      'paths': paths,
      'drop': true,
      'stage': '/tmp/share-stage',
    });
    paths.clear();
    expect(share.paths, ['/tmp/shared.txt']);
    expect(share.hasFiles, isTrue);
    expect(share.drop, isTrue);
    expect(share.stage, '/tmp/share-stage');
    expect(() => share.paths!.add('/tmp/other'), throwsUnsupportedError);

    final text = PendingShare.fromMap({'text': 'hello', 'typed': true});
    expect(text.text, 'hello');
    expect(text.typed, isTrue);
    expect(text.hasFiles, isFalse);
    expect(
      PendingShare.fromMap({
        'uris': ['content://media/1'],
      }).uris,
      ['content://media/1'],
    );
    expect(
      PendingShare.fromMap({'uri': 'content://media/1'}).uri,
      'content://media/1',
    );
  });

  test('keeps the cleanup stage for macOS text and URL shares', () {
    for (final text in ['shared text', 'https://example.com']) {
      final share = PendingShare.fromMap({
        'text': text,
        'stage': 'share-stage',
      });
      expect(share.text, text);
      expect(share.stage, 'share-stage');
      expect(share.hasFiles, isFalse);
    }
  });

  test('rejects malformed fields and conflicting content sources', () {
    final invalid = <Map<String, dynamic>>[
      {},
      {'paths': '["/tmp/file"]'},
      {'paths': <String>[]},
      {
        'paths': [''],
      },
      {
        'paths': [1],
      },
      {'uris': List.filled(101, 'content://media/1')},
      {'text': 123},
      {'text': 'hello', 'typed': 'true'},
      {'text': 'hello', 'drop': true},
      {
        'paths': ['/tmp/file'],
        'typed': true,
      },
      {
        'paths': ['/tmp/file'],
        'text': 'hello',
      },
      {'uri': ''},
      {
        'uri': 'content://media/1',
        'uris': ['content://media/2'],
      },
    ];
    for (final value in invalid) {
      expect(
        () => PendingShare.fromMap(value),
        throwsFormatException,
        reason: '$value',
      );
    }
    expect(
      () => PendingShare(paths: ['/tmp/file'], text: 'hello'),
      throwsFormatException,
    );
  });
}
