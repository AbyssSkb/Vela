import 'dart:io';

import 'package:flutter/foundation.dart';

import 'clipboard_content.dart';
import 'content_kind.dart';
import 'received_storage.dart';
import 'src/rust/api/node.dart';
import 'transfer_history.dart';
import 'transfer_history_store.dart';

typedef ReceivedContent = ({
  String? text,
  String? link,
  bool clipboardFailed,
  bool historySaved,
});

Future<
  ({
    List<SavedReceivedFile> files,
    ReceivedContent content,
    bool savedPrivately,
  })?
>
receiveAcceptedContent({
  required IncomingRequest offer,
  required TransferJob job,
  required String profile,
  required TransferKind kind,
  required String offeredName,
  required String contentName,
  required String Function() senderName,
  required String? batchId,
  required TransferHistoryStore history,
  required ReceivedStorage storage,
  required bool Function() stillAuthorized,
  required void Function(bool savingFromStaging) onTransportComplete,
  required VoidCallback onSaved,
  required bool Function() isCancelled,
}) async {
  final destination = await storage.receiveDirectory(profile, kind);
  if (!stillAuthorized()) {
    await offer.decline();
    return null;
  }
  final staged = kind == TransferKind.batch
      ? await offer.receiveFiles(directory: destination.path, job: job)
      : [await offer.receiveFile(directory: destination.path, job: job)];
  final publish = Platform.isAndroid && kind.isFile;
  onTransportComplete(publish);
  final saved = await storage.finishReceive(
    staged,
    publishFromStaging: publish,
    isCancelled: isCancelled,
  );
  if (publish) onSaved();
  final content = await copyAndRecordReceivedContent(
    files: saved.files,
    kind: kind,
    offeredName: offeredName,
    contentName: contentName,
    senderName: senderName,
    batchId: batchId,
    history: history,
  );
  return (
    files: saved.files,
    content: content,
    savedPrivately: destination.privateFallback || saved.savedPrivately,
  );
}

Future<ReceivedContent> copyAndRecordReceivedContent({
  required List<SavedReceivedFile> files,
  required TransferKind kind,
  required String offeredName,
  required String contentName,
  required String Function() senderName,
  required String? batchId,
  required TransferHistoryStore history,
}) async {
  const clipboard = PlatformClipboard();
  String? text;
  String? preview;
  String? link;
  if (kind.isText) {
    text = await File(files.first.reference).readAsString();
    preview = String.fromCharCodes(text.trim().runes.take(120));
    link = detectHttpLink(text);
  }

  var historySaved = true;
  try {
    for (final file in files) {
      await history.add(
        TransferRecord(
          name: kind.isFile ? file.name : contentName,
          peer: senderName(),
          time: DateTime.now(),
          kind: kind.historyKind(offeredName),
          received: true,
          fileReference: file.reference,
          size: file.size,
          preview: preview,
          batchId: batchId,
        ),
      );
    }
  } catch (error) {
    historySaved = false;
    debugPrint('Could not save history: $error');
  }

  var clipboardFailed = false;
  try {
    if (kind == TransferKind.text) {
      await clipboard.writeText(text!);
    } else if (kind == TransferKind.image) {
      await clipboard.writeImage(
        await File(files.first.reference).readAsBytes(),
      );
    } else if (kind == TransferKind.clipboardFile) {
      await clipboard.writeFiles(files.map((file) => file.reference).toList());
    }
  } catch (error) {
    clipboardFailed = true;
    debugPrint('Could not copy received content: $error');
  }

  return (
    text: text,
    link: link,
    clipboardFailed: clipboardFailed,
    historySaved: historySaved,
  );
}
