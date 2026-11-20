import 'package:vela/graph_physics.dart';

import 'dart:ui' show Size;
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'nodes repel nearby neighbours and retain their hard collision limit',
    () {
      final physics = GraphPhysics(collisionDiameter: 52)
        ..updateAnchors(
          {'a': Offset.zero, 'b': const Offset(100, 100)},
          center: Offset.zero,
          wallSize: const Size(500, 500),
        );
      physics.drag('a', const Offset(38, 38));
      expect(
        physics.positions['b'],
        const Offset(100, 100),
        reason: 'Diagonal gaps must not collide as rectangles',
      );
      for (var i = 0; i < 10; i++) {
        physics.step(1 / 60);
      }
      expect(
        (physics.positions['b']! - const Offset(100, 100)).distance,
        lessThan(.01),
        reason: 'Distant nodes should stay still',
      );
      physics.drag('a', const Offset(22, 22));
      expect(physics.positions['b'], const Offset(100, 100));
      for (var i = 0; i < 10; i++) {
        physics.step(1 / 60);
      }
      final pushed = physics.positions['b']!;
      expect((pushed - const Offset(100, 100)).distance, greaterThan(1));
      physics.drag('a', pushed - physics.positions['a']!);
      expect(
        (physics.positions['a']! - physics.positions['b']!).distance,
        greaterThanOrEqualTo(52),
      );
      expect((physics.positions['b']! - pushed).distance, greaterThan(1));
    },
  );

  test('coincident icons separate without invalid positions', () {
    final physics = GraphPhysics(collisionDiameter: 52)
      ..updateAnchors(
        {'a': const Offset(-100, 0), 'b': const Offset(100, 0)},
        center: Offset.zero,
        wallSize: const Size(300, 300),
      );
    physics.drag('a', const Offset(200, 0));
    final a = physics.positions['a']!, b = physics.positions['b']!;
    expect(
      a.dx.isFinite && a.dy.isFinite && b.dx.isFinite && b.dy.isFinite,
      isTrue,
    );
    expect((a - b).distance, greaterThanOrEqualTo(52));
  });

  test(
    'release keeps bounded pointer momentum while cancellation has none',
    () {
      final physics = GraphPhysics()
        ..updateAnchors(
          {'a': Offset.zero},
          center: Offset.zero,
          wallSize: const Size(1000, 1000),
        );
      physics.drag('a', const Offset(10, 0));
      physics.endDrag(velocity: const Offset(5000, 0));
      expect(physics.velocities['a']!.dx, inInclusiveRange(1, 1200));
      physics.step(1 / 60);
      expect(physics.positions['a']!.dx, greaterThan(10));
      physics.drag('a', Offset.zero);
      physics.endDrag();
      expect(physics.velocities['a'], Offset.zero);
    },
  );
  test(
    'stretched links pull devices together without snapping them to anchors',
    () {
      final physics = GraphPhysics()
        ..updateAnchors(
          {'a': Offset.zero, 'b': const Offset(200, 0)},
          center: Offset.zero,
          wallSize: const Size(1000, 1000),
          linkCenter: 'a',
          maxLinkLength: 600,
        );
      physics.drag('b', const Offset(150, 0));
      physics.endDrag();
      final before =
          (physics.positions['b']! - physics.positions['a']!).distance;
      for (var i = 0; i < 60; i++) {
        physics.step(1 / 60);
      }
      expect(
        (physics.positions['b']! - physics.positions['a']!).distance,
        lessThan(before),
      );
      expect(physics.positions['a']!, isNot(physics.anchors['a']));
    },
  );
  test('30 and 60 frames per second advance the same simulated time', () {
    GraphPhysics make() => GraphPhysics()
      ..updateAnchors(
        {'a': Offset.zero, 'b': const Offset(200, 0)},
        center: Offset.zero,
        wallSize: const Size(1000, 1000),
        linkCenter: 'a',
        maxLinkLength: 600,
      )
      ..drag('b', const Offset(150, 0))
      ..endDrag(velocity: const Offset(250, 0));
    final fast = make(), slow = make();
    for (var i = 0; i < 120; i++) {
      fast.step(1 / 60);
    }
    for (var i = 0; i < 60; i++) {
      slow.step(1 / 30);
    }
    for (final id in fast.positions.keys) {
      expect((fast.positions[id]! - slow.positions[id]!).distance, lessThan(1));
    }
  });
  test('links limit distance while a dragged node pulls its neighbour', () {
    final physics = GraphPhysics()
      ..updateAnchors(
        {'self': const Offset(250, 250), 'other': const Offset(400, 250)},
        center: const Offset(250, 250),
        wallSize: const Size(230, 230),
        linkCenter: 'self',
        maxLinkLength: 180,
      );
    physics.drag('other', const Offset(0, 210));
    for (var i = 0; i < 120; i++) {
      physics.step(1 / 60);
    }
    expect(
      (physics.positions['other']! - physics.positions['self']!).distance,
      lessThanOrEqualTo(180.1),
    );
    expect(
      (physics.positions['self']! - const Offset(250, 250)).distance,
      greaterThan(10),
    );
    physics.endDrag();
    for (var i = 0; i < 300; i++) {
      physics.step(1 / 60);
    }
    expect(
      (physics.positions['other']! - physics.positions['self']!).distance,
      lessThanOrEqualTo(180.1),
    );
  });
  test('moving the hub keeps all links and nodes inside their limits', () {
    for (final count in [2, 8, 20]) {
      final physics = GraphPhysics()
        ..updateAnchors(
          {
            'self': Offset.zero,
            for (var i = 0; i < count; i++)
              '$i':
                  Offset(
                    math.cos(i * 2 * math.pi / count),
                    math.sin(i * 2 * math.pi / count),
                  ) *
                  150,
          },
          center: Offset.zero,
          wallSize: const Size(260, 220),
          linkCenter: 'self',
          maxLinkLength: 210,
        );
      physics.drag('self', const Offset(250, 180));
      for (var i = 0; i < 120; i++) {
        physics.step(1 / 60);
      }
      for (final entry in physics.positions.entries) {
        final p = entry.value;
        expect(p.dx.abs(), lessThanOrEqualTo(260.01));
        expect(p.dy.abs(), lessThanOrEqualTo(220.01));
        expect(
          (p - physics.positions['self']!).distance,
          lessThanOrEqualTo(210.2),
          reason: '$count nodes: ${entry.key}',
        );
      }
    }
  });
  test('corner drag and resizing keep nodes and links in bounds', () {
    for (final count in [1, 20, 50]) {
      final anchors = <String, Offset>{
        'self': Offset.zero,
        for (var i = 0; i < count; i++)
          '$i':
              Offset(
                math.cos(i * 2 * math.pi / count),
                math.sin(i * 2 * math.pi / count),
              ) *
              150,
      };
      final physics = GraphPhysics()
        ..updateAnchors(
          anchors,
          center: Offset.zero,
          wallSize: const Size(500, 350),
          linkCenter: 'self',
          maxLinkLength: 400,
        );
      physics.drag('0', const Offset(500, 350));
      for (var i = 0; i < 120; i++) {
        physics.step(1 / 60);
      }
      final dragged = physics.positions['0']!;
      expect(dragged.dx, greaterThan(450));
      expect(dragged.dy, greaterThan(300));
      for (final point in physics.positions.values) {
        expect(
          (point - physics.positions['self']!).distance,
          lessThanOrEqualTo(400.2),
        );
      }
      physics.endDrag();
      physics.updateAnchors(
        anchors,
        center: Offset.zero,
        wallSize: const Size(220, 180),
        linkCenter: 'self',
        maxLinkLength: 240,
      );
      for (final point in physics.positions.values) {
        expect(point.dx.abs(), lessThanOrEqualTo(220));
        expect(point.dy.abs(), lessThanOrEqualTo(180));
        expect(
          (point - physics.positions['self']!).distance,
          lessThanOrEqualTo(240.2),
        );
      }
    }
  });
  test('a displaced group drifts back toward the center after release', () {
    final physics = GraphPhysics()
      ..updateAnchors(
        {'self': Offset.zero, 'other': const Offset(150, 0)},
        center: Offset.zero,
        wallSize: const Size(500, 300),
        linkCenter: 'self',
        maxLinkLength: 300,
      );
    physics.drag('self', const Offset(300, 100));
    physics.endDrag();
    final before =
        (physics.positions['self']! + physics.positions['other']!) / 2;
    for (var i = 0; i < 600; i++) {
      if (!physics.step(1 / 60)) break;
    }
    final after =
        (physics.positions['self']! + physics.positions['other']!) / 2;
    expect(after.distance, lessThan(before.distance));
  });
  test('dragged nodes push neighbours, remain inside the wall, and settle', () {
    final physics = GraphPhysics(collisionDiameter: 52)
      ..updateAnchors({
        'a': const Offset(150, 0),
        'b': const Offset(150, 140),
      }, center: Offset.zero);
    physics.drag('a', const Offset(0, 120));
    for (var i = 0; i < 20; i++) {
      physics.step(1 / 60);
    }
    expect(
      (physics.positions['b']! - const Offset(150, 140)).distance,
      greaterThan(1),
    );
    physics.endDrag();
    var moving = true;
    for (var i = 0; i < 1200 && moving; i++) {
      moving = physics.step(1 / 60);
    }
    expect(moving, isFalse);
    for (final point in physics.positions.values) {
      expect(point.dx.abs(), lessThanOrEqualTo(physics.wallRadius + .01));
      expect(point.dy.abs(), lessThanOrEqualTo(physics.wallRadius + .01));
    }
    physics.drag('a', const Offset(10000, 10000));
    expect(
      physics.positions['a']!.dx.abs(),
      lessThanOrEqualTo(physics.wallRadius + .01),
    );
    expect(
      physics.positions['a']!.dy.abs(),
      lessThanOrEqualTo(physics.wallRadius + .01),
    );
  });
  test('entering the graph gives nodes a brief initial impulse', () {
    final physics = GraphPhysics()
      ..updateAnchors({
        'self': Offset.zero,
        'other': const Offset(150, 0),
      }, center: Offset.zero);
    physics.wake(jitter: true);
    expect(
      physics.velocities.values.every((velocity) => velocity.distance > 7),
      isTrue,
    );
    for (var i = 0; i < 600; i++) {
      if (!physics.step(1 / 60)) break;
    }
    expect(physics.settlingTime, lessThan(10));
  });
}
