import 'dart:convert';
import 'dart:io';
import 'dart:math';

Uri serveMacUpdateFeed(
  HttpServer server,
  File archive, {
  required String version,
  required int build,
  required String? edSignature,
  required int size,
}) {
  final random = Random.secure();
  final nonce = List<int>.generate(
    32,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  final base = 'http://127.0.0.1:${server.port}/$nonce';
  final xml = '''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Vela</title><item><title>Vela $version</title><enclosure url="$base/payload.zip" sparkle:version="$build" sparkle:shortVersionString="$version" sparkle:edSignature="$edSignature" length="$size" type="application/octet-stream" /></item></channel></rss>''';
  server.listen((request) async {
    try {
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      } else if (request.uri.path == '/$nonce/appcast.xml') {
        final bytes = utf8.encode(xml);
        request.response.headers.contentType = ContentType(
          'application',
          'xml',
          charset: 'utf-8',
        );
        request.response.contentLength = bytes.length;
        if (request.method == 'GET') request.response.add(bytes);
      } else if (request.uri.path == '/$nonce/payload.zip') {
        request.response.headers.contentType = ContentType(
          'application',
          'zip',
        );
        request.response.contentLength = size;
        if (request.method == 'GET') {
          await request.response.addStream(archive.openRead());
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    } catch (_) {
      request.response
          .detachSocket()
          .then((socket) => socket.destroy())
          .catchError((_) {});
    }
  });
  return Uri.parse('$base/appcast.xml');
}
