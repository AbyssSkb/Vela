import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/generated/app_localizations.dart';
import 'notice.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, this.autoAccept = false});
  final bool autoAccept;
  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('vela/background');
  Map<Object?, Object?>? status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final value = await channel.invokeMapMethod<Object?, Object?>('status');
      if (mounted) setState(() => status = value);
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          AppLocalizations.of(context)!.unknown,
          kind: NoticeKind.error,
        );
      }
    }
  }

  Future<void> _open(String section) async {
    try {
      await channel.invokeMethod<void>('settings', {'section': section});
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          AppLocalizations.of(context)!.backgroundSettingsOpenFailed,
          kind: NoticeKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    final notificationsOff = status?['allNotifications'] == false;
    final receivesAutomatically =
        widget.autoAccept &&
        status?['running'] == true &&
        status?['nodeReady'] == true;
    Widget row(
      IconData icon,
      String title,
      String subtitle,
      String section, {
      String? statusKey,
      bool enabled = true,
    }) => ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: largeText ? 12 : 20,
        vertical: 6,
      ),
      leading: largeText ? null : Icon(icon, size: 22, color: colors.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        statusKey == 'allNotifications' && notificationsOff
            ? receivesAutomatically
                  ? t.notificationAutoAcceptMuted
                  : widget.autoAccept
                  ? t.notificationAutoAcceptStopped
                  : t.notificationBackgroundBlocked
            : statusKey != 'liveAllowed' &&
                  (notificationsOff || status?[statusKey] == false)
            ? t.notificationOff
            : subtitle,
        style: TextStyle(color: colors.onSurfaceVariant),
      ),
      trailing: enabled && !largeText
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (statusKey != null && status?[statusKey] == false)
                  Icon(
                    Icons.info_outline_rounded,
                    size: 19,
                    color: colors.error,
                  ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                ),
              ],
            )
          : null,
      onTap: enabled ? () => _open(section) : null,
    );
    Widget divider() => Divider(
      height: 1,
      indent: largeText ? 12 : 60,
      endIndent: 20,
      color: colors.outlineVariant.withValues(alpha: .45),
    );
    final liveSupported = status?['liveSupported'] == true;
    final liveText = status == null
        ? t.checking
        : !liveSupported
        ? t.notificationLiveUnsupported
        : status?['liveAllowed'] == true
        ? t.notificationLiveAllowed
        : t.notificationLiveDisabled;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Flex(
                  direction: largeText ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: largeText
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: MaterialLocalizations.of(context)
                          .backButtonTooltip,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    if (!largeText) const SizedBox(width: 8),
                    Flexible(
                      flex: largeText ? 0 : 1,
                      child: Text(
                        t.notificationSettings,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Material(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      row(
                        Icons.notifications_outlined,
                        t.notificationSystemSettings,
                        t.notificationChannelHint,
                        'notification_app',
                        statusKey: 'allNotifications',
                      ),
                      divider(),
                      row(
                        Icons.move_to_inbox_outlined,
                        t.notificationRequests,
                        t.notificationRequestsHint,
                        'notification_requests',
                        statusKey: 'requestNotifications',
                      ),
                      divider(),
                      row(
                        Icons.sync_alt_rounded,
                        t.notificationProgress,
                        t.notificationProgressHint,
                        'notification_progress',
                        statusKey: 'progressNotifications',
                      ),
                      divider(),
                      row(
                        Icons.task_alt_rounded,
                        t.notificationResults,
                        t.notificationResultsHint,
                        'notification_results',
                        statusKey: 'resultNotifications',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: row(
                    Icons.dynamic_feed_outlined,
                    t.notificationLive,
                    liveText,
                    'notification_live',
                    statusKey: 'liveAllowed',
                    enabled: liveSupported,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
