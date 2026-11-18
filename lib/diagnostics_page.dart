import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/generated/app_localizations.dart';
import 'notice.dart';
import 'src/rust/api/node.dart';

List<(int, DateTime, String)> describeConnectionEvents(
  List<DiagnosticEvent> events,
  Map<String, String> peerNames, {
  required bool chinese,
}) {
  final namesByTrace = <BigInt, String>{};
  for (final event in events) {
    if (event.kind != 'dial_start' || event.details.isEmpty) continue;
    try {
      final details = jsonDecode(event.details);
      if (details is Map && details['peer_id'] is String) {
        final name = peerNames[details['peer_id']];
        if (name != null && name.isNotEmpty) namesByTrace[event.trace] = name;
      }
    } catch (_) {}
  }
  final result = <(int, DateTime, String)>[];
  for (final event in events) {
    final peer = namesByTrace[event.trace];
    final label = switch (event.kind) {
      'dial_connected' =>
        chinese
            ? (peer == null ? '已建立设备连接' : '$peer：连接已建立')
            : (peer == null
                  ? 'Device connection established'
                  : '$peer: connection established'),
      'dial_failed' =>
        chinese
            ? (peer == null ? '设备连接失败' : '$peer：连接失败')
            : (peer == null
                  ? 'Device connection failed'
                  : '$peer: connection failed'),
      'dial_timeout' =>
        chinese
            ? (peer == null ? '设备连接超时' : '$peer：连接超时')
            : (peer == null
                  ? 'Device connection timed out'
                  : '$peer: connection timed out'),
      'session_closed' =>
        chinese
            ? (peer == null ? '设备连接已断开' : '$peer：连接已断开')
            : (peer == null
                  ? 'Device connection closed'
                  : '$peer: connection closed'),
      'session_expired' || 'session_proof_expired' =>
        chinese
            ? (peer == null ? '设备状态检测超时' : '$peer：状态检测超时')
            : (peer == null
                  ? 'Device status check timed out'
                  : '$peer: status check timed out'),
      _ => null,
    };
    if (label != null) {
      result.add((
        event.monotonicMs.toInt(),
        DateTime.fromMillisecondsSinceEpoch(event.timestampMs.toInt()),
        label,
      ));
    }
  }
  return result;
}

