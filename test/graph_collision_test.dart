import 'dart:math' as math;

import 'package:vela/device_graph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('stress bounds overlap and links', (tester) async {
    final random = math.Random(41);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final width in [320.0, 1100.0]) {
      for (final count in [2, 6, 20, 50]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: DeviceGraph(
                    minimumScale: .5,
                    availableHeight: 700,
                    peers: List.generate(count, (i) => '$i'),
                    selfName: 'Mac',
                    selfLabel: 'self',
                    selfIcon: Icons.computer,
                    name: (s) => s,
                    icon: (_) => Icons.phone,
                    presence: (_) => const Icon(Icons.circle),
                    selected: const {},
                    selecting: false,
                    onSelfTap: () {},
                    onTap: (_) {},
                    onLongPress: (_) {},
                    enabled: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final dynamic s = tester.state(find.byType(DeviceGraph));
        for (var k = 0; k < 30; k++) {
          final String id = k % 4 == 0
              ? '\u0000self'
              : '${random.nextInt(count)}';
          final Offset pos = s.physics.positions[id];
          final Offset goal =
              Offset(
                (random.nextDouble() * 2 - 1) *
                    (s.physics.wallRadiusX as double),
                (random.nextDouble() * 2 - 1) *
                    (s.physics.wallRadiusY as double),
              ) +
              (s.physics.center as Offset);
          s.physics.drag(id, goal - pos);
          s.physics.endDrag();
          await tester.pump();
          final List<Offset> points = List<Offset>.from(
            s.physics.positions.values,
          );
          final Offset hub = s.physics.positions['\u0000self'];
          for (var i = 0; i < points.length; i++) {
            expect(
              (points[i].dx - (s.physics.center as Offset).dx).abs(),
              lessThanOrEqualTo((s.physics.wallRadiusX as double) + .01),
            );
            expect(
              (points[i].dy - (s.physics.center as Offset).dy).abs(),
              lessThanOrEqualTo((s.physics.wallRadiusY as double) + .01),
            );
            expect(
              (points[i] - hub).distance,
              lessThanOrEqualTo((s.physics.maxLinkLength as double) + .2),
              reason: 'link count=$count iter=$k',
            );
            for (var j = i + 1; j < points.length; j++) {
              final d = points[i] - points[j];
              expect(
                d.distance >= 51.99,
                isTrue,
                reason: 'overlap count=$count iter=$k',
              );
            }
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
