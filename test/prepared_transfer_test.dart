import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela/prepared_transfer.dart';

void main() {
  test(
    'cleanup removes owned files and keeps user files across retries',
    () async {
      final directory = await Directory.systemTemp.createTemp('vela-transfer-');
      addTearDown(() => directory.delete(recursive: true));
      final userFile = await File('${directory.path}/user.txt')
          .writeAsString('user');
      final temporary = await File('${directory.path}/snapshot.txt')
          .writeAsString('snapshot');
      final paths = [userFile.path, temporary.path];
      final transfer = PreparedTransfer(
        paths: paths,
        ownedPaths: [temporary.path, temporary.path],
      );
      paths.clear();
      expect(transfer.paths, [userFile.path, temporary.path]);
      expect(transfer.ownedPaths, [temporary.path]);
      expect(() => transfer.paths.clear(), throwsUnsupportedError);

      await transfer.cleanup();
      await transfer.cleanup();
      expect(await userFile.readAsString(), 'user');
      expect(await temporary.exists(), isFalse);
    },
  );

  test('rejects missing paths and oversized transfers', () {
    expect(() => PreparedTransfer(paths: []), throwsFormatException);
    expect(
      () => PreparedTransfer(paths: List.filled(101, '/tmp/file')),
      throwsFormatException,
    );
    expect(() => PreparedTransfer(paths: ['']), throwsFormatException);
  });

  test(
    'cleanup reports IO failures instead of losing cleanup ownership',
    () async {
      final directory = await Directory.systemTemp.createTemp('vela-transfer-');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('${directory.path}/source.txt')
          .writeAsString('source');
      final transfer = PreparedTransfer(
        paths: [file.path],
        ownedPaths: [directory.path],
      );
      await expectLater(
        transfer.cleanup(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.exists(), isTrue);
    },
  );
}
