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
    this.onSettings,
    this.selection,
  });

  final HomeToolbarAction? addDevice;
  final List<HomeToolbarAction> actions;
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
      // Add gets the first available slot, at the right end of the toolbar.
      final priority = [if (addDevice != null) addDevice!, ...actions];
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
      final byId = {
        for (final action in [...priority, settings]) action.id: action,
      };
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
                if (visible.contains(addDevice)) _button(context, addDevice!),
                if (onSettings != null)
                  if (visible.length == priority.length)
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
                        for (final action in [
                          ...priority.skip(slotCount),
                          settings,
                        ])
                          PopupMenuItem(
                            key: action.key,
                            value: action.id,
                            enabled: action.onPressed != null,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
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
