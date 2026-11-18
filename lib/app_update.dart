import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pub_semver/pub_semver.dart';

import 'mac_update_feed.dart';

enum AppUpdateState {
  disabled,
  idle,
  checking,
  current,
  downloading,
  ready,
  installing,
  error,
}

class AppUpdateManifest {
  AppUpdateManifest._(
    this.version,
    this.build,
    this.url,
    this.sha256,
    this.size,
    this.edSignature,
  );

  final Version version;
  final int build;
  final Uri url;
  final String sha256;
  final int size;
  final String? edSignature;

  static Future<AppUpdateManifest> verify(
    List<int> envelope, {
    required String publicKey,
    required String platform,
    required String arch,
    required String repository,
  }) async {
    if (envelope.length > 64 * 1024) {
      throw const FormatException('Update manifest is too large');
    }
    final decoded = jsonDecode(utf8.decode(envelope));
    if (decoded is! Map<String, dynamic> ||
        decoded['payload'] is! String ||
        decoded['signature'] is! String) {
      throw const FormatException('Invalid update envelope');
    }
    final payload = base64Decode(decoded['payload'] as String);
    final signature = base64Decode(decoded['signature'] as String);
    final key = base64Decode(publicKey);
    if (key.length != 32 ||
        signature.length != 64 ||
        payload.length > 48 * 1024) {
      throw const FormatException('Invalid update signature');
    }
    if (!await Ed25519().verify(
      payload,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
      ),
    )) {
      throw const FormatException('Update signature verification failed');
    }
    final data = jsonDecode(utf8.decode(payload));
    if (data is! Map<String, dynamic> ||
        data['version'] is! String ||
        data['build'] is! int ||
        data['url'] is! String ||
        data['sha256'] is! String ||
        data['size'] is! int ||
        data['platform'] != platform ||
        data['arch'] != arch) {
      throw const FormatException('Update does not match this application');
    }
    final version = Version.parse(data['version'] as String);
    final build = data['build'] as int;
    final url = Uri.parse(data['url'] as String);
    final digest = data['sha256'] as String;
    final size = data['size'] as int;
    final prefix = '/$repository/releases/download/';
    final suffix = switch (platform) {
      'android' => '.apk',
      'linux' => '.AppImage',
      'windows' => '.exe',
      'macos' => '.zip',
      _ => throw const FormatException('Unsupported update platform'),
    };
    if (build <= 0 ||
        build > 2147483647 ||
        size <= 0 ||
        size > 1024 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        !url.path.startsWith(prefix) ||
        url.pathSegments.length != 6 ||
        !url.path.endsWith(suffix)) {
      throw const FormatException('Invalid update metadata');
    }
    String? edSignature;
    if (platform == 'macos') {
      final value = data['edSignature'];
      if (value is! String || base64Decode(value).length != 64) {
        throw const FormatException('Missing archive signature');
      }
      edSignature = base64Encode(base64Decode(value));
    }
    return AppUpdateManifest._(version, build, url, digest, size, edSignature);
  }

  bool newerThan(String installedVersion, int installedBuild) =>
      build > installedBuild &&
      version.compareTo(Version.parse(installedVersion)) >= 0;
}

class AppUpdateController extends ChangeNotifier {
  AppUpdateController({
    String? platform,
    this.arch = const String.fromEnvironment('VELA_UPDATE_ARCH'),
    this.version = const String.fromEnvironment('VELA_VERSION'),
    this.build = const int.fromEnvironment('VELA_BUILD_NUMBER'),
    this.publicKey = const String.fromEnvironment('VELA_UPDATE_PUBLIC_KEY'),
    this.repository = const String.fromEnvironment(
      'VELA_UPDATE_REPOSITORY',
      defaultValue: 'AbyssSkb/Vela',
    ),
    this.prepareInstall,
    MethodChannel? channel,
    Stream<List<int>> Function(Uri)? readUrl,
  }) : platform = platform ?? Platform.operatingSystem,
       _channel = channel ?? const MethodChannel('vela/update'),
       _readUrl = readUrl ?? _readHttps;

  final String platform, arch, version, publicKey, repository;
  final int build;
  final Future<void> Function()? prepareInstall;
  final MethodChannel _channel;
  final Stream<List<int>> Function(Uri) _readUrl;
  AppUpdateState state = AppUpdateState.disabled;
  String? availableVersion, errorCode;
  double? progress;
  bool _busy = true, _disposed = false, _started = false;
  Timer? _timer;
  AppUpdateManifest? _manifest;
  File? _downloaded;
  HttpServer? _localServer;

