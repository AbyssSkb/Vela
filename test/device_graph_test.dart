import 'package:vela/device_graph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('enabling reduced motion stops ongoing graph movement', (
    tester,
  ) async {
    Widget graph(bool reduced) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: DeviceGraph(
            peers: const ['a'],
            selfName: 'Mac',
            selfLabel: 'This device',
            selfIcon: Icons.computer,
            name: (id) => id,
            icon: (_) => Icons.phone_android,
            presence: (_) => const Icon(Icons.circle),
            selected: const {},
            selecting: false,
            enabled: true,
            onSelfTap: () {},
            onTap: (_) {},
            onLongPress: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(graph(false));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(DeviceGraph));
    final peer = find.byKey(const ValueKey('peer-a'));
    final raw = tester.widget<RawGestureDetector>(
      find.ancestor(of: peer, matching: find.byType(RawGestureDetector)).first,
    );
    final dynamic factory = raw.gestures.values.single;
    final dynamic recognizer = factory.constructor();
    factory.initializer(recognizer);
    recognizer.onStart(DragStartDetails());
    recognizer.onEnd(
      DragEndDetails(
        velocity: const Velocity(pixelsPerSecond: Offset(-300, 0)),
      ),
    );
    recognizer.dispose();
    expect(state.ticker.isActive, isTrue);
    await tester.pumpWidget(graph(true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(state.ticker.isActive, isFalse);
    expect(
      state.physics.velocities.values.every(
        (dynamic velocity) => velocity == Offset.zero,
      ),
      isTrue,
    );
  });
  testWidgets(
    'scaled pointer fling uses local velocity and cancellation clears it',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceGraph(
              peers: const ['a'],
              selfName: 'Mac',
              selfLabel: 'This device',
              selfIcon: Icons.computer,
              name: (id) => id,
              icon: (_) => Icons.phone_android,
              presence: (_) => const Icon(Icons.circle),
              selected: const {},
              selecting: false,
              enabled: true,
              onSelfTap: () {},
              onTap: (_) {},
              onLongPress: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(DeviceGraph));
      expect(state.physics.screenScale, lessThan(1));
      final peer = find.byKey(const ValueKey('peer-a'));
      final raw = tester.widget<RawGestureDetector>(
        find
            .ancestor(of: peer, matching: find.byType(RawGestureDetector))
            .first,
      );
      final dynamic factory = raw.gestures.values.single;
      final dynamic recognizer = factory.constructor();
      factory.initializer(recognizer);
      recognizer.onStart(DragStartDetails());
      recognizer.onEnd(
        DragEndDetails(
          velocity: const Velocity(pixelsPerSecond: Offset(-300, 0)),
        ),
      );
      recognizer.dispose();
      final Offset velocity = state.physics.velocities['a'];
      expect(velocity.dx, closeTo(-300, .01));
      expect(velocity.distance, lessThanOrEqualTo(1200));
      await tester.pumpAndSettle();
      expect(state.ticker.isActive, isFalse);
      final gesture = await tester.startGesture(tester.getCenter(peer));
      await gesture.moveBy(const Offset(-30, 0));
      await gesture.cancel();
      expect(state.physics.velocities['a'], Offset.zero);
      await tester.pumpAndSettle();
      expect(state.ticker.isActive, isFalse);
    },
  );
  testWidgets(
    'reduced motion allows dragging without starting a ticker or fling',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: DeviceGraph(
                peers: const ['a'],
                selfName: 'Mac',
                selfLabel: 'This device',
                selfIcon: Icons.computer,
                name: (id) => id,
                icon: (_) => Icons.phone_android,
                presence: (_) => const Icon(Icons.circle),
                selected: const {},
                selecting: false,
                enabled: true,
                onSelfTap: () {},
                onTap: (_) {},
                onLongPress: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final peer = find.byKey(const ValueKey('peer-a'));
      final before = tester.getCenter(peer);
      final gesture = await tester.startGesture(before);
      await gesture.moveBy(const Offset(-25, 0));
      await tester.pump();
      final afterSlop = tester.getCenter(peer);
      await gesture.moveBy(const Offset(-15, 0));
      await tester.pump();
      expect(tester.getCenter(peer).dx - afterSlop.dx, closeTo(-15, .1));
      await gesture.cancel();
      await tester.fling(peer, const Offset(-30, 0), 1000);
      await tester.pump();
      final after = tester.getCenter(peer);
      expect((after - before).distance, greaterThan(5));
      final dynamic state = tester.state(find.byType(DeviceGraph));
      expect(state.ticker.isActive, isFalse);
      expect(state.physics.velocities['a'], Offset.zero);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getCenter(peer), after);
    },
  );
  testWidgets('node size remains stable when the device rotates', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Widget graph() => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 312,
            child: DeviceGraph(
              minimumScale: .5,
              availableHeight: 600,
              peers: const ['a'],
              selfName: 'Phone',
              selfLabel: 'This device',
              selfIcon: Icons.phone,
              name: (id) => id,
              icon: (_) => Icons.computer,
              presence: (_) => const Icon(Icons.circle),
              selected: const {},
              selecting: false,
              enabled: true,
              onSelfTap: () {},
              onTap: (_) {},
              onLongPress: (_) {},
            ),
          ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(360, 792);
    await tester.pumpWidget(graph());
    await tester.pumpAndSettle();
    final portrait = tester
        .getRect(find.byKey(const ValueKey('graph-icon-a')))
        .width;
    tester.view.physicalSize = const Size(792, 360);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              child: DeviceGraph(
                minimumScale: .5,
                availableHeight: 220,
                peers: const ['a'],
                selfName: 'Phone',
                selfLabel: 'This device',
                selfIcon: Icons.phone,
                name: (id) => id,
                icon: (_) => Icons.computer,
                presence: (_) => const Icon(Icons.circle),
                selected: const {},
                selecting: false,
                enabled: true,
                onSelfTap: () {},
                onTap: (_) {},
                onLongPress: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final landscape = tester
        .getRect(find.byKey(const ValueKey('graph-icon-a')))
        .width;
    expect(
      landscape,
      closeTo(portrait, .5),
      reason: 'Rotating the same device must not resize nodes',
    );
  });

  testWidgets(
    'few landscape nodes keep their size and use the available canvas',
    (tester) async {
      tester.view.physicalSize = const Size(792, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: tester.view.physicalSize / tester.view.devicePixelRatio,
              disableAnimations: true,
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 520,
                  height: 220,
                  child: DeviceGraph(
                    minimumScale: .5,
                    availableHeight: 220,
                    peers: const ['a'],
                    selfName: 'Mac',
                    selfLabel: 'This device',
                    selfIcon: Icons.computer,
                    name: (id) => id,
                    icon: (_) => Icons.phone,
                    presence: (_) => const Icon(Icons.circle),
                    selected: const {},
                    selecting: false,
                    enabled: true,
                    onSelfTap: () {},
                    onTap: (_) {},
                    onLongPress: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(DeviceGraph));
      expect(state.physics.screenScale, inInclusiveRange(.79, .82));
      expect(
        tester.getRect(find.byKey(const ValueKey('graph-icon-a'))).width,
        inInclusiveRange(40, 43),
      );
      expect(state.physics.wallRadiusX, greaterThan(200));
      expect(state.physics.wallRadiusY, greaterThan(50));
      final peer = find.byKey(const ValueKey('peer-a'));
      final start = tester.getCenter(peer);
      final vertical = await tester.startGesture(start);
      await vertical.moveBy(const Offset(0, -25));
      await tester.pump();
      await vertical.moveBy(const Offset(0, -25));
      await tester.pump();
      expect(tester.getCenter(peer).dy, lessThan(start.dy - 20));
      await vertical.up();
      final horizontal = await tester.startGesture(tester.getCenter(peer));
      await horizontal.moveBy(const Offset(30, 0));
      await tester.pump();
      await horizontal.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(
        tester.getRect(peer).right,
        closeTo(520, 1),
        reason: 'The node can reach the visible canvas edge',
      );
      await horizontal.up();
    },
  );

  testWidgets('vertical node drag wins over scrollable landscape viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SingleChildScrollView(
              key: const ValueKey('landscape-scroll'),
              child: DeviceGraph(
                minimumScale: .5,
                availableHeight: 180,
                peers: List.generate(20, (i) => '$i'),
                selfName: 'Mac',
                selfLabel: 'This device',
                selfIcon: Icons.computer,
                name: (id) => id,
                icon: (_) => Icons.phone,
                presence: (_) => const Icon(Icons.circle),
                selected: const {},
                selecting: false,
                enabled: true,
                onSelfTap: () {},
                onTap: (_) {},
                onLongPress: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final node = find.byKey(const ValueKey('graph-icon-self'));
    final dynamic state = tester.state(find.byType(DeviceGraph));
    final scroll = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('landscape-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(scroll.maxScrollExtent, greaterThan(0));
    final horizontal = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('graph-horizontal-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(horizontal.maxScrollExtent, greaterThan(0));
    for (final delta in [
      const Offset(0, -60),
      const Offset(60, 0),
      const Offset(-45, 45),
    ]) {
      final before = state.physics.positions['\u0000self'] as Offset;
      final scrollBefore = scroll.pixels, horizontalBefore = horizontal.pixels;
      final gesture = await tester.startGesture(tester.getCenter(node));
      await gesture.moveBy(delta * .4);
      await tester.pump();
      await gesture.moveBy(delta * .6);
      await tester.pump();
      final movement =
          (state.physics.positions['\u0000self'] as Offset) - before;
      if (delta.dx != 0) {
        expect(
          movement.dx * delta.dx.sign,
          greaterThan(10),
          reason: 'Horizontal movement must reach the node',
        );
      }
      if (delta.dy != 0) {
        expect(
          movement.dy * delta.dy.sign,
          greaterThan(10),
          reason: 'Vertical movement must reach the node',
        );
      }
      expect(
        scroll.pixels,
        closeTo(scrollBefore, .1),
        reason: 'The vertical parent must not steal the drag',
      );
      expect(
        horizontal.pixels,
        closeTo(horizontalBefore, .1),
        reason: 'The horizontal parent must not steal the drag',
      );
      await gesture.up();
    }
  });

  testWidgets('dragging the canvas at its original scale does not move it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceGraph(
            peers: const ['a', 'b'],
            selfName: 'Mac',
            selfLabel: 'This device',
            selfIcon: Icons.computer,
            name: (id) => id,
            icon: (_) => Icons.phone_android,
            presence: (_) => const Icon(Icons.circle),
            selected: const {},
            selecting: false,
            enabled: true,
            onSelfTap: () {},
            onTap: (_) {},
            onLongPress: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getCenter(
      find.byKey(const ValueKey('graph-icon-self')),
    );
    await tester.dragFrom(const Offset(20, 20), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byKey(const ValueKey('graph-icon-self'))),
      before,
    );
    expect(find.byType(InteractiveViewer), findsNothing);
  });
  testWidgets('node names have transparent backgrounds', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceGraph(
            peers: const ['a'],
            selfName: 'Mac',
            selfLabel: 'This device',
            selfIcon: Icons.computer,
            name: (_) => 'Phone',
            icon: (_) => Icons.phone,
            presence: (_) => const Icon(Icons.circle),
            selected: const {},
            selecting: false,
            enabled: true,
            onSelfTap: () {},
            onTap: (_) {},
            onLongPress: (_) {},
          ),
        ),
      ),
    );
    final label = find.text('Phone');
    final background = tester.widget<Container>(
      find.ancestor(of: label, matching: find.byType(Container)).first,
    );
    expect(background.decoration, isNull);
  });

  testWidgets('nodes use the available height without clipping their labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceGraph(
            availableHeight: 600,
            peers: const ['a'],
            selfName: 'This device has a long name',
            selfLabel: 'This device',
            selfIcon: Icons.computer,
            name: (_) => 'A very long device name',
            icon: (_) => Icons.phone_android,
            presence: (_) => const Icon(Icons.circle),
            selected: const {},
            selecting: false,
            enabled: true,
            onSelfTap: () {},
            onTap: (_) {},
            onLongPress: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final peer = find.byKey(const ValueKey('peer-a'));
    final gesture = await tester.startGesture(tester.getCenter(peer));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveTo(const Offset(160, 350));
    await tester.pump();
    await gesture.moveTo(const Offset(160, 570));
    await tester.pump();
    final rect = tester.getRect(peer);
    expect(rect.bottom, lessThanOrEqualTo(600));
    expect(rect.top, greaterThan(400));
    await gesture.moveTo(const Offset(5, 300));
    await tester.pump();
    expect(tester.getRect(peer).left, greaterThanOrEqualTo(0));
    await gesture.moveTo(const Offset(315, 300));
    await tester.pump();
    expect(tester.getRect(peer).right, lessThanOrEqualTo(320));
    await gesture.up();
  });
  testWidgets(
    'graph centers this device and preserves tap and long-press actions',
    (tester) async {
      tester.view.physicalSize = const Size(720, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      String? tapped, held;
      var selfTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceGraph(
              peers: const ['a', 'b', 'c', 'd'],
              selfName: 'Mac',
              selfLabel: 'This device',
              selfIcon: Icons.computer,
              name: (id) => 'Device $id',
              icon: (_) => Icons.phone_android,
              presence: (_) => const Icon(Icons.circle, size: 12),
              selected: const {},
              selecting: false,
              enabled: true,
              onSelfTap: () => selfTapped = true,
              onTap: (id) => tapped = id,
              onLongPress: (id) => held = id,
            ),
          ),
        ),
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('graph-self'))).dx,
        closeTo(360, 1),
      );
      final link = find
          .descendant(
            of: find.byKey(const ValueKey('link-a')),
            matching: find.byType(CustomPaint),
          )
          .first;
      final paintBox = tester.renderObject<RenderBox>(link);
      final dynamic painter = tester.widget<CustomPaint>(link).painter;
      expect(
        (paintBox.localToGlobal(painter.center as Offset) -
                tester.getCenter(find.byKey(const ValueKey('graph-icon-self'))))
            .distance,
        lessThan(.1),
      );
      expect(
        (paintBox.localToGlobal(painter.point as Offset) -
                tester.getCenter(find.byKey(const ValueKey('graph-icon-a'))))
            .distance,
        lessThan(.1),
      );
      await tester.tap(find.byKey(const ValueKey('graph-self')));
      await tester.tap(find.byKey(const ValueKey('peer-a')));
      await tester.longPress(find.byKey(const ValueKey('peer-b')));
      expect(selfTapped, isTrue);
      expect(tapped, 'a');
      expect(held, 'b');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty selection mode still shows selection controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceGraph(
            peers: const ['a'],
            selfName: 'Mac',
            selfLabel: 'This device',
            selfIcon: Icons.computer,
            name: (id) => id,
            icon: (_) => Icons.phone_android,
            presence: (_) => const Icon(Icons.circle),
            selected: const {},
            selecting: true,
            enabled: true,
            onSelfTap: () {},
            onTap: (_) {},
            onLongPress: (_) {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
    expect(
      tester.widget<InkWell>(find.byKey(const ValueKey('graph-self'))).onTap,
      isNull,
    );
  });

  testWidgets('many devices fit a narrow graph without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final peers = List.generate(20, (index) => '$index');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DeviceGraph(
              peers: peers,
              selfName: 'Mac',
              selfLabel: 'This device',
              selfIcon: Icons.computer,
              name: (id) => 'A long device name $id',
              icon: (_) => Icons.phone_android,
              presence: (_) => const Icon(Icons.circle, size: 12),
              selected: const {'3'},
              selecting: true,
              enabled: true,
              onSelfTap: () {},
              onTap: (_) {},
              onLongPress: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('peer-3')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large scrollable graphs keep device targets usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final count in [20, 50]) {
      String? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: SingleChildScrollView(
                key: const ValueKey('graph-vertical-scroll'),
                child: DeviceGraph(
                  key: ValueKey('graph-$count'),
                  minimumScale: .5,
                  availableHeight: 260,
                  peers: List.generate(count, (i) => '$i'),
                  selfName: 'Mac',
                  selfLabel: 'This device',
                  selfIcon: Icons.computer,
                  name: (id) => 'Device $id',
                  icon: (_) => Icons.phone_android,
                  presence: (_) => const Icon(Icons.circle),
                  selected: const {},
                  selecting: false,
                  enabled: true,
                  onSelfTap: () {},
                  onTap: (id) => tapped = id,
                  onLongPress: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final horizontal = find.descendant(
        of: find.byKey(const ValueKey('graph-horizontal-scroll')),
        matching: find.byType(Scrollable),
      );
      final vertical = find
          .descendant(
            of: find.byKey(const ValueKey('graph-vertical-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      expect(
        tester.state<ScrollableState>(horizontal).position.maxScrollExtent,
        greaterThan(0),
      );
      expect(
        tester.state<ScrollableState>(vertical).position.maxScrollExtent,
        greaterThan(0),
      );
      final self = tester.getCenter(find.byKey(const ValueKey('graph-self')));
      expect(self.dx, closeTo(160, 2));
      expect(self.dy, inInclusiveRange(100, 200));
      final peer = find.byKey(const ValueKey('peer-0'));
      expect(tester.getRect(peer).width, greaterThanOrEqualTo(48));
      final horizontalPosition = tester
          .state<ScrollableState>(horizontal)
          .position;
      final beforeDrag = horizontalPosition.pixels;
      await tester.dragFrom(const Offset(10, 280), const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(horizontalPosition.pixels, greaterThan(beforeDrag));
      await tester.ensureVisible(peer);
      await tester.pumpAndSettle();
      await tester.tap(peer);
      expect(tapped, '0');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('small graph does not scroll away a preceding header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: SizedBox(key: ValueKey('graph-header'), height: 100),
              ),
              SliverToBoxAdapter(
                child: DeviceGraph(
                  minimumScale: .5,
                  availableHeight: 260,
                  peers: const ['a'],
                  selfName: 'Mac',
                  selfLabel: 'This device',
                  selfIcon: Icons.computer,
                  name: (id) => id,
                  icon: (_) => Icons.phone_android,
                  presence: (_) => const Icon(Icons.circle),
                  selected: const {},
                  selecting: false,
                  enabled: true,
                  onSelfTap: () {},
                  onTap: (_) {},
                  onLongPress: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('graph-header'))).dy, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large graph can scroll back to its preceding controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: SizedBox(key: ValueKey('graph-header'), height: 100),
                ),
                SliverToBoxAdapter(
                  child: DeviceGraph(
                    minimumScale: .5,
                    availableHeight: 260,
                    peers: List.generate(50, (i) => '$i'),
                    selfName: 'Mac',
                    selfLabel: 'This device',
                    selfIcon: Icons.computer,
                    name: (id) => id,
                    icon: (_) => Icons.phone_android,
                    presence: (_) => const Icon(Icons.circle),
                    selected: const {},
                    selecting: false,
                    enabled: true,
                    onSelfTap: () {},
                    onTap: (_) {},
                    onLongPress: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byKey(const ValueKey('graph-self'))).dy,
      inInclusiveRange(100, 200),
    );
    await tester.dragFrom(const Offset(10, 100), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('graph-header'))).dy, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a growing graph follows its center until the user scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Widget graph(int count) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: SingleChildScrollView(
            key: const ValueKey('outer-scroll'),
            child: DeviceGraph(
              minimumScale: .5,
              availableHeight: 260,
              peers: List.generate(count, (i) => '$i'),
              selfName: 'Mac',
              selfLabel: 'This device',
              selfIcon: Icons.computer,
              name: (id) => id,
              icon: (_) => Icons.phone_android,
              presence: (_) => const Icon(Icons.circle),
              selected: const {},
              selecting: false,
              enabled: true,
              onSelfTap: () {},
              onTap: (_) {},
              onLongPress: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(graph(20));
    await tester.pumpAndSettle();
    await tester.pumpWidget(graph(50));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byKey(const ValueKey('graph-self'))).dy,
      inInclusiveRange(100, 200),
    );
    final outer = find
        .descendant(
          of: find.byKey(const ValueKey('outer-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(outer).position;
    await tester.dragFrom(const Offset(10, 100), const Offset(0, -80));
    await tester.pumpAndSettle();
    final userOffset = position.pixels;
    await tester.pumpWidget(graph(55));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(userOffset, .1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('device nodes do not overlap across widths and device counts', (
    tester,
  ) async {
    for (final width in [320.0, 720.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      for (final count in [1, 2, 6, 12, 20, 50]) {
        final peers = List.generate(count, (i) => '$i');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DeviceGraph(
                  peers: peers,
                  selfName: 'Mac',
                  selfLabel: 'This device',
                  selfIcon: Icons.computer,
                  name: (id) => 'Device $id with a long name',
                  icon: (_) => Icons.phone_android,
                  presence: (_) => const Icon(Icons.circle, size: 12),
                  selected: const {},
                  selecting: false,
                  enabled: true,
                  onSelfTap: () {},
                  onTap: (_) {},
                  onLongPress: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final nodes = [
          find.byKey(const ValueKey('graph-self')),
          for (final id in peers) find.byKey(ValueKey('peer-$id')),
        ];
        final rects = nodes.map(tester.getRect).toList();
        final icons = [
          tester.getRect(find.byKey(const ValueKey('graph-icon-self'))),
          for (final id in peers)
            tester.getRect(find.byKey(ValueKey('graph-icon-$id'))),
        ];
        final labels = [
          tester.getRect(find.text('Mac')),
          for (final id in peers)
            tester.getRect(find.text('Device $id with a long name')),
        ];
        for (var a = 0; a < rects.length; a++) {
          expect(rects[a].left, greaterThanOrEqualTo(0));
          expect(rects[a].right, lessThanOrEqualTo(width));
          for (var b = a + 1; b < rects.length; b++) {
            expect(
              (icons[a].center - icons[b].center).distance,
              greaterThanOrEqualTo(icons[a].width - .01),
            );
            expect(
              labels[a].overlaps(labels[b]),
              isFalse,
              reason: '$count devices at $width px: labels $a and $b overlap',
            );
            expect(
              labels[a].overlaps(icons[b]) || labels[b].overlaps(icons[a]),
              isFalse,
              reason: '$count devices at $width px: a label covers an icon',
            );
          }
        }
        expect(tester.takeException(), isNull);
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('only a newly added node animates in', (tester) async {
    Widget graph(List<String> peers) => MaterialApp(
      home: Scaffold(
        body: DeviceGraph(
          peers: peers,
          selfName: 'Mac',
          selfLabel: 'This device',
          selfIcon: Icons.computer,
          name: (id) => id,
          icon: (_) => Icons.phone_android,
          presence: (_) => const Icon(Icons.circle),
          selected: const {},
          selecting: false,
          enabled: true,
          onSelfTap: () {},
          onTap: (_) {},
          onLongPress: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(graph(['a']));
    await tester.pumpAndSettle();
    await tester.pumpWidget(graph(['a', 'b']));
    final a = find
        .descendant(
          of: find.byKey(const ValueKey('node-a')),
          matching: find.byType(Opacity),
        )
        .first;
    final b = find
        .descendant(
          of: find.byKey(const ValueKey('node-b')),
          matching: find.byType(Opacity),
        )
        .first;
    expect(tester.widget<Opacity>(a).opacity, 1);
    expect(tester.widget<Opacity>(b).opacity, 0);
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(b).opacity, 1);
  });

  testWidgets(
    'graph fills the remaining viewport and scrolls for many devices',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      Widget graph(int count) => MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 200)),
              SliverLayoutBuilder(
                builder: (context, constraints) => SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          (constraints.viewportMainAxisExtent -
                                  constraints.precedingScrollExtent)
                              .clamp(0.0, double.infinity),
                    ),
                    child: Center(
                      child: DeviceGraph(
                        peers: List.generate(count, (i) => '$i'),
                        selfName: 'Mac',
                        selfLabel: 'This device',
                        selfIcon: Icons.computer,
                        name: (id) => id,
                        icon: (_) => Icons.phone_android,
                        presence: (_) => const Icon(Icons.circle),
                        selected: const {},
                        selecting: false,
                        enabled: true,
                        onSelfTap: () {},
                        onTap: (_) {},
                        onLongPress: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(graph(1));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(const ValueKey('graph-self'))).dy,
        closeTo(505, 20),
      );
      expect(find.byKey(const ValueKey('device-graph')), findsOneWidget);
      await tester.pumpWidget(graph(20));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dragging a node moves neighbours and settles', (tester) async {
    tester.view.physicalSize = const Size(720, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceGraph(
            peers: const ['a', 'b', 'c', 'd'],
            selfName: 'Mac',
            selfLabel: 'This device',
            selfIcon: Icons.computer,
            name: (id) => id,
            icon: (_) => Icons.phone_android,
            presence: (_) => const Icon(Icons.circle),
            selected: const {},
            selecting: false,
            enabled: true,
            onSelfTap: () {},
            onTap: (_) {},
            onLongPress: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final a = find.byKey(const ValueKey('peer-a'));
    final b = find.byKey(const ValueKey('peer-b'));
    final self = find.byKey(const ValueKey('graph-self'));
    final startA = tester.getCenter(a),
        startB = tester.getCenter(b),
        startSelf = tester.getCenter(self);
    final gesture = await tester.startGesture(startA);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveTo(startB + const Offset(40, -30));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(startB + const Offset(5, 0));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    expect((tester.getCenter(a) - startA).distance, greaterThan(10));
    expect((tester.getCenter(b) - startB).distance, greaterThan(.1));
    expect((tester.getCenter(self) - startSelf).distance, greaterThan(.1));
    await gesture.up();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect((tester.getCenter(a) - startA).distance, greaterThan(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging nodes apart works with and without reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Widget graph(bool reduced, int count) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: SingleChildScrollView(
            child: DeviceGraph(
              minimumScale: .5,
              availableHeight: 700,
              peers: List.generate(count, (i) => '$i'),
              selfName: 'Mac',
              selfLabel: 'This device',
              selfIcon: Icons.computer,
              name: (id) => id,
              icon: (_) => Icons.phone_android,
              presence: (_) => const Icon(Icons.circle, size: 12),
              selected: const {},
              selecting: false,
              enabled: true,
              onSelfTap: () {},
              onTap: (_) {},
              onLongPress: (_) {},
            ),
          ),
        ),
      ),
    );
    void expectSeparate(int count) {
      final icons = [
        tester.getRect(find.byKey(const ValueKey('graph-icon-self'))),
        for (var i = 0; i < count; i++)
          tester.getRect(find.byKey(ValueKey('graph-icon-$i'))),
      ];
      for (var i = 0; i < icons.length; i++) {
        for (var j = i + 1; j < icons.length; j++) {
          expect(
            (icons[i].center - icons[j].center).distance,
            greaterThanOrEqualTo(icons[i].width - .01),
            reason: 'node icons $i and $j overlap',
          );
        }
      }
    }

    for (final reduced in [false, true]) {
      await tester.pumpWidget(graph(reduced, 4));
      await tester.pumpAndSettle();
      final peer = find.byKey(const ValueKey('peer-0'));
      final self = find.byKey(const ValueKey('graph-self'));
      final gesture = await tester.startGesture(tester.getCenter(peer));
      await gesture.moveBy(const Offset(-25, 0));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(self));
      await tester.pump(const Duration(milliseconds: 16));
      expectSeparate(4);
      await gesture.up();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      expectSeparate(4);
      await tester.pumpWidget(graph(reduced, 5));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      expectSeparate(5);
      tester.view.physicalSize = const Size(320, 640);
      await tester.pump();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      expectSeparate(5);
      await tester.pumpWidget(graph(reduced, 3));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      expectSeparate(3);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.physicalSize = const Size(800, 800);
    }
  });
}
