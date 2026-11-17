import 'dart:io';

import 'content_kind.dart';
import 'pending_share.dart';

class PreparedTransfer {
  PreparedTransfer({
    required List<String> paths,
    this.kind = TransferKind.file,
    List<String> ownedPaths = const [],
    this.fromClipboard = false,
    this.share,
  }) : paths = List.unmodifiable(paths),
       ownedPaths = List.unmodifiable(ownedPaths.toSet()) {
    if (paths.isEmpty ||
        paths.length > 100 ||
        paths.any((path) => path.isEmpty) ||
        ownedPaths.any((path) => path.isEmpty)) {
      throw const FormatException('Invalid prepared transfer');
    }
  }

  final List<String> paths, ownedPaths;
  final TransferKind kind;
  final bool fromClipboard;
  final PendingShare? share;

  Future<void> cleanup() async {
    for (final path in ownedPaths) {
      try {
        await File(path).delete();
      } on PathNotFoundException {
        // A completed or cancelled attempt may have already removed it.
      }
    }
  }
}