  bool get busy => _busy;
  bool get installing => state == AppUpdateState.installing;
  bool get canInstall => state == AppUpdateState.ready && !_busy;
  bool get canCheck =>
      state != AppUpdateState.disabled &&
      state != AppUpdateState.checking &&
      state != AppUpdateState.downloading &&
      state != AppUpdateState.ready &&
      !installing;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    if (publicKey.isEmpty ||
        version.isEmpty ||
        build <= 0 ||
        !['android', 'linux', 'windows', 'macos'].contains(platform) ||
        !['arm64', 'x64'].contains(arch)) {
      return;
    }
    try {
      if (base64Decode(publicKey).length != 32 ||
          !RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(repository)) {
        throw const FormatException('Invalid update configuration');
      }
      Version.parse(version);
      _channel.setMethodCallHandler(_nativeCall);
      await _channel.invokeMethod<void>('setBusy', {'busy': _busy});
      if (_disposed) return;
      _setState(AppUpdateState.idle);
      _timer = Timer.periodic(const Duration(hours: 12), (_) => check());
      await check();
    } catch (_) {
      _fail('update_failed');
    }
  }

  Uri _feed(String extension) => Uri.parse(
    'https://github.com/$repository/releases/download/updates/$platform-$arch.$extension',
  );

  Future<void> setBusy(bool value) async {
    if (_busy == value || _disposed) return;
    _busy = value;
    _notify();
    if (!_started || state == AppUpdateState.disabled) return;
    try {
      await _channel.invokeMethod<void>('setBusy', {'busy': value});
    } catch (_) {
      // A missing or failed busy guard must never permit installation.
      _busy = true;
      _fail('update_failed');
    }
  }

  Future<dynamic> _nativeCall(MethodCall call) async {
    if (_disposed) return false;
    if (call.method == 'prepareInstall') {
      if (!installing || prepareInstall == null) return false;
      if (_busy) throw PlatformException(code: 'busy');
      try {
        await prepareInstall!();
        return !_disposed;
      } on PlatformException catch (error) {
        if (error.code == 'busy') rethrow;
        return false;
      } catch (_) {
        return false;
      }
    }
    if (call.method == 'updateEvent' && platform == 'macos') {
      final event = call.arguments;
      if (event is! Map) return null;
      final status = event['status'];
      final next = AppUpdateState.values
          .where((s) => s.name == status)
          .firstOrNull;
      if (next != null) {
        if (event['version'] is String) {
          availableVersion = event['version'] as String;
        }
        if (next == AppUpdateState.error || next == AppUpdateState.ready) {
          await _closeLocalFeed();
        }
        if (next == AppUpdateState.error) errorCode = 'update_failed';
        _setState(next);
      }
    }
    return null;
  }

  Future<void> check() async {
    if (!canCheck || _disposed) return;
    errorCode = null;
    _setState(AppUpdateState.checking);
    try {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in _readUrl(
        _feed('json'),
      ).timeout(const Duration(seconds: 30))) {
        if (_disposed) return;
        bytes.add(chunk);
        if (bytes.length > 64 * 1024) {
          throw const FormatException('Update manifest is too large');
        }
      }
      final manifest = await AppUpdateManifest.verify(
        bytes.takeBytes(),
        publicKey: publicKey,
        platform: platform,
        arch: arch,
        repository: repository,
      );
      if (_disposed) return;
      if (!manifest.newerThan(version, build)) {
        await _clearCache();
        _setState(AppUpdateState.current);
        return;
      }
      _manifest = manifest;
      availableVersion = manifest.version.toString();
      _setState(AppUpdateState.downloading);
      _downloaded = await _download(manifest);
      if (!_disposed) _setState(AppUpdateState.ready);
    } on FormatException {
      _fail('verification_failed');
    } catch (_) {
      _fail('update_failed');
    }
  }

  Future<Directory> _cache() async {
    final path = await _channel.invokeMethod<String>('getUpdateDirectory');
    if (path == null || path.isEmpty) throw StateError('No update cache');
    return Directory(path);
  }

  Future<void> _clearCache({String? keep}) async {
    final dir = await _cache();
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entry is Directory &&
          RegExp(r'^download-[a-zA-Z0-9]+$').hasMatch(name)) {
        await _clearStage(entry);
        continue;
      }
      final ownedFile = RegExp(r'^[a-f0-9]{64}\.(apk|AppImage|exe|zip)$')
          .hasMatch(name);
      final oldHelper =
          platform == 'windows' &&
          RegExp(r'^vela-updater-helper-[a-zA-Z0-9-]+\.exe$').hasMatch(name);
      if (entry.path != keep && (ownedFile || oldHelper)) {
        try {
          await entry.delete();
        } catch (_) {
          // A system installer may still hold the previous cache file open.
        }
      }
    }
  }

  Future<void> _clearStage(Directory stage) async {
    RandomAccessFile? lock;
    try {
      final marker = File('${stage.path}/.lock');
      if (!await marker.exists()) return;
      lock = await marker.open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      await lock.close();
      lock = null;
      await stage.delete(recursive: true);
    } catch (_) {
      // Another running instance can still be writing this staging directory.
    } finally {
      await lock?.close();
    }
  }

  Future<File> _download(AppUpdateManifest manifest) async {
    final dir = await _cache();
    await dir.create(recursive: true);
    final suffix = switch (platform) {
      'android' => 'apk',
      'windows' => 'exe',
      'macos' => 'zip',
      _ => 'AppImage',
    };
    final target = File('${dir.path}/${manifest.sha256}.$suffix');
    await _clearCache(keep: target.path);
    if (await FileSystemEntity.type(target.path, followLinks: false) ==
        FileSystemEntityType.file) {
      if (await _matches(target, manifest)) return target;
      await target.delete();
    }
    final stage = await dir.createTemp('download-');
    final stageLock = await File('${stage.path}/.lock')
        .open(mode: FileMode.write);
    await stageLock.lock(FileLock.exclusive);
    final file = File('${stage.path}/payload');
    final sink = file.openWrite();
    var received = 0;
    final elapsed = Stopwatch()..start();
    try {
      Stream<List<int>> content() async* {
        await for (final chunk in _readUrl(
          manifest.url,
        ).timeout(const Duration(seconds: 45))) {
          if (_disposed) throw StateError('Updater disposed');
          received += chunk.length;
          if (received > manifest.size || elapsed.elapsed.inMinutes >= 15) {
            throw const FormatException('Update download exceeds limits');
          }
          final next = received / manifest.size;
          if ((next * 100).floor() != ((progress ?? 0) * 100).floor()) {
            progress = next;
            _notify();
          }
          yield chunk;
        }
      }

      await sink.addStream(content());
      await sink.flush();
      await sink.close();
      if (!await _matches(file, manifest)) {
        throw const FormatException('Update content verification failed');
      }
      return await file.rename(target.path);
    } finally {
      try {
        await sink.close();
      } catch (_) {
        // addStream already reported its error; the staging files still need cleanup.
      }
      try {
        await stageLock.close();
      } finally {
        if (await stage.exists()) await stage.delete(recursive: true);
      }
    }
  }

  Future<bool> _matches(File file, AppUpdateManifest manifest) async =>
      await file.length() == manifest.size &&
      (await crypto.sha256.bind(file.openRead()).first).toString() ==
          manifest.sha256;

  Future<void> install() async {
    if (!canInstall) throw StateError('Update installation is unavailable');
    errorCode = null;
    _setState(AppUpdateState.installing);
    try {
      final manifest = _manifest;
      final file = _downloaded;
      if (manifest == null || file == null || !await _matches(file, manifest)) {
        throw const FormatException('Update changed after download');
      }
      if (_disposed) return;
      if (_busy) throw PlatformException(code: 'busy');
      final arguments = platform == 'macos'
          ? {
              'feedUrl': (await _startLocalFeed(manifest, file)).toString(),
              'publicKey': publicKey,
            }
          : {'path': file.path, 'sha256': manifest.sha256};
      await _channel.invokeMethod<void>('installDownloaded', arguments);
      if (platform == 'android') _setState(AppUpdateState.ready);
    } on FormatException {
      await _closeLocalFeed();
      _downloaded = null;
      _fail('verification_failed');
    } on PlatformException catch (error) {
      await _closeLocalFeed();
      errorCode = error.code == 'cancelled' ? null : error.code;
      _setState(AppUpdateState.ready);
    } catch (_) {
      await _closeLocalFeed();
      errorCode = 'update_failed';
      _setState(AppUpdateState.ready);
    }
  }

  Future<Uri> _startLocalFeed(AppUpdateManifest manifest, File archive) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_disposed) {
      await server.close(force: true);
      throw StateError('Updater disposed');
    }
    _localServer = server;
    return serveMacUpdateFeed(
      server,
      archive,
      version: manifest.version.toString(),
      build: manifest.build,
      edSignature: manifest.edSignature,
      size: manifest.size,
    );
  }

  Future<void> _closeLocalFeed() async {
    final server = _localServer;
    _localServer = null;
    await server?.close(force: true);
  }

  void _fail(String code) {
    errorCode = code;
    _setState(AppUpdateState.error);
  }

  void _setState(AppUpdateState value) {
    if (_disposed) return;
    state = value;
    if (value != AppUpdateState.downloading) progress = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_closeLocalFeed());
    if (_started) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

Stream<List<int>> _readHttps(Uri url) async* {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  client.autoUncompress = false;
  try {
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (url.scheme != 'https' ||
          url.port != 443 ||
          url.userInfo.isNotEmpty ||
          !(url.host == 'github.com' ||
              url.host.endsWith('.githubusercontent.com'))) {
        throw const FormatException('Invalid update redirect');
      }
      final request = await client
          .getUrl(url)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) throw const HttpException('Invalid redirect');
        url = url.resolve(location);
        await response.listen((_) {}).cancel();
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Update HTTP ${response.statusCode}');
      }
      yield* response;
      return;
    }
    throw const HttpException('Too many update redirects');
  } finally {
    client.close(force: true);
  }
}
