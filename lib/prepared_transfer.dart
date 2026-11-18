import 'dart:io';

import 'content_kind.dart';
import 'pending_share.dart';

class PreparedTransfer {
  PreparedTransfer({
    required List<String> paths,
    this.kind = TransferKind.file,
    List<String> ownedTemporaryPaths = const [],
    this.fromClipboard = false,
    this.share,
  }) : paths = List.unmodifiable(paths),
       ownedTemporaryPaths = List.unmodifiable(ownedTemporaryPaths.toSet()) {
    if (paths.isEmpty ||
        paths.length > 100 ||
        paths.any((path) => path.isEmpty) ||
        ownedTemporaryPaths.any((path) => path.isEmpty)) {
      throw const FormatException('Invalid prepared transfer');
    }
  }

  final List<String> paths, ownedTemporaryPaths;
  final TransferKind kind;
  final bool fromClipboard;
  final PendingShare? share;

  Future<void> deleteOwnedTemporaryFiles() async {
    for (final path in ownedTemporaryPaths) {
      try {
        await File(path).delete();
      } on PathNotFoundException {
        // A completed or cancelled attempt may have already removed it.
      }
    }
  }
}
