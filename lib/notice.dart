import 'package:flutter/material.dart';

enum NoticeKind { info, success, error }

const receiptDuration = Duration(seconds: 8);

const _noticeShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
);
const _noticePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 8);

Widget _noticeSurface(Key key, Color color, Widget child) => Material(
  key: key,
  color: color,
  shape: _noticeShape,
  clipBehavior: Clip.antiAlias,
  child: Padding(padding: _noticePadding, child: child),
);

class ActivityNotice extends StatelessWidget {
  const ActivityNotice({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: _noticeSurface(
          const ValueKey('activity-notice'),
          colors.secondaryContainer,
          SafeArea(
            top: false,
            bottom: false,
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
  final route = ModalRoute.of(context);
  var active = true;
  void dismiss() {
    if (active && messenger.mounted) {
      active = false;
      messenger.removeCurrentSnackBar();
    }
  }

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
          dismiss();
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
        onPressed: dismiss,
        color: foreground,
        iconSize: 20,
        icon: const Icon(Icons.close_rounded),
      ),
    ],
  ];
  messenger.clearSnackBars();
  final controller = messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.fixed,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      hitTestBehavior: HitTestBehavior.deferToChild,
      duration: onAction == null
          ? const Duration(seconds: 4)
          : MediaQuery.accessibleNavigationOf(context)
          ? const Duration(days: 1)
          : receiptDuration,
      content: LayoutBuilder(
        builder: (context, constraints) {
          if (MediaQuery.viewInsetsOf(context).bottom > 0 ||
              (route != null &&
                  (ModalRoute.of(context) != route || !route.isCurrent))) {
            WidgetsBinding.instance.addPostFrameCallback((_) => dismiss());
            return const SizedBox.shrink();
          }
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final stackActions =
              actions.isNotEmpty &&
              (constraints.maxWidth - _noticePadding.horizontal < 320 ||
                  scale > 1.3);
          return _noticeSurface(
            const ValueKey('message-notice'),
            background,
            stackActions
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      details,
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        children: actions,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: details),
                      ...actions,
                    ],
                  ),
          );
        },
      ),
    ),
  );
  controller.closed.then((_) => active = false);
  return controller;
}
