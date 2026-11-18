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
    this.received,
    this.onSettings,
    this.selection,
  });

  final HomeToolbarAction? addDevice;
  final List<HomeToolbarAction> actions;
  final List<HomeToolbarAction> menuActions;
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
      final buttonWidth = math.min(44.0, math.max(0.0, (width - 8) / 3));
      final priority = [?addDevice, ?received, ...actions];
      final titleWidth = MediaQuery.textScalerOf(context).scale(112);
      final slotCount = ((width - titleWidth - 44) / 44).floor().clamp(
        0,
        priority.length,
      );
      final visible = priority.take(slotCount).toSet();
      final labelActions = width >= 620 && titleWidth <= 128;
      final settings = HomeToolbarAction(
        'settings',
        t.settings,
        Icons.settings_outlined,
        onSettings,
      );
      final menu = [
        ...priority.skip(slotCount),
        ...menuActions,
        if (onSettings != null) settings,
      ];
      final byId = {for (final action in menu) action.id: action};
      Widget primaryButton(HomeToolbarAction action) => labelActions
          ? TextButton.icon(
              key: action.key,
              onPressed: action.onPressed,
              icon: Icon(action.icon),
              label: Text(action.label),
            )
          : _button(context, action);
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.devices,
                    maxLines: titleWidth > 112 ? null : 1,
                    overflow: titleWidth > 112 ? null : TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(width: math.min(16, math.max(0, width - 16))),
                for (final action in actions)
                  if (visible.contains(action)) _button(context, action),
                if (visible.contains(received)) primaryButton(received!),
                if (visible.contains(addDevice)) primaryButton(addDevice!),
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
      );
    },
  );
}
