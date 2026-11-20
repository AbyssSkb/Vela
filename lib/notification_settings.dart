import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/generated/app_localizations.dart';
import 'notice.dart';
import 'settings_row_title.dart';

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
      String section, {
      required String statusKey,
    }) {
      final subtitle = statusKey == 'allNotifications' && notificationsOff
          ? receivesAutomatically
                ? t.notificationAutoAcceptMuted
                : widget.autoAccept
                ? t.notificationAutoAcceptStopped
                : t.notificationBackgroundBlocked
          : null;
      final categoryOff = !notificationsOff && status?[statusKey] == false;
      return ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: largeText ? 12 : 16),
        minTileHeight: 52,
        leading: largeText ? null : Icon(icon, size: 20),
        title: SettingsRowTitle(
          title,
          value: categoryOff ? Text(t.notificationOff) : null,
        ),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: !largeText
            ? const Icon(Icons.chevron_right_rounded, size: 20)
            : null,
        onTap: () => _open(section),
      );
    }

    Widget divider() => Divider(
      height: 1,
      indent: largeText ? 12 : 60,
      endIndent: 20,
      color: colors.outlineVariant.withValues(alpha: .45),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: MaterialLocalizations.of(context)
                          .backButtonTooltip,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.notificationSettings,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Material(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      row(
                        Icons.notifications_outlined,
                        t.notificationSystemSettings,
                        'notification_app',
                        statusKey: 'allNotifications',
                      ),
                      divider(),
                      row(
                        Icons.move_to_inbox_outlined,
                        t.notificationRequests,
                        'notification_requests',
                        statusKey: 'requestNotifications',
                      ),
                      divider(),
                      row(
                        Icons.sync_alt_rounded,
                        t.notificationProgress,
                        'notification_progress',
                        statusKey: 'progressNotifications',
                      ),
                      divider(),
                      row(
                        Icons.task_alt_rounded,
                        t.notificationResults,
                        'notification_results',
                        statusKey: 'resultNotifications',
                      ),
                    ],
                  ),
                ),
                if (status?['liveSupported'] == true) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: row(
                      Icons.dynamic_feed_outlined,
                      t.notificationLive,
                      'notification_live',
                      statusKey: 'liveAllowed',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
