import 'dart:math' as math;

import 'package:flutter/material.dart';

class HomeResponsiveLayout extends StatefulWidget {
  const HomeResponsiveLayout({
    super.key,
    required this.wide,
    required this.actions,
    required this.devices,
    this.largeText = false,
  });
  final bool wide;
  final List<Widget> actions;
  final Widget devices;
  final bool largeText;

  static const _largeButtonHeight = 64.0;
  static const _gap = 8.0;
  static const _railRowGap = 6.0;

  static double minimumHeight({
    required bool wide,
    required int count,
    required bool largeText,
    required double width,
  }) {
    if (!largeText) {
      return wide ? count * 40.0 + (count - 1) * _railRowGap : 220.0;
    }
    final columns = _largeColumns(width);
    final rows = (count + columns - 1) ~/ columns;
    return wide
        ? count * _largeButtonHeight + (count - 1) * _railRowGap
        : rows * _largeButtonHeight + (rows - 1) * _gap + 120;
  }

  static int _largeColumns(double width) => width < 280 ? 1 : 2;

  @override
  State<HomeResponsiveLayout> createState() => _HomeLayoutState();
}

class _HomeLayoutState extends State<HomeResponsiveLayout>
    with SingleTickerProviderStateMixin {
  late final AnimationController transition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.wide ? 1 : 0,
  );

  @override
  void didUpdateWidget(HomeResponsiveLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wide != widget.wide) {
      if (MediaQuery.disableAnimationsOf(context)) {
        transition.value = widget.wide ? 1 : 0;
      } else if (widget.wide) {
        transition.forward();
      } else {
        transition.reverse();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      transition.value = widget.wide ? 1 : 0;
    }
  }

  @override
  void dispose() {
    transition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: transition,
    builder: (context, _) => CustomMultiChildLayout(
      delegate: _HomeLayoutDelegate(
        transition.value,
        widget.actions.length,
        widget.largeText,
      ),
      children: [
        for (final (index, action) in widget.actions.indexed)
          LayoutId(id: index, child: action),
        LayoutId(id: 'devices', child: widget.devices),
      ],
    ),
  );
}

class _HomeLayoutDelegate extends MultiChildLayoutDelegate {
  _HomeLayoutDelegate(this.progress, this.count, this.largeText);
  final double progress;
  final int count;
  final bool largeText;

  @override
  void performLayout(Size size) {
    const gap = HomeResponsiveLayout._gap,
        railGap = 24.0,
        railRowGap = HomeResponsiveLayout._railRowGap;
    final buttonHeight = largeText
        ? HomeResponsiveLayout._largeButtonHeight
        : 48.0;
    final railWidth = largeText ? 208.0 : 144.0;
    final movingDown = (progress * 3).clamp(0.0, 1.0);
    final movingSide = ((progress - 1 / 3) * 3).clamp(0.0, 1.0);
    final movingUp = ((progress - 2 / 3) * 3).clamp(0.0, 1.0);
    final columns = largeText
        ? math.min(HomeResponsiveLayout._largeColumns(size.width), count)
        : (count > 4 ? 3 : count);
    final railHeight = ((size.height - (count - 1) * railRowGap) / count).clamp(
      largeText ? buttonHeight : 40.0,
      buttonHeight,
    );
    final railTop = math.max(
      0.0,
      (size.height - (railHeight * count + railRowGap * (count - 1))) / 2,
    );
    final buttonWidth = math.max(
      0.0,
      (size.width - gap * (columns - 1)) / columns,
    );
    final width =
        buttonWidth +
        (math.min(railWidth, size.width) - buttonWidth) * movingSide;
    final height = buttonHeight + (railHeight - buttonHeight) * movingDown;
    var bottom = 0.0;
    for (var i = 0; i < count; i++) {
      final x = (i % columns) * (buttonWidth + gap) * (1 - movingSide);
      final stagedY =
          (i ~/ columns) * (buttonHeight + gap) * (1 - movingDown) +
          i * (railHeight + railRowGap) * movingDown;
      final y = stagedY + railTop * movingUp;
      layoutChild(i, BoxConstraints.tight(Size(width, height)));
      positionChild(i, Offset(x, y));
      bottom = math.max(bottom, y + height);
    }
    final left = math.min(size.width, (railWidth + railGap) * movingSide);
    final top = (bottom + 16) * (1 - movingUp);
    layoutChild(
      'devices',
      BoxConstraints.tight(
        Size(math.max(0, size.width - left), math.max(0, size.height - top)),
      ),
    );
    positionChild('devices', Offset(left, top));
  }

  @override
  bool shouldRelayout(_HomeLayoutDelegate oldDelegate) =>
      progress != oldDelegate.progress ||
      count != oldDelegate.count ||
      largeText != oldDelegate.largeText;
}
