import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'graph_physics.dart';

class _NodePanGestureRecognizer extends PanGestureRecognizer {
  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind kind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved.abs() > computeHitSlop(kind, gestureSettings);
}

class DeviceGraph extends StatefulWidget {
  const DeviceGraph({
    super.key,
    required this.peers,
    required this.selfName,
    required this.selfLabel,
    required this.selfIcon,
    required this.name,
    required this.icon,
    required this.presence,
    required this.selected,
    required this.selecting,
    required this.onSelfTap,
    required this.onTap,
    required this.onLongPress,
    required this.enabled,
    this.dropTargetKey,
    this.availableHeight,
    this.minimumScale = 0,
  }) : assert(minimumScale >= 0 && minimumScale <= 1);
  final List<String> peers;
  final String selfName, selfLabel;
  final IconData selfIcon;
  final String Function(String) name;
  final IconData Function(String) icon;
  final Widget Function(String) presence;
  final Set<String> selected;
  final VoidCallback onSelfTap;
  final ValueChanged<String> onTap, onLongPress;
  final bool enabled, selecting;
  final Key? Function(String)? dropTargetKey;
  final double? availableHeight;
  final double minimumScale;

  @override
  State<DeviceGraph> createState() => _DeviceGraphState();
}

class _DeviceGraphState extends State<DeviceGraph>
    with SingleTickerProviderStateMixin {
  static const selfId = '\u0000self';
  static const nodeSize = Size(104, 108);
  static const iconSize = 52.0;
  final physics = GraphPhysics(collisionDiameter: iconSize);
  late final Ticker ticker = createTicker(_tick);
  Duration? lastTick;
  final Map<int, double> radii = {};
  final graphViewportKey = GlobalKey();
  ScrollController? horizontalScroll;
  double? lastHorizontalCenter;
  bool centeredVertically = false, verticalCenterScheduled = false;
  double? lastVerticalOffset, lastGraphHeight, lastAvailableHeight;

  void _tick(Duration elapsed) {
    if (MediaQuery.disableAnimationsOf(context)) {
      ticker.stop();
      lastTick = null;
      physics.stop();
      return;
    }
    final dt = lastTick == null
        ? 1 / 60
        : (elapsed - lastTick!).inMicroseconds / 1000000;
    lastTick = elapsed;
    final moving = physics.step(dt);
    if (mounted) setState(() {});
    if (!moving) {
      ticker.stop();
      lastTick = null;
    }
  }

  void _drag(String id, Offset delta) {
    physics.drag(id, delta);
    if (!ticker.isActive && !MediaQuery.disableAnimationsOf(context)) {
      ticker.start();
    }
    setState(() {});
  }

  @override
  void dispose() {
    horizontalScroll?.dispose();
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = widget.peers.length;
        List<Offset> offsets(double radius) => [
          for (var i = 0; i < count; i++)
            Offset(
              math.cos(2 * math.pi * i / count) * radius,
              math.sin(2 * math.pi * i / count) * radius,
            ),
        ];
        Rect box(Offset point) => Rect.fromCenter(
          center: point,
          width: nodeSize.width + 10,
          height: nodeSize.height + 10,
        );
        bool intersects(Rect rect, Offset end) {
          var low = 0.0, high = 1.0;
          for (final (value, min, max) in [
            (end.dx, rect.left, rect.right),
            (end.dy, rect.top, rect.bottom),
          ]) {
            if (value.abs() < 1e-9) {
              if (min > 0 || max < 0) return false;
              continue;
            }
            var a = min / value, b = max / value;
            if (a > b) {
              final swap = a;
              a = b;
              b = swap;
            }
            low = math.max(low, a);
            high = math.min(high, b);
            if (low > high) return false;
          }
          return true;
        }

        bool fits(double radius) {
          final points = offsets(radius);
          final rects = [for (final point in points) box(point)];
          for (var i = 0; i < count; i++) {
            if (rects[i].overlaps(box(Offset.zero))) return false;
            for (var j = 0; j < i; j++) {
              if (rects[i].overlaps(rects[j])) return false;
            }
            for (var j = 0; j < count; j++) {
              if (j != i && intersects(rects[j], points[i])) return false;
            }
          }
          return true;
        }

        final radius = radii.putIfAbsent(count, () {
          var lower = 0.0, upper = math.max(180.0, count * 150.0);
          for (var i = 0; i < 18; i++) {
            final middle = (lower + upper) / 2;
            if (fits(middle)) {
              upper = middle;
            } else {
              lower = middle;
            }
          }
          return math.max(120.0, upper + 8);
        });
        final ring = offsets(radius);
        final requiredWidth =
            ring.fold<double>(
                  0,
                  (value, point) => math.max(value, point.dx.abs()),
                ) *
                2 +
            144;
        final requiredHeight =
            ring.fold<double>(
                  0,
                  (value, point) => math.max(value, point.dy.abs()),
                ) *
                2 +
            144;
        final viewportWidth = math.max(
          constraints.maxWidth,
          requiredWidth * widget.minimumScale,
        );
        final viewportHeight = math.max(
          math.max(
            100.0,
            widget.availableHeight ?? MediaQuery.sizeOf(context).height * .55,
          ),
          requiredHeight * widget.minimumScale,
        );
        final shortSide = MediaQuery.sizeOf(context).shortestSide;
        final orientationScale = shortSide > 48
            ? math.min(
                1.0,
                math.max(widget.minimumScale, (shortSide - 48) / requiredWidth),
              )
            : 1.0;
        final fitScale = math.min(
          orientationScale,
          math.min(
            viewportWidth / requiredWidth,
            viewportHeight / requiredHeight,
          ),
        );
        if (widget.minimumScale > 0 &&
            !verticalCenterScheduled &&
            (!centeredVertically ||
                lastGraphHeight != viewportHeight ||
                lastAvailableHeight != widget.availableHeight)) {
          final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
          if (scrollable != null) {
            verticalCenterScheduled = true;
            lastGraphHeight = viewportHeight;
            lastAvailableHeight = widget.availableHeight;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              verticalCenterScheduled = false;
              if (!mounted || !scrollable.position.hasContentDimensions) return;
              final position = scrollable.position;
              if (position.maxScrollExtent <= 0) return;
              final graphBox =
                  graphViewportKey.currentContext?.findRenderObject()
                      as RenderBox?;
              final scrollBox =
                  scrollable.context.findRenderObject() as RenderBox?;
              if (graphBox == null ||
                  scrollBox == null ||
                  graphBox.size.height <= scrollBox.size.height) {
                return;
              }
              final mayCenter = !centeredVertically
                  ? position.pixels.abs() < .1
                  : lastVerticalOffset != null &&
                        (position.pixels - lastVerticalOffset!).abs() < .1;
              centeredVertically = true;
              if (mayCenter && !position.isScrollingNotifier.value) {
                final graphY = graphBox
                    .localToGlobal(graphBox.size.center(Offset.zero))
                    .dy;
                final viewportTop = scrollBox.localToGlobal(Offset.zero).dy;
                final viewportBottom = viewportTop + scrollBox.size.height;
                final viewportY = (viewportTop + viewportBottom) / 2;
                position.jumpTo(
                  (position.pixels + graphY - viewportY).clamp(
                    position.minScrollExtent,
                    position.maxScrollExtent,
                  ),
                );
                lastVerticalOffset = position.pixels;
              }
            });
          }
        }
        final canvasWidth = math.max(requiredWidth, viewportWidth / fitScale);
        final canvasHeight = math.max(
          requiredHeight,
          viewportHeight / fitScale,
        );
        final center = Offset(canvasWidth / 2, (canvasHeight - 28) / 2);
        final anchors = ring.map((point) => point + center).toList();
        final entering = physics.positions.isEmpty;
        final changed =
            physics.positions.length != count + 1 ||
            widget.peers.any((id) => !physics.positions.containsKey(id));
        final wallSize = Size(
          canvasWidth / 2 - nodeSize.width / 2,
          center.dy - 40,
        );
        final resized =
            physics.center != center ||
            physics.wallRadiusX != wallSize.width ||
            physics.wallRadiusY != wallSize.height;
        final maxLinkLength =
            2 *
            math.sqrt(
              wallSize.width * wallSize.width +
                  wallSize.height * wallSize.height,
            );
        physics.updateAnchors(
          {
            selfId: center,
            for (var i = 0; i < count; i++) widget.peers[i]: anchors[i],
          },
          center: center,
          wallSize: wallSize,
          linkCenter: selfId,
          maxLinkLength: maxLinkLength,
          screenScale: fitScale,
        );
        if ((changed || resized) &&
            count > 0 &&
            !ticker.isActive &&
            !MediaQuery.disableAnimationsOf(context)) {
          physics.wake(jitter: entering);
          ticker.start();
        }
        final selfPoint = physics.positions[selfId]!;
        final points = [for (final id in widget.peers) physics.positions[id]!];
        Widget node({
          required Offset point,
          required String title,
          required IconData symbol,
          String? id,
        }) {
          final isSelf = id == null;
          final nodeId = id ?? selfId;
          final isSelected = id != null && widget.selected.contains(id);
          return Positioned(
            key: ValueKey('position-${id ?? 'self'}'),
            left: point.dx - nodeSize.width / 2,
            top: point.dy - 40,
            width: nodeSize.width,
            height: nodeSize.height,
            child: TweenAnimationBuilder<double>(
              key: ValueKey('node-${id ?? 'self'}'),
              tween: Tween(begin: 0, end: 1),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              builder: (context, progress, child) => Opacity(
                opacity: progress,
                child: Transform.scale(
                  alignment: const Alignment(0, -7 / 27),
                  scale: .9 + progress * .1,
                  child: child,
                ),
              ),
              child: Semantics(
                key: id == null ? null : widget.dropTargetKey?.call(id),
                label: isSelf ? widget.selfLabel : null,
                selected: isSelected,
                child: Material(
                  color: Colors.transparent,
                  child: RawGestureDetector(
                    gestures: widget.enabled
                        ? {
                            _NodePanGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  _NodePanGestureRecognizer
                                >(
                                  () => _NodePanGestureRecognizer(),
                                  (recognizer) => recognizer
                                    ..onStart = (_) {
                                      physics.dragging = nodeId;
                                      if (!ticker.isActive &&
                                          !MediaQuery.disableAnimationsOf(
                                            context,
                                          )) {
                                        ticker.start();
                                      }
                                    }
                                    ..onUpdate = (details) {
                                      _drag(nodeId, details.delta);
                                    }
                                    ..onEnd = (details) {
                                      final reducedMotion =
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          );
                                      physics.endDrag(
                                        velocity: reducedMotion
                                            ? Offset.zero
                                            : details.velocity.pixelsPerSecond,
                                      );
                                      if (!reducedMotion && !ticker.isActive) {
                                        ticker.start();
                                      }
                                    }
                                    ..onCancel = () {
                                      physics.endDrag();
                                      if (!MediaQuery.disableAnimationsOf(
                                            context,
                                          ) &&
                                          !ticker.isActive) {
                                        ticker.start();
                                      }
                                    },
                                ),
                          }
                        : const {},
                    child: InkWell(
                      key: isSelf
                          ? const ValueKey('graph-self')
                          : ValueKey('peer-$id'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: !widget.enabled
                          ? null
                          : isSelf
                          ? (!widget.selecting ? widget.onSelfTap : null)
                          : () => widget.onTap(id),
                      onLongPress: isSelf || !widget.enabled
                          ? null
                          : () => widget.onLongPress(id),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(5, 14, 5, 0),
                        child: Column(
                          children: [
                            SizedBox(
                              key: ValueKey('graph-icon-${id ?? 'self'}'),
                              width: iconSize,
                              height: iconSize,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: iconSize,
                                    height: iconSize,
                                    decoration: BoxDecoration(
                                      color: isSelf
                                          ? colors.primary
                                          : isSelected
                                          ? colors.secondaryContainer
                                          : colors.surfaceContainerHigh,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      symbol,
                                      color: isSelf
                                          ? colors.onPrimary
                                          : colors.primary,
                                      size: 25,
                                    ),
                                  ),
                                  if (isSelf)
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: colors.surface,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Tooltip(
                                          message: widget.selfLabel,
                                          child: Icon(
                                            Icons.person_rounded,
                                            size: 12,
                                            color: colors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (!isSelf)
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: colors.surface,
                                          shape: BoxShape.circle,
                                        ),
                                        child: widget.selecting
                                            ? Icon(
                                                isSelected
                                                    ? Icons.check_circle
                                                    : Icons.circle_outlined,
                                                size: 12,
                                                color: isSelected
                                                    ? colors.primary
                                                    : colors.onSurfaceVariant,
                                              )
                                            : widget.presence(id),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final graph = SizedBox(
          key: const ValueKey('device-graph'),
          height: viewportHeight,
          width: viewportWidth,
          child: Center(
            key: graphViewportKey,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: Stack(
                  children: [
                    for (var i = 0; i < count; i++)
                      Positioned.fill(
                        key: ValueKey('link-${widget.peers[i]}'),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 360),
                          curve: Curves.easeOutCubic,
                          builder: (context, progress, _) => CustomPaint(
                            painter: _LinksPainter(
                              selfPoint,
                              points[i],
                              colors.outlineVariant,
                              progress,
                            ),
                          ),
                        ),
                      ),
                    node(
                      point: selfPoint,
                      title: widget.selfName,
                      symbol: widget.selfIcon,
                    ),
                    for (var i = 0; i < count; i++)
                      node(
                        point: points[i],
                        title: widget.name(widget.peers[i]),
                        symbol: widget.icon(widget.peers[i]),
                        id: widget.peers[i],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        final horizontalCenter = math.max(
          0.0,
          (viewportWidth - constraints.maxWidth) / 2,
        );
        if (horizontalScroll == null) {
          horizontalScroll = ScrollController(
            initialScrollOffset: horizontalCenter,
            keepScrollOffset: false,
          );
        } else if (lastHorizontalCenter != horizontalCenter) {
          final oldCenter = lastHorizontalCenter;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final controller = horizontalScroll;
            if (!mounted ||
                controller == null ||
                !controller.hasClients ||
                oldCenter == null) {
              return;
            }
            if ((controller.offset - oldCenter).abs() < .1 &&
                !controller.position.isScrollingNotifier.value) {
              controller.jumpTo(
                horizontalCenter.clamp(
                  controller.position.minScrollExtent,
                  controller.position.maxScrollExtent,
                ),
              );
            }
          });
        }
        lastHorizontalCenter = horizontalCenter;
        return SingleChildScrollView(
          key: const ValueKey('graph-horizontal-scroll'),
          controller: horizontalScroll,
          scrollDirection: Axis.horizontal,
          child: graph,
        );
      },
    );
  }
}

class _LinksPainter extends CustomPainter {
  const _LinksPainter(this.center, this.point, this.color, this.progress);
  final Offset center, point;
  final double progress;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(center, Offset.lerp(center, point, progress)!, paint);
  }

  @override
  bool shouldRepaint(covariant _LinksPainter oldDelegate) =>
      center != oldDelegate.center ||
      point != oldDelegate.point ||
      color != oldDelegate.color ||
      progress != oldDelegate.progress;
}
