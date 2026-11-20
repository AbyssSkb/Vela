import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'content_kind.dart';
import 'l10n/generated/app_localizations.dart';
import 'notice.dart';
import 'page_layout.dart';
import 'received_storage.dart';

export 'content_kind.dart' show HistoryKind;

class TransferRecord {
  const TransferRecord({
    required this.name,
    required this.peer,
    required this.time,
    required this.kind,
    required this.received,
    this.fileReference,
    this.size,
    this.preview,
    this.batchId,
  });
  final String name, peer;
  final HistoryKind kind;
  final DateTime time;
  final bool received;
  final String? fileReference, preview;
  final String? batchId;
  final int? size;

  Map<String, Object?> toJson() => {
    'name': name,
    'peer': peer,
    'time': time.toIso8601String(),
    'kind': kind.storageName,
    'received': received,
    'path': fileReference,
    'size': size,
    'preview': preview,
    if (batchId != null) 'batchId': batchId,
  };
  static List<TransferRecord> decode(String? raw) {
    if (raw == null) return [];
    try {
      final records = <TransferRecord>[];
      for (final value in jsonDecode(raw) as List) {
        try {
          final item = value as Map;
          records.add(
            TransferRecord(
              name: item['name'] as String,
              peer: item['peer'] as String,
              time: DateTime.parse(item['time'] as String),
              kind: HistoryKind.fromStorage(item['kind'] as String),
              received: item['received'] as bool,
              fileReference: item['path'] as String?,
              size: item['size'] as int?,
              preview: item['preview'] as String?,
              batchId: item['batchId'] as String?,
            ),
          );
        } catch (_) {
          continue;
        }
      }
      return records;
    } catch (_) {
      return [];
    }
  }
}

Future<({List<TransferRecord> removed, bool failed})>
deleteFilesAndSelectRemovableRecords(
  Iterable<TransferRecord> records, {
  required bool deleteFiles,
  Future<void> Function(String)? deleteFile,
}) async {
  final removed = <TransferRecord>[];
  var failed = false;
  for (final item in records) {
    if (deleteFiles && item.fileReference != null) {
      try {
        await (deleteFile ?? const ReceivedStorage().delete)(
          item.fileReference!,
        );
      } on PathNotFoundException {
        /* The file is already gone. */
      } catch (e) {
        failed = true;
        debugPrint('Could not delete received file: $e');
        continue;
      }
    }
    removed.add(item);
  }
  return (removed: removed, failed: failed);
}

class TransferHistoryPage extends StatefulWidget {
  const TransferHistoryPage({
    super.key,
    required this.records,
    required this.open,
    required this.export,
    required this.openFolder,
    required this.reveal,
    required this.remove,
    this.copyFiles,
    this.batchId,
  });
  final ValueListenable<List<TransferRecord>> records;
  final String? batchId;
  final Future<void> Function(TransferRecord) open, export;
  final Future<void> Function() openFolder;
  final Future<void> Function(TransferRecord) reveal;
  final Future<void> Function(List<TransferRecord>)? copyFiles;
  final Future<void> Function(
    Iterable<TransferRecord>, {
    required bool deleteFiles,
  })
  remove;
  @override
  State<TransferHistoryPage> createState() => _TransferHistoryPageState();
}

class _TransferHistoryPageState extends State<TransferHistoryPage> {
  final searchController = TextEditingController();
  final searchFocus = FocusNode();
  bool searching = false, selecting = false;
  String query = '';
  final Set<TransferRecord> selected = {};

