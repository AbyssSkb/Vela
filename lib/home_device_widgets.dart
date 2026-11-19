import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'l10n/generated/app_localizations.dart';

class EmptyDevicesSliver extends StatelessWidget {
  const EmptyDevicesSliver({
    super.key,
    required this.onAddDevice,
    required this.onShowCode,
  });

  final VoidCallback? onAddDevice;
  final VoidCallback onShowCode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;
    final showIllustration = !HomeSendButton.usesLargeLabels(context);
    final instructions = Text(
      t.emptyDevices,
      textAlign: TextAlign.center,
      style: TextStyle(color: colors.onSurfaceVariant),
    );
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, showIllustration ? 72 : 24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showIllustration)
                SizedBox(
                  width: 152,
                  height: 112,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          width: 106,
                          height: 78,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(
                            Icons.laptop_mac_rounded,
                            size: 46,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 4,
                        child: Container(
                          width: 57,
                          height: 74,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(19),
                            border: Border.all(color: colors.outlineVariant),
                          ),
                          child: Icon(
                            Icons.phone_android_rounded,
                            size: 32,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (showIllustration) const SizedBox(height: 24),
              Text(
                t.connectDevices,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (showIllustration) ...[
                const SizedBox(height: 8),
                instructions,
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('add-device'),
                onPressed: onAddDevice,
                icon: const Icon(Icons.add_rounded),
                label: Text(t.addDevice),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                key: const ValueKey('show-device-code'),
                onPressed: onShowCode,
                icon: const Icon(Icons.qr_code_rounded),
                label: Text(t.showMyCode, textAlign: TextAlign.center),
              ),
              if (!showIllustration) ...[
                const SizedBox(height: 16),
                instructions,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HomeSendButton extends StatelessWidget {
  const HomeSendButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  static const _largeLabelSize = 13.0;
  static const _horizontalPadding = 8.0;

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
    ),
    child: Semantics(
      label: AppLocalizations.of(context)!.sendContentType(label),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = usesLargeLabels(context);
          if (largeText) {
            return Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: _largeLabelSize),
            );
          }
          if (constraints.maxWidth < 90) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: math.min(18, constraints.maxWidth)),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  static bool usesLargeLabels(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) > 17;

  static double minimumLargeLabelWidth(
    BuildContext context,
    Iterable<HomeSendButton> buttons,
  ) {
    final style = Theme.of(context).textTheme.labelLarge
        ?.copyWith(fontSize: _largeLabelSize);
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    var widest = 0.0;
    for (final button in buttons) {
      painter.text = TextSpan(text: button.label, style: style);
      painter.layout();
      widest = math.max(widest, painter.width);
    }
    painter.dispose();
    return widest.ceilToDouble() + 2 * _horizontalPadding;
  }
}
