import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import 'clipboard_content.dart';
import 'content_kind.dart';
import 'desktop_platform.dart';
import 'received_storage.dart';
import 'transfer_history.dart';
import 'transfer_history_store.dart';

typedef ReceivedContent = ({
  String? text,
  String? link,
  bool clipboardFailed,
  bool historySaved,
});

Future<ReceivedContent> copyAndRecordReceivedContent({
  required List<SavedReceivedFile> files,
  required TransferKind kind,
  required String offeredName,
  required String contentName,
  required String Function() senderName,
  required TransferHistoryStore history,
}) async {
  const clipboardChannel = MethodChannel('vela/clipboard');
  String? text;
  String? preview;
  String? link;
  var clipboardFailed = false;
  if (kind.isText) {
    text = await File(files.first.reference).readAsString();
    preview = String.fromCharCodes(text.trim().runes.take(120));
    link = detectHttpLink(text);
    if (kind.copiesTextToClipboard) {
      if (Platform.isAndroid) {
        await clipboardChannel.invokeMethod<void>('writeText', {'text': text});
      } else {
        await Clipboard.setData(ClipboardData(text: text));
      }
    }
  } else {
    try {
      if (kind == TransferKind.image) {
        await DesktopPlatform.writeClipboardImage(
          await File(files.first.reference).readAsBytes(),
        );
      } else {
        final references = files.map((file) => file.reference).toList();
        if (Platform.isAndroid) {
          await clipboardChannel.invokeMethod<void>('writeFiles', {
            'paths': references,
          });
        } else if (!await Pasteboard.writeFiles(references)) {
          throw StateError('Clipboard rejected received files');
        }
      }
    } catch (error) {
      clipboardFailed = true;
      debugPrint('Could not copy received content: $error');
    }
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
        ),
      );
    }
  } catch (error) {
    historySaved = false;
    debugPrint('Could not save history: $error');
  }
  return (
    text: text,
    link: link,
    clipboardFailed: clipboardFailed,
    historySaved: historySaved,
  );
}
