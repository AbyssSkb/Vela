import 'package:flutter/material.dart';

enum NoticeKind { info, success, error }

const _noticeShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
);
const _noticePadding = EdgeInsets.all(16);

class ActivityNotice extends StatelessWidget {
  const ActivityNotice({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('activity-notice'),
      color: colors.secondaryContainer,
      shape: _noticeShape,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: _noticePadding,
          child: IconTheme.merge(
            data: IconThemeData(color: colors.onSecondaryContainer),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: colors.onSecondaryContainer,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showNotice(
  BuildContext context,
  String message, {
  NoticeKind kind = NoticeKind.info,
  String? detail,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  assert((actionLabel == null) == (onAction == null));
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  final icon = switch (kind) {
    NoticeKind.info => Icons.info_outline_rounded,
    NoticeKind.error => Icons.error_outline_rounded,
    NoticeKind.success => Icons.check_circle_outline_rounded,
  };
  final background = switch (kind) {
    NoticeKind.info => colors.secondaryContainer,
    NoticeKind.error => colors.errorContainer,
    NoticeKind.success =>
      theme.brightness == Brightness.dark
          ? const Color(0xff1d4930)
          : const Color(0xffd9f1df),
  };
  final foreground = switch (kind) {
    NoticeKind.info => colors.onSecondaryContainer,
    NoticeKind.error => colors.onErrorContainer,
    NoticeKind.success =>
      theme.brightness == Brightness.dark
          ? const Color(0xffd9f1df)
          : const Color(0xff174d2f),
  };
  final messenger = ScaffoldMessenger.of(context);
  final details = Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: foreground, size: 19),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (detail != null)
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground),
              ),
          ],
        ),
      ),
    ],
  );
  final actions = [
    if (onAction != null) ...[
      TextButton(
        key: const ValueKey('notice-action'),
        onPressed: () {
          messenger.hideCurrentSnackBar();
          onAction();
        },
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(48, 48),
        ),
        child: Text(actionLabel!, textAlign: TextAlign.center),
      ),
      IconButton(
        key: const ValueKey('notice-close'),
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        onPressed: messenger.hideCurrentSnackBar,
        color: foreground,
        iconSize: 20,
        icon: const Icon(Icons.close_rounded),
      ),
    ],
  ];
  messenger.clearSnackBars();
  return messenger.showSnackBar(
    SnackBar(
      key: const ValueKey('message-notice'),
      behavior: SnackBarBehavior.fixed,
      backgroundColor: background,
      elevation: 0,
      padding: _noticePadding,
      shape: _noticeShape,
      clipBehavior: Clip.antiAlias,
      hitTestBehavior: HitTestBehavior.deferToChild,
      duration: onAction == null
          ? const Duration(seconds: 4)
          : const Duration(days: 1),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          if (actions.isNotEmpty &&
              (constraints.maxWidth < 340 || scale > 1.3)) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  children: actions,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              ...actions,
            ],
          );
        },
      ),
    ),
  );
}
