import 'package:flutter/material.dart';

class SettingsRowTitle extends StatelessWidget {
  const SettingsRowTitle(this.title, {super.key, this.value});

  final String title;
  final Widget? value;

  @override
  Widget build(BuildContext context) {
    if (value == null) return Text(title);
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(child: Text(title)),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .46),
            child: DefaultTextStyle(
              style: theme.textTheme.bodyMedium!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: value!,
            ),
          ),
        ],
      ),
    );
  }
}