  bool _inScope(TransferRecord item) =>
      item.received &&
      (widget.batchId == null || item.batchId == widget.batchId);
  @override
  void dispose() {
    searchController.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  bool _matches(TransferRecord item) =>
      query.isEmpty ||
      '${item.name} ${item.peer} ${item.preview ?? ''}'.toLowerCase().contains(
        query,
      );

  void _toggleSelection(TransferRecord item) {
    setState(() {
      selecting = true;
      if (!selected.add(item)) selected.remove(item);
    });
  }

  void _closeSelection() => setState(() {
    selecting = false;
    selected.clear();
  });

  void _startSearch() {
    if (selecting || !widget.records.value.any(_inScope)) return;
    setState(() => searching = true);
    searchFocus.requestFocus();
  }

  void _clearSearch() => setState(() {
    searchController.clear();
    query = '';
  });

  void _closeSearch() => setState(() {
    searching = false;
    searchController.clear();
    query = '';
  });

  Future<void> _confirmRemove(Iterable<TransferRecord> records) async {
    final t = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final items = records.toList();
    if (items.isEmpty) return;
    var deleteFiles = false;
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(t.removeRecordsQuestion(items.length)),
          content: items.any((item) => item.fileReference != null)
              ? CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(t.removeRecordsAndFiles),
                  subtitle: Text(t.deleteFilesWarning),
                  value: deleteFiles,
                  onChanged: (value) =>
                      setDialogState(() => deleteFiles = value ?? false),
                )
              : null,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, deleteFiles),
              style: deleteFiles
                  ? FilledButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                    )
                  : null,
              child: Text(
                deleteFiles ? t.removeRecordAndFile : t.removeRecordsOnly,
              ),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      await widget.remove(items, deleteFiles: choice);
      if (mounted) _closeSelection();
    } catch (e) {
      if (mounted) {
        setState(
          () => selected.removeWhere(
            (item) => !widget.records.value.contains(item),
          ),
        );
        showNotice(
          context,
          e is StateError ? e.message.toString() : t.storageFailed,
          kind: NoticeKind.error,
        );
      }
    }
  }

  IconData _icon(TransferRecord record) {
    if (record.kind.isText) {
      return Icons.subject_rounded;
    }
    if (record.kind == HistoryKind.image) return Icons.image_outlined;
    final extension = record.name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(extension)) {
      return Icons.image_outlined;
    }
    if (['mp4', 'mov', 'mkv', 'webm'].contains(extension)) {
      return Icons.movie_outlined;
    }
    if (['mp3', 'm4a', 'flac', 'wav', 'ogg'].contains(extension)) {
      return Icons.music_note_rounded;
    }
    if (extension == 'apk') return Icons.android_rounded;
    return Icons.insert_drive_file_outlined;
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final units = ['KB', 'MB', 'GB', 'TB'];
    double value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
  }

  void _showDetails(TransferRecord item) {
    final t = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final details = <(String, String)>[
      (t.recordName, item.name),
      if (item.size != null) (t.fileSizeLabel, _size(item.size!)),
      (t.recordDevice, item.peer),
      (
        t.recordTime,
        DateFormat.yMMMd(locale).add_Hm().format(item.time.toLocal()),
      ),
    ];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.recordDetails),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (label, value) in details)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          value,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
        ],
      ),
    );
  }

  static const receivedStorage = ReceivedStorage();

  bool _canCopy(TransferRecord record) =>
      widget.copyFiles != null &&
      record.kind.isFile &&
      record.fileReference != null;

  Future<void> _copyFiles(Iterable<TransferRecord> records) async {
    final t = AppLocalizations.of(context)!;
    try {
      await widget.copyFiles!(records.where(_canCopy).toList());
      if (mounted)
        showNotice(context, t.historyCopied, kind: NoticeKind.success);
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          e is StateError ? e.message.toString() : t.historyCopyFailed,
          kind: NoticeKind.error,
        );
      }
    }
  }

  Future<void> _openFolder() async {
    final t = AppLocalizations.of(context)!;
    try {
      await widget.openFolder();
    } catch (_) {
      if (mounted) showNotice(context, t.storageFailed, kind: NoticeKind.error);
    }
  }

  Widget _buildToolbar(BuildContext context, List<TransferRecord> records) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final visibleRecords = records.where(_inScope);
    final matches = visibleRecords.where(_matches);
    final batch = widget.batchId != null;
    final copyBatch = batch && visibleRecords.any(_canCopy);
    final showClear = !searching && !batch && visibleRecords.isNotEmpty;
    final batchSenders = batch
        ? visibleRecords.map((item) => item.peer).toSet()
        : const <String>{};
    final title = selecting
        ? t.selectedCount(selected.length)
        : batch
        ? t.receivedBatch
        : t.transferHistory;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        theme.platform == TargetPlatform.macOS ? 38 : 8,
        12,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: selecting
                    ? _closeSelection
                    : searching
                    ? _closeSearch
                    : () => Navigator.pop(context),
                tooltip: selecting
                    ? t.cancel
                    : searching
                    ? t.close
                    : MaterialLocalizations.of(context).backButtonTooltip,
                icon: Icon(
                  selecting || searching
                      ? Icons.close_rounded
                      : Icons.arrow_back_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: searching && !selecting
                    ? TextField(
                        controller: searchController,
                        focusNode: searchFocus,
                        onChanged: (value) =>
                            setState(() => query = value.trim().toLowerCase()),
                        decoration: InputDecoration(
                          hintText: t.searchHistory,
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      )
                    : Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              if (selecting) ...[
                IconButton(
                  tooltip: t.selectAll,
                  onPressed: matches.isEmpty
                      ? null
                      : () => setState(() => selected.addAll(matches)),
                  icon: const Icon(Icons.select_all_rounded),
                ),
                if (selected.any(_canCopy))
                  IconButton(
                    tooltip: t.historyCopyFiles,
                    onPressed: () => _copyFiles(selected),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                IconButton(
                  tooltip: t.removeRecord,
                  onPressed: selected.isEmpty
                      ? null
                      : () => _confirmRemove(selected),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ] else if (!searching) ...[
                if (copyBatch)
                  IconButton(
                    tooltip: t.historyCopyFiles,
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () => _copyFiles(visibleRecords),
                  )
                else if (receivedStorage.supportsReceiveLocation)
                  IconButton(
                    tooltip: t.openReceiveFolder,
                    icon: const Icon(Icons.folder_open_rounded),
                    onPressed: _openFolder,
                  ),
                if (visibleRecords.isNotEmpty)
                  IconButton(
                    tooltip: t.searchHistory,
                    icon: const Icon(Icons.search_rounded),
                    onPressed: _startSearch,
                  ),
              ],
              if (!selecting && (showClear || matches.isNotEmpty))
                PopupMenuButton<String>(
                  key: const ValueKey('history-actions'),
                  tooltip: t.manageRecords,
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (action) {
                    if (action == 'select') {
                      setState(() => selecting = true);
                    } else if (action == 'folder') {
                      _openFolder();
                    } else {
                      _confirmRemove(visibleRecords);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'select',
                      child: Text(t.selectRecords),
                    ),
                    if (copyBatch &&
                        !searching &&
                        receivedStorage.supportsReceiveLocation)
                      PopupMenuItem(
                        value: 'folder',
                        child: Text(t.openReceiveFolder),
                      ),
                    if (showClear)
                      PopupMenuItem(
                        value: 'clear',
                        child: Text(t.clearHistory),
                      ),
                  ],
                ),
            ],
          ),
          if (batch && visibleRecords.isNotEmpty && !selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                [
                  t.filesCount(visibleRecords.length),
                  if (batchSenders.length == 1)
                    t.historyReceivedFrom(batchSenders.single),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _recordAction(
    String action,
    IconData icon,
    String label,
  ) => PopupMenuItem(
    value: action,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    String dateLabel(DateTime date) {
      final day = DateTime(date.year, date.month, date.day);
      final today = DateTime(now.year, now.month, now.day);
      if (day == today) return t.today;
      if (day == today.subtract(const Duration(days: 1))) return t.yesterday;
      return DateFormat.yMMMd(locale).format(date);
    }

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    return PopScope(
      canPop: !selecting && !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) {
          _closeSelection();
        } else if (searching) {
          _closeSearch();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _startSearch,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _startSearch,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: PageLayout(
              maxWidth: 640,
              header: ValueListenableBuilder<List<TransferRecord>>(
                valueListenable: widget.records,
                builder: (context, records, _) =>
                    _buildToolbar(context, records),
              ),
              body: ValueListenableBuilder<List<TransferRecord>>(
                valueListenable: widget.records,
                builder: (context, allItems, _) {
                  final received = allItems.where(_inScope).toList();
                  if (received.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.batchId == null
                              ? t.noTransferHistory
                              : t.receivedBatchUnavailable,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                    );
                  }
                  final items = received.where(_matches).toList();
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              t.noHistoryMatches,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                            TextButton(
                              onPressed: _clearSearch,
                              child: Text(t.clearSearch),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final date = item.time.toLocal();
                      final firstOfDay =
                          index == 0 ||
                          !sameDay(date, items[index - 1].time.toLocal());
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (firstOfDay)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                12,
                                index == 0 ? 8 : 24,
                                12,
                                8,
                              ),
                              child: Text(
                                dateLabel(date),
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ),
                          Material(
                            color: selected.contains(item)
                                ? colors.secondaryContainer.withValues(
                                    alpha: .5,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onLongPress: () => _toggleSelection(item),
                              onTap: selecting
                                  ? () => _toggleSelection(item)
                                  : item.fileReference == null
                                  ? null
                                  : () => widget.open(item),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: colors.secondaryContainer
                                            .withValues(alpha: 0.55),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        _icon(item),
                                        size: 21,
                                        color: colors.onSecondaryContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.preview?.isNotEmpty == true
                                                ? item.preview!
                                                : item.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.peer,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: colors
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                DateFormat.Hm(locale)
                                                    .format(date),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: colors
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (selecting)
                                      Semantics(
                                        label: item.name,
                                        child: Checkbox(
                                          value: selected.contains(item),
                                          onChanged: (_) =>
                                              _toggleSelection(item),
                                        ),
                                      )
                                    else
                                      PopupMenuButton<String>(
                                        tooltip: t.moreOptions,
                                        icon: Icon(
                                          Icons.more_vert_rounded,
                                          color: colors.onSurfaceVariant,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        onSelected: (action) async {
                                          try {
                                            if (action == 'export') {
                                              await widget.export(item);
                                            } else if (action == 'copy') {
                                              await _copyFiles([item]);
                                            } else if (action == 'reveal') {
                                              await widget.reveal(item);
                                            } else if (action == 'details') {
                                              _showDetails(item);
                                            } else {
                                              await _confirmRemove([item]);
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              showNotice(
                                                context,
                                                e is StateError
                                                    ? e.message.toString()
                                                    : t.storageFailed,
                                                kind: NoticeKind.error,
                                              );
                                            }
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          if (_canCopy(item))
                                            _recordAction(
                                              'copy',
                                              Icons.copy_rounded,
                                              t.historyCopyFiles,
                                            ),
                                          if (item.fileReference != null &&
                                              item.kind.isFile &&
                                              receivedStorage
                                                  .supportsReceiveLocation)
                                            _recordAction(
                                              'reveal',
                                              Icons.folder_outlined,
                                              Platform.isMacOS
                                                  ? t.revealInFinder
                                                  : t.showInFolder,
                                            ),
                                          _recordAction(
                                            'details',
                                            Icons.info_outline_rounded,
                                            t.recordDetails,
                                          ),
                                          if (item.fileReference != null &&
                                              !item.kind.isText &&
                                              receivedStorage.supportsSaveAs)
                                            _recordAction(
                                              'export',
                                              Icons.save_alt_rounded,
                                              t.saveAs,
                                            ),
                                          _recordAction(
                                            'remove',
                                            Icons.playlist_remove_rounded,
                                            t.removeRecord,
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
