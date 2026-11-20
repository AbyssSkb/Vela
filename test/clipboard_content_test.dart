import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela/clipboard_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pasteboard = MethodChannel('pasteboard');
  const android = PlatformClipboard(platform: TargetPlatform.android);
  const linux = PlatformClipboard(platform: TargetPlatform.linux);

  tearDown(() {
    messenger.setMockMethodCallHandler(pasteboard, null);
    messenger.setMockMethodCallHandler(PlatformClipboard.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

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

  test('Android reads a clipboard image before a document URI', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    Object? platformImage = bytes;
    if (Platform.isWindows) {
      final directory = await Directory.systemTemp.createTemp(
        'vela-clipboard-',
      );
      addTearDown(() => directory.delete(recursive: true));
      platformImage = (await File(
        '${directory.path}/image',
      ).writeAsBytes(bytes)).path;
    }
    messenger.setMockMethodCallHandler(pasteboard, (call) async {
      expect(call.method, 'image');
      return platformImage;
    });
    messenger.setMockMethodCallHandler(
      PlatformClipboard.channel,
      (call) async => fail('Unexpected clipboard file lookup'),
    );
    final content = await android.read();
    expect(content.image, bytes);
    expect(content.files, isEmpty);
    expect(content.text, isNull);
  });

  test('desktop prefers files and Android falls back to text', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(pasteboard, (call) async {
      calls.add(call.method);
      return call.method == 'files' ? ['/clipboard-file'] : null;
    });
    messenger.setMockMethodCallHandler(PlatformClipboard.channel, (call) async {
      expect(call.method, 'files');
      return <String>[];
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      expect(call.method, 'Clipboard.getData');
      return {'text': 'clipboard'};
    });
    expect((await linux.read()).files, ['/clipboard-file']);
    expect(calls, ['files']);
    expect((await android.read()).text, 'clipboard');
    expect(calls, ['files', 'image']);
  });

  test(
    'writes text and files through Android and images through Linux',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(PlatformClipboard.channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      final image = Uint8List.fromList([1, 2, 3]);
      await android.writeText('clipboard');
      await android.writeFiles(['content://documents/file']);
      await linux.writeImage(image);
      expect(calls.map((call) => call.method), [
        'writeText',
        'writeFiles',
        'writeImage',
      ]);
      expect(calls.map((call) => call.arguments), [
        {'text': 'clipboard'},
        {
          'paths': ['content://documents/file'],
        },
        {'bytes': image},
      ]);
    },
  );
}
