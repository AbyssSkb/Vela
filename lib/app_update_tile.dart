import 'package:flutter/material.dart';

import 'app_update.dart';
import 'l10n/generated/app_localizations.dart';
import 'notice.dart';
import 'settings_row_title.dart';

class AppUpdateTile extends StatelessWidget {
  const AppUpdateTile({super.key, required this.controller});

  final AppUpdateController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final t = AppLocalizations.of(context)!;
      final colors = Theme.of(context).colorScheme;
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      String text(String en, String cn) => zh ? cn : en;
      final failed = controller.state == AppUpdateState.error;
      final version = controller.version.isEmpty ? null : controller.version;
      final progress = controller.progress;
      final busyMessage = text(
        'Finish the current operation first',
        '请先完成当前操作',
      );
      final status = switch (controller.state) {
        AppUpdateState.disabled || AppUpdateState.idle => version,
        AppUpdateState.checking => text('Checking…', '检查中…'),
        AppUpdateState.current => text('Up to date', '已是最新'),
        AppUpdateState.downloading =>
          progress == null
              ? text('Downloading…', '下载中…')
              : '${(progress * 100).round()}%',
        AppUpdateState.ready =>
          controller.busy ? busyMessage : controller.availableVersion,
        AppUpdateState.installing => text('Installing…', '安装中…'),
        AppUpdateState.error => t.appUpdateFailed,
      };
      Future<void> confirmInstall() async {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(text('Install update?', '安装更新？')),
            content: controller.platform == 'android'
                ? null
                : Text(text('Vela will restart.', 'Vela 将重启。')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(text('Later', '稍后')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(text('Install', '安装')),
              ),
            ],
          ),
        );
        if (accepted != true || !context.mounted) return;
        if (!controller.canInstall) {
          showNotice(context, busyMessage, kind: NoticeKind.info);
          return;
        }
        await controller.install();
        if (context.mounted && controller.errorCode != null) {
          showNotice(context, switch (controller.errorCode) {
            'unknown_sources' => text(
              'Allow Vela to install updates in Android settings, then try again.',
              '请在 Android 设置中允许 Vela 安装更新，然后重试。',
            ),
            'read_only' => text(
              'Move Vela to a writable location and try again.',
              '请将 Vela 移到可写位置后重试。',
            ),
            'busy' => busyMessage,
            _ => text(
              'Could not install the update. Please try again.',
              '无法安装更新，请重试。',
            ),
          }, kind: NoticeKind.error);
        }
      }

      final value = status == null
          ? null
          : Semantics(
              liveRegion: true,
              child: Text(
                status,
                style: failed ? TextStyle(color: colors.error) : null,
              ),
            );
      return ListTile(
        key: const ValueKey('app-update'),
        leading: const Icon(Icons.system_update_alt_rounded, size: 20),
        title: SettingsRowTitle(
          controller.state == AppUpdateState.disabled
              ? text('Version', '版本')
              : text('App updates', '应用更新'),
          value: value,
        ),
        trailing: controller.canCheck
            ? TextButton(
                onPressed: controller.check,
                child: Text(failed ? t.retry : t.appUpdateCheck),
              )
            : controller.state == AppUpdateState.ready
            ? FilledButton(
                key: const ValueKey('install-update'),
                onPressed: controller.canInstall ? confirmInstall : null,
                child: Text(text('Install', '安装')),
              )
            : null,
      );
    },
  );
}
