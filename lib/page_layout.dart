import 'package:flutter/material.dart';

class PageLayout extends StatelessWidget {
  const PageLayout({
    super.key,
    required this.header,
    required this.body,
    this.maxWidth = 560,
  });

  final Widget header;
  final Widget body;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    Widget centered(Widget child) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
    return SafeArea(
      child: Column(
        children: [
          if (desktop) header else centered(header),
          Expanded(child: centered(body)),
        ],
      ),
    );
  }
}
