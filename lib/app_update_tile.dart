import 'package:flutter/material.dart';

import 'app_update.dart';
import 'l10n/generated/app_localizations.dart';
import 'notice.dart';

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
      final subtitle = switch (controller.state) {
        AppUpdateState.disabled => text(
          'Updates are unavailable in this build',
          '此版本暂不提供应用内更新',
        ),
        AppUpdateState.idle => null,
        AppUpdateState.checking => text('Checking for updates…', '正在检查更新…'),
        AppUpdateState.current => text('You are up to date', '已是最新版本'),
        AppUpdateState.downloading => text('Downloading update…', '正在下载更新…'),
        AppUpdateState.ready =>
          controller.busy
              ? text(
                  'Finish the current transfer or pairing first',
                  '请先完成当前传输或配对',
                )
              : text('Update ready to install', '更新已下载，可以安装'),
        AppUpdateState.installing => text('Installing update…', '正在安装更新…'),
        AppUpdateState.error => t.appUpdateFailed,
      };
      Future<void> confirmInstall() async {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(text('Install update?', '安装更新？')),
            content: Text(
              controller.platform == 'android'
                  ? text(
                      'Android will ask you to confirm installation.',
                      'Android 将请你确认安装。',
                    )
                  : text(
                      'Vela will close and restart to install the update.',
                      'Vela 将关闭并重启以安装更新。',
                    ),
            ),
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
          showNotice(
            context,
            text('Finish the current transfer or pairing first', '请先完成当前传输或配对'),
            kind: NoticeKind.info,
          );
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
            'busy' => text(
              'Finish the current transfer or pairing first',
              '请先完成当前传输或配对',
            ),
            _ => text(
              'Could not install the update. Please try again.',
              '无法安装更新，请重试。',
            ),
          }, kind: NoticeKind.error);
        }
      }

      return ListTile(
        key: const ValueKey('app-update'),
        leading: const Icon(Icons.system_update_alt_rounded, size: 20),
        titleAlignment: ListTileTitleAlignment.top,
        title: Text(text('App updates', '应用更新')),
        subtitle: OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          spacing: 16,
          overflowSpacing: 4,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (controller.version.isNotEmpty)
                  Text(
                    text(
                      'Installed version ${controller.version}',
                      '已安装版本 ${controller.version}',
                    ),
                  ),
                if (controller.availableVersion case final version?
                    when controller.state == AppUpdateState.ready)
                  Text(text('Available version $version', '待安装版本 $version')),
                if (subtitle != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      subtitle,
                      style: failed ? TextStyle(color: colors.error) : null,
                    ),
                  ),
                if (controller.state == AppUpdateState.downloading)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(value: controller.progress),
                  ),
              ],
            ),
            if (controller.canCheck)
              OutlinedButton(
                onPressed: controller.check,
                child: Text(failed ? t.retry : t.appUpdateCheck),
              ),
            if (controller.state == AppUpdateState.ready)
              FilledButton(
                key: const ValueKey('install-update'),
                onPressed: controller.canInstall ? confirmInstall : null,
                child: Text(text('Install', '安装')),
              ),
          ],
        ),
      );
    },
  );
}
