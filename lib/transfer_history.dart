import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'content_kind.dart';
import 'l10n/generated/app_localizations.dart';
import 'notice.dart';
import 'received_storage.dart';
import 'desktop_platform.dart';

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
  });
  final String name, peer;
  final HistoryKind kind;
  final DateTime time;
  final bool received;
  final String? fileReference, preview;
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
  });
  final ValueListenable<List<TransferRecord>> records;
  final Future<void> Function(TransferRecord) open, export;
  final Future<void> Function() openFolder;
  final Future<void> Function(TransferRecord) reveal;
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
  bool searching = false;
  String query = '';
  final Set<TransferRecord> selected = {};
  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _toggleSelection(TransferRecord item) {
    setState(() {
      if (!selected.add(item)) selected.remove(item);
    });
  }

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
      if (mounted) setState(() => selected.clear());
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
      canPop: selected.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selected.isNotEmpty) setState(() => selected.clear());
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      Theme.of(context).platform == TargetPlatform.macOS
                          ? 38
                          : 8,
                      20,
                      8,
                    ),
                    child: Row(
                      children: [
                        if (selected.isNotEmpty) ...[
                          IconButton(
                            onPressed: () => setState(() => selected.clear()),
                            tooltip: t.cancel,
                            icon: const Icon(Icons.close_rounded),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t.selectedCount(selected.length),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: t.selectAll,
                            onPressed: () => setState(
                              () => selected.addAll(
                                widget.records.value.where(
                                  (item) =>
                                      item.received &&
                                      (query.isEmpty ||
                                          '${item.name} ${item.peer} ${item.preview ?? ''}'
                                              .toLowerCase()
                                              .contains(query)),
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.select_all_rounded),
                          ),
                          IconButton(
                            tooltip: t.removeRecord,
                            onPressed: () => _confirmRemove(selected),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ] else ...[
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            tooltip: MaterialLocalizations.of(context)
                                .backButtonTooltip,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: searching
                                ? TextField(
                                    controller: searchController,
                                    autofocus: true,
                                    onChanged: (value) => setState(
                                      () => query = value.trim().toLowerCase(),
                                    ),
                                    decoration: InputDecoration(
                                      hintText: t.searchHistory,
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                  )
                                : Text(
                                    t.transferHistory,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                          ),
                          IconButton(
                            tooltip: t.openReceiveFolder,
                            icon: const Icon(Icons.folder_open_rounded),
                            onPressed: () async {
                              try {
                                await widget.openFolder();
                              } catch (_) {
                                if (context.mounted) {
                                  showNotice(
                                    context,
                                    t.storageFailed,
                                    kind: NoticeKind.error,
                                  );
                                }
                              }
                            },
                          ),
                          ValueListenableBuilder<List<TransferRecord>>(
                            valueListenable: widget.records,
                            builder: (context, items, _) =>
                                !items.any((item) => item.received)
                                ? const SizedBox.shrink()
                                : IconButton(
                                    tooltip: searching
                                        ? t.close
                                        : t.searchHistory,
                                    icon: Icon(
                                      searching
                                          ? Icons.close_rounded
                                          : Icons.search_rounded,
                                    ),
                                    onPressed: () => setState(() {
                                      searching = !searching;
                                      searchController.clear();
                                      query = '';
                                    }),
                                  ),
                          ),
                          if (!searching)
                            ValueListenableBuilder<List<TransferRecord>>(
                              valueListenable: widget.records,
                              builder: (context, items, _) =>
                                  !items.any((item) => item.received)
                                  ? const SizedBox.shrink()
                                  : IconButton(
                                      tooltip: t.clearHistory,
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                      onPressed: () => _confirmRemove(
                                        items.where((item) => item.received),
                                      ),
                                    ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<List<TransferRecord>>(
                      valueListenable: widget.records,
                      builder: (context, allItems, _) {
                        final received = allItems
                            .where((item) => item.received)
                            .toList();
                        if (received.isEmpty) {
                          return Center(
                            child: Text(
                              t.noTransferHistory,
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          );
                        }
                        final items = query.isEmpty
                            ? received
                            : received
                                  .where(
                                    (item) =>
                                        '${item.name} ${item.peer} ${item.preview ?? ''}'
                                            .toLowerCase()
                                            .contains(query),
                                  )
                                  .toList();
                        if (items.isEmpty) {
                          return Center(
                            child: Text(
                              t.noHistoryMatches,
                              style: TextStyle(color: colors.onSurfaceVariant),
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
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
                                    onTap: selected.isNotEmpty
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
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              _icon(item),
                                              size: 21,
                                              color:
                                                  colors.onSecondaryContainer,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.preview?.isNotEmpty ==
                                                          true
                                                      ? item.preview!
                                                      : item.name,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                                const SizedBox(height: 3),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        item.peer,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
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
                                          if (selected.isNotEmpty)
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
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              onSelected: (action) async {
                                                try {
                                                  if (action == 'export') {
                                                    await widget.export(item);
                                                  } else if (action ==
                                                      'reveal') {
                                                    await widget.reveal(item);
                                                  } else if (action ==
                                                      'details') {
                                                    _showDetails(item);
                                                  } else {
                                                    await _confirmRemove([
                                                      item,
                                                    ]);
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
                                                if (item.fileReference !=
                                                        null &&
                                                    item.kind.isFile &&
                                                    (Platform.isAndroid ||
                                                        Platform.isMacOS ||
                                                        DesktopPlatform
                                                            .isWindowsOrLinux))
                                                  PopupMenuItem(
                                                    value: 'reveal',
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Icon(
                                                          Icons.folder_outlined,
                                                          size: 20,
                                                        ),
                                                        const SizedBox(
                                                          width: 12,
                                                        ),
                                                        Text(
                                                          Platform.isMacOS
                                                              ? t.revealInFinder
                                                              : t.showInFolder,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                PopupMenuItem(
                                                  value: 'details',
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        Icons
                                                            .info_outline_rounded,
                                                        size: 20,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Text(t.recordDetails),
                                                    ],
                                                  ),
                                                ),
                                                if (item.fileReference !=
                                                        null &&
                                                    !item.kind.isText &&
                                                    Platform.isAndroid)
                                                  PopupMenuItem(
                                                    value: 'export',
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Icon(
                                                          Icons
                                                              .save_alt_rounded,
                                                          size: 20,
                                                        ),
                                                        const SizedBox(
                                                          width: 12,
                                                        ),
                                                        Text(t.saveAs),
                                                      ],
                                                    ),
                                                  ),
                                                PopupMenuItem(
                                                  value: 'remove',
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        Icons
                                                            .playlist_remove_rounded,
                                                        size: 20,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Text(t.removeRecord),
                                                    ],
                                                  ),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
