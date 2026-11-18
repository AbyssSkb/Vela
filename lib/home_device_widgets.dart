import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'l10n/generated/app_localizations.dart';

class EmptyDevicesSliver extends StatelessWidget {
  const EmptyDevicesSliver({super.key, required this.onAddDevice});

  final VoidCallback? onAddDevice;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 72),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                          color: const Color(0xffe9ecfc),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          Icons.laptop_mac_rounded,
                          size: 46,
                          color: colors.primary,
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(19),
                          border: Border.all(color: const Color(0xffe5e8f4)),
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
              const SizedBox(height: 24),
              Text(
                t.connectDevices,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                t.emptyDevices,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('add-device'),
                onPressed: onAddDevice,
                icon: const Icon(Icons.add_rounded),
                label: Text(t.addDevice),
              ),
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

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 90
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: math.min(18, constraints.maxWidth)),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            )
          : Row(
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
            ),
    ),
  );
}
