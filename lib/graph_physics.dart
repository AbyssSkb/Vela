import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class GraphPhysics {
  GraphPhysics({this.collisionDiameter});
  final double? collisionDiameter;
  final Map<String, Offset> anchors = {};
  final Map<String, Offset> positions = {};
  final Map<String, Offset> velocities = {};
  String? dragging;
  Offset center = Offset.zero;
  double wallRadius = 0;
  double wallRadiusX = 0, wallRadiusY = 0;
  String? linkCenter;
  double maxLinkLength = double.infinity;
  final random = math.Random();
  double settlingTime = 0;
  double stableTime = 0;
  double screenScale = 1;

  void wake({bool jitter = false}) {
    settlingTime = 0;
    stableTime = 0;
    if (jitter) {
      for (final id in positions.keys) {
        final angle = random.nextDouble() * math.pi * 2;
        velocities[id] = Offset(math.cos(angle), math.sin(angle)) * 8;
      }
    }
  }

  void updateAnchors(
    Map<String, Offset> next, {
    required Offset center,
    Size? wallSize,
    String? linkCenter,
    double? maxLinkLength,
    double screenScale = 1,
  }) {
    this.center = center;
    wallRadius =
        next.values.fold<double>(
          0,
          (radius, point) => math.max(radius, (point - center).distance),
        ) +
        12;
    wallRadiusX = wallSize?.width ?? wallRadius;
    wallRadiusY = wallSize?.height ?? wallRadius;
    this.linkCenter = linkCenter;
    this.maxLinkLength = maxLinkLength ?? double.infinity;
    this.screenScale = screenScale;
    positions.removeWhere((id, _) => !next.containsKey(id));
    velocities.removeWhere((id, _) => !next.containsKey(id));
    for (final entry in next.entries) {
      if (!positions.containsKey(entry.key) ||
          (dragging == null &&
              positions[entry.key] == anchors[entry.key] &&
              (velocities[entry.key] ?? Offset.zero) == Offset.zero)) {
        positions[entry.key] = entry.value;
      } else if (dragging == null &&
          anchors.containsKey(entry.key) &&
          anchors[entry.key] != entry.value) {
        positions[entry.key] =
            positions[entry.key]! + entry.value - anchors[entry.key]!;
      }
      velocities.putIfAbsent(entry.key, () => Offset.zero);
    }
    anchors
      ..clear()
      ..addAll(next);
    for (final id in positions.keys) {
      positions[id] = _insideWall(positions[id]!);
    }
    _constrainLinks();
    if (!_separateNodes()) {
      for (final entry in anchors.entries) {
        positions[entry.key] = _insideWall(entry.value);
        velocities[entry.key] = Offset.zero;
      }
    }
  }

  void drag(String id, Offset delta) {
    if (!positions.containsKey(id)) return;
    final before = Map<String, Offset>.of(positions);
    dragging = id;
    wake();
    positions[id] = _insideWall(positions[id]! + delta);
    velocities[id] = Offset.zero;
    _constrainLinks();
    if (!_separateNodes()) {
      positions
        ..clear()
        ..addAll(before);
    }
  }

  Offset _insideWall(Offset point) {
    return Offset(
      point.dx.clamp(center.dx - wallRadiusX, center.dx + wallRadiusX),
      point.dy.clamp(center.dy - wallRadiusY, center.dy + wallRadiusY),
    );
  }

  void _constrainLinks() {
    final hub = linkCenter;
    if (hub == null || !positions.containsKey(hub)) return;
    for (var iteration = 0; iteration < 100; iteration++) {
      var maxExcess = 0.0;
      for (final id in positions.keys) {
        if (id == hub) continue;
        final delta = positions[id]! - positions[hub]!;
        final excess = delta.distance - maxLinkLength;
        if (excess <= 0) continue;
        maxExcess = math.max(maxExcess, excess);
        final correction = delta / delta.distance * excess;
        if (dragging == id) {
          final before = positions[hub]!;
          positions[hub] = _insideWall(before + correction);
          positions[id] = _insideWall(
            positions[id]! - (correction - (positions[hub]! - before)),
          );
        } else if (dragging == hub) {
          final before = positions[id]!;
          positions[id] = _insideWall(before - correction);
          positions[hub] = _insideWall(
            positions[hub]! + (correction + (positions[id]! - before)),
          );
        } else {
          positions[id] = _insideWall(positions[id]! - correction / 2);
          positions[hub] = _insideWall(positions[hub]! + correction / 2);
        }
      }
      if (maxExcess < .1) break;
    }
    for (final id in positions.keys) {
      if (id == hub) continue;
      final delta = positions[id]! - positions[hub]!;
      if (delta.distance > maxLinkLength) {
        positions[id] =
            positions[hub]! + delta / delta.distance * maxLinkLength;
      }
    }
  }

  bool _separateNodes() {
    final diameter = collisionDiameter;
    if (diameter == null) return true;
    final ids = positions.keys.toList();
    for (var iteration = 0; iteration < 80; iteration++) {
      var overlap = false;
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final a = ids[i], b = ids[j];
          final delta = positions[a]! - positions[b]!;
          final distance = delta.distance;
          final overlapDistance = diameter - distance;
          if (overlapDistance <= 0) continue;
          overlap = true;
          final direction = distance > 0.0001
              ? delta / distance
              : const Offset(1, 0);
          final correction = direction * (overlapDistance + .001);
          final share = dragging == a
              ? 0.0
              : dragging == b
              ? 1.0
              : .5;
          final oldA = positions[a]!, oldB = positions[b]!;
          positions[a] = _insideWall(oldA + correction * share);
          positions[b] = _insideWall(
            oldB - (correction - (positions[a]! - oldA)),
          );
          positions[a] = _insideWall(
            positions[a]! +
                correction +
                (positions[b]! - oldB) -
                (positions[a]! - oldA),
          );
        }
      }
      if (!overlap) return true;
      _constrainLinks();
    }
    return false;
  }

  bool step(double seconds) {
    var remaining = seconds.clamp(0.0, .1);
    var moving = true;
    while (remaining > 0 && moving) {
      final dt = math.min(remaining, 1 / 60);
      moving = _step(dt);
      remaining -= dt;
    }
    return moving;
  }

  bool _step(double dt) {
    final before = Map<String, Offset>.of(positions);
    if (dragging == null) settlingTime += dt;
    // Fade recentering so the layout can settle without an abrupt stop.
    final forceScale = dragging != null
        ? 1.0
        : ((5.5 - settlingTime) / 3).clamp(0.0, 1.0);
    final forces = <String, Offset>{};
    final centroid = positions.isEmpty
        ? center
        : positions.values.fold(Offset.zero, (sum, point) => sum + point) /
              positions.length.toDouble();
    final centerPull = dragging == null
        ? (center - centroid) * (2.5 * forceScale)
        : Offset.zero;
    for (final id in positions.keys) {
      final delta = positions[id]! - center;
      final wall = Offset(
        delta.dx.abs() > wallRadiusX - 2
            ? -delta.dx.sign * (delta.dx.abs() - wallRadiusX + 2) * 60
            : 0,
        delta.dy.abs() > wallRadiusY - 2
            ? -delta.dy.sign * (delta.dy.abs() - wallRadiusY + 2) * 60
            : 0,
      );
      forces[id] = -velocities[id]! * 9 + wall * forceScale + centerPull;
    }
    final ids = positions.keys.toList();
    if (collisionDiameter case final diameter?) {
      final range = diameter * 1.5;
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final a = ids[i], b = ids[j];
          final delta = positions[a]! - positions[b]!;
          final distance = delta.distance;
          if (distance == 0 || distance >= range) continue;
          final push = delta / distance * ((range - distance) * 45);
          forces[a] = forces[a]! + push;
          forces[b] = forces[b]! - push;
        }
      }
    }
    final hub = linkCenter;
    if (hub != null && positions.containsKey(hub) && anchors.containsKey(hub)) {
      for (final id in ids) {
        if (id == hub || !anchors.containsKey(id)) continue;
        final delta = positions[id]! - positions[hub]!;
        final distance = delta.distance;
        final rest = (anchors[id]! - anchors[hub]!).distance;
        if (distance <= rest || distance == 0) continue;
        final direction = delta / distance;
        final relativeSpeed =
            (velocities[id]! - velocities[hub]!).dx * direction.dx +
            (velocities[id]! - velocities[hub]!).dy * direction.dy;
        final pull =
            direction * math.max(0, (distance - rest) * 12 + relativeSpeed * 2);
        forces[id] = forces[id]! - pull;
        forces[hub] = forces[hub]! + pull;
      }
    }
    for (final id in ids) {
      if (id == dragging) continue;
      var velocity = velocities[id]! + forces[id]! * dt;
      var position = positions[id]! + velocity * dt;
      final bounded = _insideWall(position);
      if (bounded.dx != position.dx) velocity = Offset(0, velocity.dy);
      if (bounded.dy != position.dy) velocity = Offset(velocity.dx, 0);
      position = bounded;
      positions[id] = position;
      velocities[id] = velocity;
    }
    _constrainLinks();
    if (!_separateNodes()) {
      positions
        ..clear()
        ..addAll(before);
      for (final id in ids) {
        velocities[id] = Offset.zero;
      }
    }
    final maxMovement = ids.fold<double>(
      0,
      (value, id) => math.max(value, (positions[id]! - before[id]!).distance),
    );
    if (dragging == null && dt > 0 && maxMovement / dt * screenScale < 1.5) {
      stableTime += dt;
    } else {
      stableTime = 0;
    }
    if (stableTime >= .25) {
      for (final id in ids) {
        velocities[id] = Offset.zero;
      }
      return false;
    }
    return true;
  }

  void endDrag({Offset velocity = Offset.zero}) {
    final id = dragging;
    if (id != null && velocities.containsKey(id)) {
      final speed = velocity.distance;
      velocities[id] = !speed.isFinite
          ? Offset.zero
          : speed > 1200
          ? velocity * (1200 / speed)
          : velocity;
    }
    wake();
    dragging = null;
  }

  void stop() {
    for (final id in velocities.keys) {
      velocities[id] = Offset.zero;
    }
  }

  double get maxDisplacement => positions.entries.fold(
    0,
    (max, entry) => math.max(max, (entry.value - anchors[entry.key]!).distance),
  );
}
