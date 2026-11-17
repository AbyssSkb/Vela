// Debug-only, two-process test of the real Flutter-to-Rust transfer boundary.
import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'src/rust/api/node.dart';

Future<void> runPeerTest(String role, String runId) async {
  final base = await getApplicationSupportDirectory();
  final root = await Directory('${base.path}/tests/$runId')
      .create(recursive: true);
  final node = await startNode(secret: await generateSecret());
  try {
    await node.waitUntilOnline().timeout(const Duration(seconds: 60));
    await File('${root.path}/$role.id').writeAsString(node.id(), flush: true);
    final other = role == 'a' ? 'b' : 'a';
    final idFile = File('${root.path}/$other.id');
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (!await idFile.exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('other instance did not start');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final peer = (await idFile.readAsString()).trim();
    await node.replaceTrustedPeers(trusted: [peer]);
    await File('${root.path}/$role.ready').writeAsString('ready');
    final otherReady = File('${root.path}/$other.ready');
    while (!await otherReady.exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('other instance did not pair');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final dest = await Directory('${root.path}/$role-received')
        .create(recursive: true);
    for (final kind in ['file', 'text', 'image', 'clipboard_file']) {
      Future<void> send() async {
        final file = File('${root.path}/$role-$kind.bin');
        await file.writeAsString('vela $role $kind', flush: true);
        await node
            .newTransferJob()
            .sendFile(peerId: peer, path: file.path, kind: kind)
            .timeout(const Duration(seconds: 60));
        stdout.writeln('sent $kind');
      }

      Future<void> receive() async {
        final offer = await node.nextRequest().timeout(
          const Duration(seconds: 60),
        );
        final info = offer.info();
        if (info.sender != peer || info.kind != kind) {
          throw StateError('unexpected offer');
        }
        final path = await offer
            .receiveFile(directory: dest.path, job: node.newTransferJob())
            .timeout(const Duration(seconds: 60));
        if (await File(path).readAsString() != 'vela $other $kind') {
          throw StateError('content mismatch');
        }
        stdout.writeln('received $kind');
      }

      if (role == 'a') {
        await send();
        await receive();
      } else {
        await receive();
        await send();
      }
    }
    stdout.writeln('PEER_TEST_OK $role');
  } finally {
    await node.close();
  }
}
