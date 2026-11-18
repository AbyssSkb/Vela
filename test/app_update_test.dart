import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela/app_update.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vela/update-test');
  const repository = 'AbyssSkb/Vela';
  const assetUrl =
      'https://github.com/AbyssSkb/Vela/releases/download/v1.1.0/Vela-linux-x64.AppImage';
  final bytes = utf8.encode('verified update fixture');
  late SimpleKeyPair keyPair;
  late String publicKey;

  Future<List<int>> envelope(Map<String, dynamic> payload) async {
    final encoded = utf8.encode(jsonEncode(payload));
    final signature = await Ed25519().sign(encoded, keyPair: keyPair);
    return utf8.encode(
      jsonEncode({
        'payload': base64Encode(encoded),
        'signature': base64Encode(signature.bytes),
      }),
    );
  }

  Map<String, dynamic> payload({
    String version = '1.1.0',
    int build = 6,
    String platform = 'linux',
    String arch = 'x64',
    String url = assetUrl,
    String? sha256,
    int? size,
  }) => {
    'version': version,
    'build': build,
    'platform': platform,
    'arch': arch,
    'url': url,
    'sha256': sha256 ?? crypto.sha256.convert(bytes).toString(),
    'size': size ?? bytes.length,
  };

  Future<AppUpdateManifest> verify(List<int> data) => AppUpdateManifest.verify(
    data,
    publicKey: publicKey,
    platform: 'linux',
    arch: 'x64',
    repository: repository,
  );

  Future<dynamic> nativeCall(String method, [Object? arguments]) {
    const codec = StandardMethodCodec();
    final result = Completer<dynamic>();
    ServicesBinding.instance.channelBuffers.push(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (ByteData? reply) {
        try {
          result.complete(codec.decodeEnvelope(reply!));
        } catch (error, stack) {
          result.completeError(error, stack);
        }
      },
    );
    return result.future;
  }

  setUpAll(() async {
    keyPair = await Ed25519().newKeyPairFromSeed(
      List<int>.generate(32, (i) => i),
    );
    publicKey = base64Encode((await keyPair.extractPublicKey()).bytes);
  });

  test(
    'signed metadata validates platform, URL and monotonic versions',
    () async {
      final manifest = await verify(await envelope(payload()));
      expect(manifest.newerThan('1.0.0', 5), isTrue);
      expect(manifest.newerThan('1.1.0', 6), isFalse);
      expect(manifest.newerThan('1.2.0', 5), isFalse);
      expect(manifest.newerThan('1.0.0', 7), isFalse);
      final prerelease = await verify(
        await envelope(payload(version: '1.1.0-beta.2', build: 7)),
      );
      expect(prerelease.newerThan('1.1.0-beta.1', 6), isTrue);
      expect(prerelease.newerThan('1.1.0', 6), isFalse);
    },
  );

  test('modified signed payload is rejected before trusting fields', () async {
    final original = jsonDecode(utf8.decode(await envelope(payload()))) as Map;
    original['payload'] = base64Encode(
      utf8.encode(jsonEncode(payload(version: '9.0.0'))),
    );
    await expectLater(
      verify(utf8.encode(jsonEncode(original))),
      throwsFormatException,
    );
  });

  test('even signed metadata cannot target another platform or URL', () async {
    for (final invalid in [
      payload(platform: 'windows'),
      payload(arch: 'arm64'),
      payload(
        url: 'http://github.com/AbyssSkb/Vela/releases/download/v1/a.AppImage',
      ),
      payload(url: 'https://example.com/a.AppImage'),
      payload(
        url: 'https://github.com/another/project/releases/download/v1/a.AppImage',
      ),
      payload(url: '$assetUrl?redirect=elsewhere'),
      payload(url: '$assetUrl.exe'),
      payload(size: 1024 * 1024 * 1024 + 1),
      payload(sha256: 'invalid'),
    ]) {
      await expectLater(verify(await envelope(invalid)), throwsFormatException);
    }
  });

  test(
    'macOS metadata requires a correctly encoded Sparkle archive signature',
    () async {
      for (final signature in [null, 'AA==']) {
        final metadata = {
          ...payload(
            platform: 'macos',
            arch: 'arm64',
            url: 'https://github.com/AbyssSkb/Vela/releases/download/v1.1.0/Vela-macos-arm64.zip',
          ),
          'edSignature': signature,
        };
        await expectLater(
          AppUpdateManifest.verify(
            await envelope(metadata),
            publicKey: publicKey,
            platform: 'macos',
            arch: 'arm64',
            repository: repository,
          ),
          throwsFormatException,
        );
      }
    },
  );

  group('download and installation', () {
    late Directory cache;
    late List<MethodCall> calls;
    late AppUpdateController controller;
    late List<int> signed;
    late List<int> downloaded;
    late int requests;

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('vela-update-test-');
      calls = [];
      requests = 0;
      signed = await envelope(payload());
      downloaded = bytes;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'getUpdateDirectory') return cache.path;
            return null;
          });
      controller = AppUpdateController(
        platform: 'linux',
        arch: 'x64',
        version: '1.0.0',
        build: 5,
        publicKey: publicKey,
        channel: channel,
        readUrl: (url) {
          requests++;
          return Stream.value(url.path.endsWith('.json') ? signed : downloaded);
        },
      );
    });

    tearDown(() async {
      controller.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await cache.delete(recursive: true);
    });

    test(
      'downloads automatically but installation waits for an idle app',
      () async {
        await controller.start();
        expect(controller.state, AppUpdateState.ready);
        expect(requests, 2);
        expect(controller.busy, isTrue);
        await expectLater(controller.install(), throwsStateError);
        expect(calls.where((c) => c.method == 'installDownloaded'), isEmpty);
        await controller.setBusy(false);
        await controller.install();
        final installed = calls.singleWhere(
          (c) => c.method == 'installDownloaded',
        );
        final args = installed.arguments as Map;
        expect(args['sha256'], crypto.sha256.convert(bytes).toString());
        expect(await File(args['path'] as String).readAsBytes(), bytes);
      },
    );

    test(
      'tampered download is rejected and partial content is removed',
      () async {
        downloaded = List<int>.filled(bytes.length, 0);
        await controller.start();
        expect(controller.state, AppUpdateState.error);
        expect(controller.errorCode, 'verification_failed');
        expect(await cache.list().toList(), isEmpty);
        expect(calls.where((c) => c.method == 'installDownloaded'), isEmpty);
      },
    );

    test(
      'oversized download is rejected before it can fill the cache',
      () async {
        downloaded = List<int>.filled(bytes.length + 1, 0);
        await controller.start();
        expect(controller.state, AppUpdateState.error);
        expect(await cache.list().toList(), isEmpty);
      },
    );

    test(
      'cached update is checked again immediately before installing',
      () async {
        await controller.start();
        await controller.setBusy(false);
        final file = (await cache.list().toList()).single as File;
        await file.writeAsString('replaced after download');
        await controller.install();
        expect(controller.state, AppUpdateState.error);
        expect(controller.errorCode, 'verification_failed');
        expect(calls.where((c) => c.method == 'installDownloaded'), isEmpty);
      },
    );

    test(
      'abandoned staging directories are reclaimed before downloading',
      () async {
        final stage = await Directory('${cache.path}/download-abandoned')
            .create();
        await File('${stage.path}/.lock').writeAsString('');
        await File('${stage.path}/payload').writeAsBytes(bytes);
        await controller.start();
        expect(controller.state, AppUpdateState.ready);
        expect(await stage.exists(), isFalse);
        expect(await cache.list().toList(), hasLength(1));
      },
    );

    test('missing release key leaves development builds offline', () async {
      controller.dispose();
      controller = AppUpdateController(
        platform: 'linux',
        arch: 'x64',
        version: '1.0.0',
        build: 5,
        publicKey: '',
        channel: channel,
        readUrl: (_) {
          requests++;
          throw StateError('Must not request updates');
        },
      );
      await controller.start();
      expect(controller.state, AppUpdateState.disabled);
      expect(requests, 0);
    });

    test('macOS waits for consent and drains the app before install', () async {
      controller.dispose();
      var prepared = 0;
      final archiveSignature = await Ed25519().sign(bytes, keyPair: keyPair);
      signed = await envelope({
        ...payload(
          platform: 'macos',
          arch: 'arm64',
          url: 'https://github.com/AbyssSkb/Vela/releases/download/v1.1.0/Vela-macos-arm64.zip',
        ),
        'edSignature': base64Encode(archiveSignature.bytes),
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'getUpdateDirectory') return cache.path;
            if (call.method == 'installDownloaded') {
              expect(controller.installing, isTrue);
              expect(await nativeCall('prepareInstall'), isTrue);
              final args = call.arguments as Map;
              final feed = Uri.parse(args['feedUrl'] as String);
              expect(args['publicKey'], publicKey);
              expect(feed.scheme, 'http');
              expect(feed.host, '127.0.0.1');
              expect(
                feed.path,
                matches(RegExp(r'^/[a-f0-9]{64}/appcast\.xml$')),
              );
              final client = _LoopbackHttpOverrides().createHttpClient(null);
              try {
                final response = await (await client.getUrl(feed)).close();
                expect(response.statusCode, HttpStatus.ok);
                final xml = await response.transform(utf8.decoder).join();
                expect(xml, contains('sparkle:version="6"'));
                expect(
                  xml,
                  contains(
                    'sparkle:edSignature="${base64Encode(archiveSignature.bytes)}"',
                  ),
                );
                final asset = feed.replace(
                  path: feed.path.replaceFirst('appcast.xml', 'payload.zip'),
                );
                final content = await (await client.getUrl(asset)).close();
                expect(
                  await content.fold<List<int>>(
                    [],
                    (buffer, chunk) => buffer..addAll(chunk),
                  ),
                  bytes,
                );
                final denied = await (await client.getUrl(
                  feed.replace(path: '/appcast.xml'),
                )).close();
                expect(denied.statusCode, HttpStatus.notFound);
                await denied.drain<void>();
                final readOnly = await (await client.postUrl(feed)).close();
                expect(readOnly.statusCode, HttpStatus.methodNotAllowed);
                await readOnly.drain<void>();
              } finally {
                client.close(force: true);
              }
            }
            return null;
          });
      controller = AppUpdateController(
        platform: 'macos',
        arch: 'arm64',
        version: '1.0.0',
        build: 5,
        publicKey: publicKey,
        channel: channel,
        readUrl: (url) =>
            Stream.value(url.path.endsWith('.json') ? signed : bytes),
        prepareInstall: () async {
          prepared++;
        },
      );
      await controller.start();
      expect(controller.state, AppUpdateState.ready);
      expect(prepared, 0);
      expect(
        calls.where((call) => call.method == 'installDownloaded'),
        isEmpty,
      );
      expect(await nativeCall('prepareInstall'), isFalse);
      await controller.setBusy(false);
      expect(await nativeCall('prepareInstall'), isFalse);
      await controller.install();
      expect(prepared, 1);
      expect(controller.state, AppUpdateState.installing);
      expect(
        calls.where((call) => call.method == 'installDownloaded'),
        hasLength(1),
      );
    });

    test('install distinguishes a busy app from a failed shutdown', () async {
      Object failure = PlatformException(code: 'busy');
      controller.dispose();
      controller = AppUpdateController(
        platform: 'linux',
        arch: 'x64',
        version: '1.0.0',
        build: 5,
        publicKey: publicKey,
        channel: channel,
        readUrl: (url) =>
            Stream.value(url.path.endsWith('.json') ? signed : bytes),
        prepareInstall: () async => throw failure,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getUpdateDirectory') return cache.path;
            if (call.method == 'installDownloaded' &&
                await nativeCall('prepareInstall') != true) {
              throw PlatformException(code: 'update_failed');
            }
            return null;
          });
      await controller.start();
      await controller.setBusy(false);
      await controller.install();
      expect(controller.errorCode, 'busy');
      expect(controller.canInstall, isTrue);

      failure = StateError('could not close node');
      await controller.install();
      expect(controller.errorCode, 'update_failed');
      expect(controller.canInstall, isTrue);
    });

    test('failed macOS handoff closes the temporary local feed', () async {
      controller.dispose();
      Uri? feed;
      final archiveSignature = await Ed25519().sign(bytes, keyPair: keyPair);
      signed = await envelope({
        ...payload(
          platform: 'macos',
          arch: 'arm64',
          url: 'https://github.com/AbyssSkb/Vela/releases/download/v1.1.0/Vela-macos-arm64.zip',
        ),
        'edSignature': base64Encode(archiveSignature.bytes),
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getUpdateDirectory') return cache.path;
            if (call.method == 'installDownloaded') {
              feed = Uri.parse((call.arguments as Map)['feedUrl'] as String);
              throw PlatformException(code: 'update_failed');
            }
            return null;
          });
      controller = AppUpdateController(
        platform: 'macos',
        arch: 'arm64',
        version: '1.0.0',
        build: 5,
        publicKey: publicKey,
        channel: channel,
        readUrl: (url) =>
            Stream.value(url.path.endsWith('.json') ? signed : bytes),
      );
      await controller.start();
      await controller.setBusy(false);
      await controller.install();
      expect(controller.state, AppUpdateState.ready);
      final client = _LoopbackHttpOverrides().createHttpClient(null)
        ..connectionTimeout = const Duration(seconds: 1);
      try {
        await expectLater(
          client.getUrl(feed!),
          throwsA(isA<SocketException>()),
        );
      } finally {
        client.close(force: true);
      }
    });

    testWidgets('ready updates require explicit confirmation', (tester) async {
      await tester.runAsync(controller.start);
      await controller.setBusy(false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppUpdateTile(controller: controller)),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('app-update')));
      await tester.pumpAndSettle();
      expect(find.text('Install update?'), findsOneWidget);
      expect(calls.where((c) => c.method == 'installDownloaded'), isEmpty);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'installDownloaded'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an incoming transfer while confirming prevents installation', (
      tester,
    ) async {
      await tester.runAsync(controller.start);
      await controller.setBusy(false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppUpdateTile(controller: controller)),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('app-update')));
      await tester.pumpAndSettle();
      await controller.setBusy(true);
      await tester.tap(find.text('Install'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        calls.where((call) => call.method == 'installDownloaded'),
        isEmpty,
      );
      expect(
        find.text('Finish the current transfer or pairing first'),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

// Widget tests replace HttpClient; these two checks exercise a real loopback server.
class _LoopbackHttpOverrides extends HttpOverrides {}
