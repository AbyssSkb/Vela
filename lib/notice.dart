import 'package:flutter/material.dart';

enum NoticeKind { info, success, error }

class ActivityNotice extends StatelessWidget {
  const ActivityNotice({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Material(
              key: const ValueKey('activity-notice'),
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
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
                maxLines: 3,
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
  final inset = ((MediaQuery.widthOf(context) - 560) / 2).clamp(
    12.0,
    double.infinity,
  );
  messenger.clearSnackBars();
  return messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(inset, 0, inset, 12),
      backgroundColor: background,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      duration: onAction == null
          ? const Duration(seconds: 4)
          : const Duration(days: 1),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          if (actions.isNotEmpty &&
              (detail != null || constraints.maxWidth < 340 || scale > 1.3)) {
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
