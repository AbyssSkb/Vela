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
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .58),
            child: Text(title),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DefaultTextStyle(
              style: theme.textTheme.bodyMedium!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              child: value!,
            ),
          ),
        ],
      ),
    );
  }
}