class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.nodeReady,
    required this.peerCount,
    required this.reachableCount,
    required this.relayCount,
    required this.readyRelayCount,
    required this.events,
  });

  final bool nodeReady;
  final int peerCount;
  final int reachableCount;
  final int relayCount;
  final int? readyRelayCount;
  final List<String> events;

  String report(bool chinese) {
    final node = nodeReady
        ? (chinese ? '就绪' : 'Ready')
        : (chinese ? '未就绪' : 'Not ready');
    final relay = '${readyRelayCount ?? '—'} / $relayCount';
    return [
      'Vela ${chinese ? '诊断' : 'diagnostics'}',
      '${chinese ? '节点' : 'Node'}: $node',
      '${chinese ? '在线设备' : 'Reachable devices'}: $reachableCount / $peerCount',
      '${chinese ? '就绪中继' : 'Ready relays'}: $relay',
      '',
      '${chinese ? '近期事件' : 'Recent events'}:',
      ...events,
    ].join('\n');
  }
}

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({
    super.key,
    required this.load,
    required this.clear,
    required this.initialEnabled,
    required this.setEnabled,
    this.retryStartup,
    this.refreshDevices,
  });

  final Future<DiagnosticsSnapshot> Function() load;
  final Future<void> Function() clear;
  final bool initialEnabled;
  final Future<void> Function(bool) setEnabled;
  final Future<void> Function()? retryStartup, refreshDevices;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  DiagnosticsSnapshot? snapshot;
  TimeOfDay? refreshedAt;
  Timer? timer;
  bool loading = false;
  bool reload = false;
  bool clearing = false;
  bool failed = false;
  late bool enabled = widget.initialEnabled;
  bool changingEnabled = false;
  bool recovering = false;
  int version = 0;

  bool get chinese => Localizations.localeOf(context).languageCode == 'zh';
  String text(String zh, String en) => chinese ? zh : en;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_load()),
    );
  }

  Future<void> _load() async {
    if (loading) return;
    loading = true;
    final request = version;
    try {
      final next = await widget.load();
      if (mounted && request == version) {
        setState(() {
          snapshot = next;
          refreshedAt = TimeOfDay.now();
          failed = false;
        });
      }
    } catch (_) {
      if (mounted && request == version) setState(() => failed = true);
    } finally {
      loading = false;
      if (reload && mounted) {
        reload = false;
        unawaited(_load());
      }
    }
  }

  Future<void> _clear() async {
    if (clearing) return;
    final t = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t.diagnosticsClearQuestion),
        content: Text(t.diagnosticsClearDetail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            key: const ValueKey('diagnostics-confirm-clear'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.diagnosticsClearEvents),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || clearing) return;
    setState(() => clearing = true);
    version++;
    try {
      await widget.clear();
      if (!mounted) return;
      version++;
      final current = snapshot;
      if (current != null) {
        setState(() {
          snapshot = DiagnosticsSnapshot(
            nodeReady: current.nodeReady,
            peerCount: current.peerCount,
            reachableCount: current.reachableCount,
            relayCount: current.relayCount,
            readyRelayCount: current.readyRelayCount,
            events: const [],
          );
          failed = false;
        });
      }
      if (loading) {
        reload = true;
      } else {
        await _load();
      }
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          text('清空失败', 'Could not clear events'),
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => clearing = false);
    }
  }

  Future<void> _recover(Future<void> Function() action) async {
    setState(() => recovering = true);
    try {
      await action();
      if (!mounted) return;
      if (loading) {
        reload = true;
      } else {
        await _load();
      }
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          AppLocalizations.of(context)!.diagnosticsRecoveryFailed,
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => recovering = false);
    }
  }

  Future<void> _copy() async {
    final current = snapshot;
    if (current == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: current.report(chinese)));
      if (mounted) {
        showNotice(context, text('已复制', 'Copied'), kind: NoticeKind.success);
      }
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          text('复制失败', 'Could not copy'),
          kind: NoticeKind.error,
        );
      }
    }
  }

  Future<void> _setEnabled(bool value) async {
    if (changingEnabled) return;
    final previous = enabled;
    setState(() {
      enabled = value;
      changingEnabled = true;
    });
    try {
      await widget.setEnabled(value);
    } catch (_) {
      if (mounted) {
        setState(() => enabled = previous);
        showNotice(
          context,
          text('设置保存失败', 'Could not save setting'),
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => changingEnabled = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final current = snapshot;
    final notStarted = current?.nodeReady == false;
    final peersUnavailable =
        current != null &&
        current.nodeReady &&
        current.peerCount > 0 &&
        current.reachableCount == 0;
    final recovery = notStarted ? widget.retryStartup : widget.refreshDevices;
    final updated = refreshedAt?.format(context);
    final titleStyle = Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.w700);
    Widget status(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: TextStyle(color: colors.onSurfaceVariant)),
        ],
      ),
    );
    Widget divider() => Divider(
      height: 1,
      indent: 18,
      endIndent: 18,
      color: colors.outlineVariant.withValues(alpha: .45),
    );
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    Platform.isMacOS ? 38 : 8,
                    20,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.maybePop(context),
                              tooltip: MaterialLocalizations.of(context)
                                  .backButtonTooltip,
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(t.diagnostics, style: titleStyle),
                            ),
                          ],
                        ),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton.icon(
                              key: const ValueKey('diagnostics-copy'),
                              onPressed: current == null ? null : _copy,
                              icon: const Icon(Icons.copy_rounded),
                              label: Text(text('复制报告', 'Copy report')),
                            ),
                            if (current != null && current.events.isNotEmpty)
                              PopupMenuButton<void>(
                                key: const ValueKey('diagnostics-actions'),
                                enabled: !clearing,
                                tooltip: t.moreOptions,
                                itemBuilder: (_) => [
                                  PopupMenuItem<void>(
                                    key: const ValueKey('diagnostics-clear'),
                                    onTap: _clear,
                                    child: Text(t.diagnosticsClearEvents),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (notStarted || peersUnavailable)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  notStarted
                                      ? t.diagnosticsStartupHelp
                                      : t.diagnosticsDeviceHelp,
                                ),
                                if (recovery != null)
                                  TextButton(
                                    onPressed: recovering
                                        ? null
                                        : () => _recover(recovery),
                                    child: Text(
                                      recovering
                                          ? t.checking
                                          : notStarted
                                          ? t.diagnosticsRetryStartup
                                          : t.refreshDevices,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        Material(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(18),
                          clipBehavior: Clip.antiAlias,
                          child: SwitchListTile(
                            key: const ValueKey('diagnostics-enabled'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 4,
                            ),
                            title: Text(
                              text('调试日志', 'Debug logging'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              text(
                                '记录连接与状态事件',
                                'Record connection and status events',
                              ),
                            ),
                            value: enabled,
                            onChanged: changingEnabled ? null : _setEnabled,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (current == null)
                          Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  failed
                                      ? text(
                                          '无法获取诊断信息',
                                          'Diagnostics unavailable',
                                        )
                                      : text('正在加载', 'Loading'),
                                ),
                                if (failed)
                                  TextButton(
                                    onPressed: _load,
                                    child: Text(t.retry),
                                  ),
                              ],
                            ),
                          )
                        else ...[
                          if (updated != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                              child: Semantics(
                                liveRegion: failed,
                                child: Text(
                                  failed
                                      ? t.diagnosticsStale(updated)
                                      : t.diagnosticsUpdated(updated),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: failed
                                            ? colors.error
                                            : colors.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ),
                          Material(
                            color: colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                status(
                                  text('节点', 'Node'),
                                  current.nodeReady
                                      ? text('就绪', 'Ready')
                                      : text('未就绪', 'Not ready'),
                                ),
                                divider(),
                                status(
                                  text('在线设备', 'Reachable devices'),
                                  '${current.reachableCount} / ${current.peerCount}',
                                ),
                                divider(),
                                status(
                                  text('就绪中继', 'Ready relays'),
                                  '${current.readyRelayCount ?? '—'} / ${current.relayCount}',
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
                            child: Text(
                              text('近期事件', 'Recent events'),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (current.events.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                text('暂无事件', 'No events'),
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (current != null && current.events.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.builder(
                      itemCount: current.events.length,
                      itemBuilder: (context, index) {
                        final first = index == 0;
                        final last = index == current.events.length - 1;
                        return Material(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.vertical(
                            top: first
                                ? const Radius.circular(18)
                                : Radius.zero,
                            bottom: last
                                ? const Radius.circular(18)
                                : Radius.zero,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              18,
                              first ? 14 : 10,
                              18,
                              last ? 14 : 0,
                            ),
                            child: SelectableText(
                              current.events[current.events.length - 1 - index],
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
