import '../lib/content_kind.dart';
import '../lib/prepared_transfer.dart';
import '../lib/send_session.dart';
import '../lib/transfer_failure.dart';

class MemoryContent extends PreparedTransfer {
  MemoryContent() : super(paths: const ['/user/original']);
  int cleanups = 0;

  @override
  Future<void> cleanup() async => cleanups++;
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  for (final kind in TransferKind.values) {
    check(
      TransferKind.fromWire(kind.wireName) == kind,
      'Transfer kind round trip',
    );
  }
  for (final kind in HistoryKind.values) {
    check(
      HistoryKind.fromStorage(kind.storageName) == kind,
      'History round trip',
    );
  }
  check(
    TransferKind.batch.historyKind('x') == HistoryKind.file,
    'Batch history',
  );
  check(
    TransferKind.file.historyKind('x$folderArchiveSuffix') ==
        HistoryKind.folderArchive,
    'Folder archive recognition',
  );
  check(
    TransferKind.text.historyKind('x$folderArchiveSuffix') == HistoryKind.text,
    'Only file transfers are folder archives',
  );
  check(
    TransferKind.text.copiesTextToClipboard &&
        !TransferKind.typedText.copiesTextToClipboard,
    'Typed text does not overwrite the clipboard',
  );
  for (final entry in {
    'cancelled': TransferFailure.cancelled,
    'declined': TransferFailure.declined,
    'save_failed': TransferFailure.saveFailed,
    'pairing_declined': TransferFailure.pairingDeclined,
  }.entries) {
    check(
      classifyTransferFailure(
            Exception('[vela:${entry.key}] changed wording'),
          ) ==
          entry.value,
      'Stable error code ${entry.key}',
    );
  }
  check(
    classifyTransferFailure(Exception('transfer declined')) ==
        TransferFailure.unknown,
    'Human-readable text is not an error code',
  );

  final content = MemoryContent();
  var sourceReleases = 0;
  final session = SendSession(
    content,
    releaseSource: () async => sourceReleases++,
  );
  final firstRetry = session.allowRetry();
  check(
    identical(firstRetry.take(), session),
    'Retry reuses the same snapshot',
  );
  final secondRetry = session.allowRetry();
  await firstRetry.dismiss();
  check(content.cleanups == 0, 'Old notice cannot release a new retry');
  check(firstRetry.take() == null, 'Retry is single use');
  await secondRetry.dismiss();
  await secondRetry.dismiss();
  await session.discard();
  check(content.cleanups == 1, 'Abandon releases the snapshot exactly once');
  check(sourceReleases == 0, 'Failed attempt keeps the pending source');

  final sent = MemoryContent();
  final completed = SendSession(
    sent,
    releaseSource: () async => sourceReleases++,
  );
  await completed.complete();
  await completed.discard();
  check(
    sourceReleases == 1 && sent.cleanups == 1,
    'Success releases both owners',
  );

  final failedRelease = MemoryContent();
  try {
    await SendSession(
      failedRelease,
      releaseSource: () async => throw StateError('Source release failed'),
    ).complete();
    throw StateError('Expected source release failure');
  } catch (error) {
    check(
      error.toString().contains('Source release failed'),
      'Failure is retained',
    );
  }
  check(
    failedRelease.cleanups == 1,
    'Source release failure still frees snapshot',
  );
  print('Core contracts passed (memory only; no files created).');
}
