import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'l10n/generated/app_localizations.dart';

class HomeToolbarAction {
  const HomeToolbarAction(
    this.id,
    this.label,
    this.icon,
    this.onPressed, {
    this.key,
    this.buttonIcon,
  });

  final String id, label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Key? key;
  final Widget? buttonIcon;
}

class HomeToolbar extends StatelessWidget {
  const HomeToolbar({
    super.key,
    this.addDevice,
    required this.actions,
    required this.menuActions,
    this.viewMode,
    this.received,
    this.onSettings,
    this.selection,
  });

  final HomeToolbarAction? addDevice;
  final List<HomeToolbarAction> actions;
  final List<HomeToolbarAction> menuActions;
  final HomeToolbarAction? viewMode;
  final HomeToolbarAction? received;
  final VoidCallback? onSettings;
  final Widget? selection;

  Widget _button(BuildContext context, HomeToolbarAction action) {
    final button = IconButton(
      key: action.key,
      tooltip: action.label,
      onPressed: action.onPressed,
      icon: action.buttonIcon ?? Icon(action.icon),
    );
    if (MediaQuery.disableAnimationsOf(context)) return button;
    return TweenAnimationBuilder<double>(
      key: ValueKey('toolbar-fade-${action.id}'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      builder: (_, opacity, child) => Opacity(opacity: opacity, child: child),
      child: button,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) {
      final t = AppLocalizations.of(context)!;
      final width = viewport.maxWidth;
      final target = Theme.of(context).platform == TargetPlatform.android
          ? 48.0
          : 44.0;
      final buttonWidth = math.min(target, math.max(0.0, (width - 8) / 3));
      final titleWidth = MediaQuery.textScalerOf(context).scale(112);
      final labelActions = width >= 620 && titleWidth <= 128;
      final receivedBelow = !labelActions && received != null;
      final viewBelow = !labelActions && width >= 300 && titleWidth <= 128;
      final priority = [
        ?addDevice,
        if (!receivedBelow) ?received,
        ...actions,
        if (labelActions) ?viewMode,
      ];
      final slotCount = ((width - titleWidth - target) / target).floor().clamp(
        0,
        priority.length,
      );
      final visible = priority.take(slotCount).toSet();
      final settings = HomeToolbarAction(
        'settings',
        t.settings,
        Icons.settings_outlined,
        onSettings,
      );
      final menu = [
        ...priority.skip(slotCount),
        if (!labelActions && !viewBelow) ?viewMode,
        ...menuActions,
        if (onSettings != null) settings,
      ];
      final byId = {for (final action in menu) action.id: action};
      Widget labeled(HomeToolbarAction action) {
        final style = TextButton.styleFrom(minimumSize: const Size(48, 48));
        if (width < 120) {
          return TextButton(
            key: action.key,
            onPressed: action.onPressed,
            style: style,
            child: Text(action.label),
          );
        }
        return TextButton.icon(
          key: action.key,
          onPressed: action.onPressed,
          style: style,
          icon: Icon(action.icon),
          label: Text(action.label),
        );
      }

      return IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: Size(buttonWidth, 48),
            fixedSize: Size(buttonWidth, 48),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        child:
            selection ??
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.devices,
                        maxLines: titleWidth > 112 ? null : 1,
                        overflow: titleWidth > 112
                            ? null
                            : TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    SizedBox(width: math.min(16, math.max(0, width - 16))),
                    for (final action in actions)
                      if (visible.contains(action)) _button(context, action),
                    if (visible.contains(viewMode))
                      if (width >= 760)
                        labeled(viewMode!)
                      else
                        _button(context, viewMode!),
                    if (visible.contains(received)) labeled(received!),
                    if (visible.contains(addDevice))
                      if (labelActions)
                        labeled(addDevice!)
                      else
                        _button(context, addDevice!),
                    if (menu.isNotEmpty)
                      if (menu.length == 1 && menu.single == settings)
                        IconButton(
                          key: const ValueKey('home-settings'),
                          tooltip: t.settings,
                          onPressed: onSettings,
                          icon: const Icon(Icons.settings_outlined),
                        )
                      else
                        PopupMenuButton<String>(
                          key: const ValueKey('home-more'),
                          tooltip: MaterialLocalizations.of(context)
                              .showMenuTooltip,
                          icon: const Icon(Icons.more_vert_rounded),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          onSelected: (id) => byId[id]?.onPressed?.call(),
                          itemBuilder: (_) => [
                            for (final action in menu)
                              PopupMenuItem(
                                key: action == settings
                                    ? const ValueKey('home-settings')
                                    : action.key,
                                value: action.id,
                                enabled: action.onPressed != null,
                                child: Row(
                                  children: [
                                    Icon(action.icon, size: 20),
                                    const SizedBox(width: 12),
                                    Flexible(child: Text(action.label)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                  ],
                ),
                if (receivedBelow || (viewBelow && viewMode != null))
                  Wrap(
                    spacing: 8,
                    children: [
                      if (receivedBelow) labeled(received!),
                      if (viewBelow && viewMode != null) labeled(viewMode!),
                    ],
                  ),
              ],
            ),
      );
    },
  );
}
