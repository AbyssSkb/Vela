import 'dart:io';
import 'dart:ui' as ui;

import 'package:vela/device_graph.dart';
import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:vela/main.dart';
import 'package:vela/peer_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart' as fakes;
import 'support/home_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first launch offers both sides of pairing', (tester) async {
    await withHomeTestEnvironment(
      tester,
      devices: PeerState(),
      api: fakes.FakeRustApi(fakes.FakeNode()),
      run: (_) async {
        tester.view.physicalSize = const Size(320, 640);
        await tester.pumpWidget(
          const VelaApp(
            profile: 'test',
            initialLanguage: 'en',
            initialAppearance: 'dark',
            initialDiagnosticsEnabled: false,
          ),
        );
        final add = find.byKey(const ValueKey('add-device'));
        await waitForHome(tester, () => add.evaluate().isNotEmpty);
        final showCode = find.text('Show my QR code');
        expect(add.hitTestable(), findsOneWidget);
        expect(showCode.hitTestable(), findsOneWidget);
        await tester.tap(showCode);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('device-id')), findsOneWidget);
        expect(find.text('Copy device code'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('peer-id')), findsOneWidget);
      },
    );
  });

  testWidgets('device details can be scrolled in a small window', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await withHomeTestEnvironment(
      tester,
      devices: PeerState(
        peers: {fakes.peerId: 'Phone'},
        aliases: {fakes.peerId: 'Personal phone with a longer alias'},
      ),
      api: fakes.FakeRustApi(fakes.FakeNode()),
      run: (_) async {
        tester.view.physicalSize = const Size(320, 480);
        await tester.pumpWidget(
          const VelaApp(
            profile: 'test',
            initialLanguage: 'en',
            initialAppearance: 'dark',
            initialDiagnosticsEnabled: false,
          ),
        );
        final device = find.byKey(const ValueKey('peer-${fakes.peerId}'));
        await waitForHome(tester, () => device.evaluate().isNotEmpty);
        await tester.ensureVisible(device);
        await tester.tap(device);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);

        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        final remove = find.text('Remove device');
        await tester.scrollUntilVisible(
          remove,
          120,
          scrollable: find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pump();
        expect(remove.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(remove);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          find.widgetWithText(FilledButton, 'Remove').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('five actions remain readable when the layout changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Widget layout(bool wide) => MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(
          child: HomeResponsiveLayout(
            wide: wide,
            actions: [
              for (var i = 0; i < 5; i++)
                FilledButton(
                  key: ValueKey('action-$i'),
                  onPressed: () {},
                  child: Text('Action $i'),
                ),
            ],
            devices: const SizedBox(key: ValueKey('layout-devices')),
          ),
        ),
      ),
    );
    await tester.pumpWidget(layout(false));
    final compact = [
      for (var i = 0; i < 5; i++)
        tester.getRect(find.byKey(ValueKey('action-$i'))),
    ];
    expect(compact.every((rect) => rect.width >= 90), isTrue);
    expect(compact[3].top, greaterThan(compact[0].bottom));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('layout-devices'))).dy,
      greaterThan(compact[3].bottom),
    );
    await tester.pumpWidget(layout(true));
    await tester.pumpAndSettle();
    final wide = [
      for (var i = 0; i < 5; i++)
        tester.getRect(find.byKey(ValueKey('action-$i'))),
    ];
    for (var i = 1; i < wide.length; i++) {
      expect(wide[i].top, greaterThanOrEqualTo(wide[i - 1].bottom));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('five landscape actions fit and remain tappable', (tester) async {
    tester.view.physicalSize = const Size(792, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 24, bottom: 20),
          ),
          child: SafeArea(
            child: Scaffold(
              body: Column(
                children: [
                  const SizedBox(height: 84),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: HomeResponsiveLayout(
                        wide: true,
                        actions: [
                          for (var i = 0; i < 5; i++)
                            FilledButton(
                              key: ValueKey('landscape-action-$i'),
                              onPressed: () => tapped = i,
                              child: Text('Action $i'),
                            ),
                        ],
                        devices: const SizedBox(
                          key: ValueKey('landscape-devices'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final area = tester.getRect(
      find.byKey(const ValueKey('landscape-devices')),
    );
    final rects = [
      for (var i = 0; i < 5; i++)
        tester.getRect(find.byKey(ValueKey('landscape-action-$i'))),
    ];
    expect(
      rects.every((rect) => rect.width >= 110 && rect.width <= 150),
      isTrue,
      reason: 'Wide actions should fit their contents in one column',
    );
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].top, greaterThanOrEqualTo(rects[i - 1].bottom));
    }
    expect(
      (rects.first.top + rects.last.bottom) / 2,
      closeTo(area.center.dy, 1),
      reason: 'The action column is vertically centered',
    );
    for (var i = 0; i < rects.length; i++) {
      expect(rects[i].bottom, lessThanOrEqualTo(340));
      expect(rects[i].right, lessThanOrEqualTo(area.left));
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse);
      }
      await tester.tap(find.byKey(ValueKey('landscape-action-$i')));
      expect(tapped, i);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'five actions remain visible and separate during short landscape transition',
    (tester) async {
      tester.view.physicalSize = const Size(792, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      Widget layout(bool wide) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 232,
            child: HomeResponsiveLayout(
              wide: wide,
              actions: [
                for (var i = 0; i < 5; i++)
                  FilledButton(
                    key: ValueKey('short-action-$i'),
                    onPressed: () {},
                    child: Text('Action $i'),
                  ),
              ],
              devices: const SizedBox(key: ValueKey('short-devices')),
            ),
          ),
        ),
      );
      await tester.pumpWidget(layout(false));
      await tester.pumpWidget(layout(true));
      for (var frame = 0; frame < 17; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final rects = [
          for (var i = 0; i < 5; i++)
            tester.getRect(find.byKey(ValueKey('short-action-$i'))),
        ];
        final devices = tester.getRect(
          find.byKey(const ValueKey('short-devices')),
        );
        for (var i = 0; i < rects.length; i++) {
          expect(
            rects[i].bottom,
            lessThanOrEqualTo(232.01),
            reason: 'Action $i leaves the viewport during frame $frame',
          );
          expect(rects[i].overlaps(devices), isFalse);
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse);
          }
        }
      }
    },
  );

  testWidgets(
    'home adapts to viewport size and keeps device view and selection on resize',
    (tester) async {
      final node = fakes.FakeNode();
      final devices = PeerState(
        peers: {
          fakes.peerId: 'Phone',
          'c' * 64: 'Work Mac',
          'd' * 64: 'Tablet',
          'e' * 64: 'Laptop',
        },
        types: {
          fakes.peerId: 'mobile',
          'c' * 64: 'desktop',
          'd' * 64: 'tablet',
          'e' * 64: 'desktop',
        },
      );
      Future<void> verifyLayout(Directory _) async {
        final captureKey = GlobalKey();
        final captureDirectory = Platform.environment['VELA_UI_CAPTURE_DIR'];
        final fonts = Platform.environment['VELA_UI_CAPTURE_FONT_DIR'];
        if (captureDirectory != null && fonts != null) {
          await tester.runAsync(() async {
            for (final (family, file) in [
              ('Roboto', 'Roboto-Regular.ttf'),
              ('MaterialIcons', 'MaterialIcons-Regular.otf'),
            ]) {
              final loader = FontLoader(family)
                ..addFont(
                  File('$fonts/$file')
                      .readAsBytes()
                      .then((bytes) => bytes.buffer.asByteData()),
                );
              await loader.load();
            }
          });
        }

        Future<void> capture(String name) async {
          if (captureDirectory == null) return;
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File('$captureDirectory/$name.png')
                .writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
          });
        }

        Widget home({double scale = 1, bool animations = false}) =>
            RepaintBoundary(
              key: captureKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  useMaterial3: true,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xff5367ca),
                  ),
                  scaffoldBackgroundColor: const Color(0xfff8f9fd),
                  fontFamily: fonts == null ? null : 'Roboto',
                ),
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: !animations,
                  ),
                  child: child!,
                ),
                home: HomePage(
                  profile: 'test',
                  language: 'en',
                  appearance: 'light',
                  changeSetting: (_, _) async {},
                  diagnosticsEnabled: false,
                  changeDiagnosticsEnabled: (_) async {},
                ),
              ),
            );
        Future<void> resize(Size size) async {
          tester.view.physicalSize = size;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
        }

        final device = find.byKey(const ValueKey('peer-${fakes.peerId}'));
        final file = find.byKey(const ValueKey('send-file'));
        final devices = find.byKey(const ValueKey('home-devices'));
        await resize(const Size(390, 844));
        await tester.pumpWidget(home());
        await waitForHome(tester, () => device.evaluate().isNotEmpty);
        expect(file, findsOneWidget);
        expect(find.byKey(const ValueKey('home-more')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('transfer-history')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('select-devices')), findsNothing);
        expect(
          tester.getRect(find.byKey(const ValueKey('refresh-devices'))).left -
              tester.getRect(find.text('Devices')).right,
          greaterThanOrEqualTo(16),
        );
        expect(
          tester.getTopLeft(file).dy,
          lessThan(tester.getTopLeft(device).dy),
        );
        expect(tester.takeException(), isNull);
        await capture('ui-portrait');
        final titlePosition = tester.getTopLeft(find.text('Devices'));
        await resize(const Size(340, 844));
        expect(
          tester.getTopLeft(find.text('Devices')),
          titlePosition,
          reason: 'The page title must stay fixed while the window is resized',
        );
        await resize(const Size(320, 844));
        expect(find.byKey(const ValueKey('select-devices')), findsNothing);
        expect(find.byKey(const ValueKey('toggle-device-view')), findsNothing);
        expect(find.byKey(const ValueKey('transfer-history')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('home-more')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const ValueKey('select-devices')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('0 selected'), findsOneWidget);
        await tester.tap(find.byTooltip('Cancel').first);
        await tester.pump();
        await resize(const Size(500, 844));
        expect(find.byKey(const ValueKey('home-more')), findsNothing);
        expect(
          find.byTooltip('Settings'),
          findsOneWidget,
          reason: 'A menu containing only Settings should be a direct button',
        );
        expect(
          find.byKey(const ValueKey('select-devices')),
          findsOneWidget,
          reason: 'Toolbar actions should return progressively as space grows',
        );
        expect(
          find.byKey(const ValueKey('toggle-device-view')),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('refresh-devices'))).dx,
          lessThan(
            tester
                .getTopLeft(find.byKey(const ValueKey('toggle-device-view')))
                .dx,
          ),
        );
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('toggle-device-view')))
              .dx,
          lessThan(
            tester.getTopLeft(find.byKey(const ValueKey('select-devices'))).dx,
          ),
        );
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('select-devices'))).dx,
          lessThan(
            tester.getTopLeft(find.byKey(const ValueKey('add-device'))).dx,
          ),
        );
        expect(tester.takeException(), isNull);
        await resize(const Size(379, 844));
        await tester.pumpWidget(home(animations: true));
        await tester.pump();
        await resize(const Size(380, 844));
        await tester.pump(const Duration(milliseconds: 80));
        final animatedSlot = find
            .descendant(
              of: find.byKey(const ValueKey('toolbar-fade-view')),
              matching: find.byType(Opacity),
            )
            .first;
        expect(
          tester.widget<Opacity>(animatedSlot).opacity,
          inExclusiveRange(0, 1),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.widget<Opacity>(animatedSlot).opacity, 1);
        await tester.pumpWidget(home());
        await tester.pump();
        int? previousCount;
        for (var width = 300; width <= 500; width++) {
          tester.view.physicalSize = Size(width.toDouble(), 844);
          await tester.pump();
          final count = tester
              .widgetList<IconButton>(find.byType(IconButton))
              .length;
          if (previousCount != null) {
            expect(
              count - previousCount,
              inInclusiveRange(0, 1),
              reason: 'Toolbar actions must appear one at a time at $width',
            );
          }
          previousCount = count;
          expect(tester.takeException(), isNull);
        }

        await resize(const Size(844, 390));
        expect(
          tester.getRect(file).right,
          lessThanOrEqualTo(tester.getRect(device).left),
        );
        expect(
          find.byType(DeviceGraph),
          findsNothing,
          reason: 'Explicit list preference survives rotation',
        );
        await capture('ui-landscape');
        await resize(const Size(699, 250));
        final listScroll = tester.state<ScrollableState>(
          find.descendant(of: devices, matching: find.byType(Scrollable)).first,
        );
        expect(listScroll.position.maxScrollExtent, greaterThan(20));
        listScroll.position.jumpTo(20);
        await tester.pump();
        await resize(const Size(700, 250));
        expect(
          tester.state<ScrollableState>(
            find
                .descendant(of: devices, matching: find.byType(Scrollable))
                .first,
          ),
          same(listScroll),
        );
        expect(
          listScroll.position.pixels,
          closeTo(20, .1),
          reason: 'List scroll position survives the breakpoint',
        );
        expect(
          find.byType(DeviceGraph),
          findsNothing,
          reason: 'Automatic view stays stable across the breakpoint',
        );
        expect(
          node.closed,
          isFalse,
          reason: 'Resizing does not close or restart the node',
        );
        await resize(const Size(844, 390));

        await tester.tap(find.byKey(const ValueKey('select-devices')));
        await tester.pump();
        await tester.tap(device);
        await tester.pump();
        expect(
          tester.widget<Checkbox>(find.byType(Checkbox).first).value,
          isTrue,
        );
        await resize(const Size(1200, 760));
        await capture('ui-wide-selected');
        expect(
          tester.widget<Checkbox>(find.byType(Checkbox).first).value,
          isTrue,
          reason: 'Resize must retain selection',
        );
        await tester.tap(find.byTooltip('Cancel').first);
        await tester.pump();
        await capture('ui-wide');
        await tester.tap(find.byKey(const ValueKey('toggle-device-view')));
        await tester.pump();
        expect(find.byType(DeviceGraph), findsOneWidget);
        await capture('ui-wide-graph');
        for (final height in [360.0, 316.0]) {
          await resize(Size(792, height));
          for (var i = 0; i < 200; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(
            find.byType(DeviceGraph),
            findsOneWidget,
            reason: 'A manually chosen graph remains selected at short heights',
          );
          final landscapePane = tester.getRect(devices);
          for (final key in [
            'graph-self',
            'peer-${fakes.peerId}',
            'peer-${'c' * 64}',
            'peer-${'d' * 64}',
            'peer-${'e' * 64}',
          ]) {
            final rect = tester.getRect(find.byKey(ValueKey(key)));
            expect(
              landscapePane.contains(rect.topLeft) &&
                  landscapePane.contains(
                    rect.bottomRight - const Offset(.01, .01),
                  ),
              isTrue,
              reason:
                  '$key is clipped by the landscape viewport at height $height',
            );
          }
          for (final key in [
            'send-file',
            'send-folder',
            'send-text',
            'send-clipboard',
          ]) {
            expect(
              tester.getRect(find.byKey(ValueKey(key))).bottom,
              lessThanOrEqualTo(height),
              reason: '$key must fit in landscape',
            );
          }
        }
        expect(tester.takeException(), isNull);

        await resize(const Size(640, 480));
        expect(
          find.byType(DeviceGraph),
          findsOneWidget,
          reason: 'Manual view preference survives narrowing the window',
        );
        await resize(const Size(699, 400));
        await tester.pumpWidget(home(animations: true));
        await tester.pump();
        final graphState = tester.state(find.byType(DeviceGraph));
        final deviceScroll = tester.state<ScrollableState>(
          find.descendant(of: devices, matching: find.byType(Scrollable)).first,
        );
        final self = find.byKey(const ValueKey('graph-self'));
        final gesture = await tester.startGesture(tester.getCenter(self));
        await gesture.moveBy(const Offset(15, 0));
        await tester.pump();
        tester.view.physicalSize = const Size(700, 400);
        for (var i = 0; i < 17; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.state(find.byType(DeviceGraph)), same(graphState));
          expect(
            tester.state<ScrollableState>(
              find
                  .descendant(of: devices, matching: find.byType(Scrollable))
                  .first,
            ),
            same(deviceScroll),
          );
          final deviceRect = tester.getRect(devices);
          final fileRect = tester.getRect(file);
          final clipboardRect = tester.getRect(
            find.byKey(const ValueKey('send-clipboard')),
          );
          expect(
            fileRect.overlaps(clipboardRect),
            isFalse,
            reason: 'Actions stay separate during the transition',
          );
          expect(
            fileRect.overlaps(deviceRect),
            isFalse,
            reason: 'Actions never cover the device area',
          );
          expect(
            clipboardRect.overlaps(deviceRect),
            isFalse,
            reason: 'Actions never cover the device area',
          );
          expect(tester.takeException(), isNull);
          if (i == 4 || i == 9 || i == 14) await capture('ui-transition-$i');
        }
        await gesture.moveBy(const Offset(15, 0));
        await gesture.up();
        await tester.pump();
        expect(
          tester.state(find.byType(DeviceGraph)),
          same(graphState),
          reason: 'A graph drag survives the layout transition',
        );
        await capture('ui-transition-wide');
        await resize(const Size(160, 220));
        expect(find.byType(DeviceGraph), findsOneWidget);
        await capture('ui-very-small');
        expect(
          tester.takeException(),
          isNull,
          reason: 'A very small viewport remains scrollable without overflow',
        );
        await resize(const Size(80, 100));
        expect(
          tester.takeException(),
          isNull,
          reason: 'Even extreme widths must not overflow',
        );
        await tester.pumpWidget(home());
        await tester.pump();
        await resize(const Size(800, 160));
        final clipboard = find.byKey(const ValueKey('send-clipboard'));
        expect(tester.getBottomRight(clipboard).dy, greaterThan(160));
        await tester.dragFrom(const Offset(20, 145), const Offset(0, -140));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          clipboard.hitTestable(),
          findsOneWidget,
          reason: 'Actions can be reached by scrolling in a very short window',
        );
        expect(tester.takeException(), isNull);
        await capture('ui-short-wide-scrolled');
        if (find.byType(DeviceGraph).evaluate().isNotEmpty) {
          await resize(const Size(1200, 760));
          await tester.tap(find.byKey(const ValueKey('toggle-device-view')));
          await tester.pump();
        }
        await tester.pumpWidget(home(scale: 2));
        await resize(const Size(320, 640));
        for (final text in [
          'Devices',
          'Files',
          'Folder',
          'Text',
          'Clipboard',
        ]) {
          final label = find.text(text);
          expect(label.hitTestable(), findsOneWidget, reason: text);
          final paragraph = tester.renderObject<RenderParagraph>(label);
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '$text should remain readable at 2× text size',
          );
          if (text != 'Devices') {
            final end = paragraph
                .getBoxesForSelection(
                  TextSelection(
                    baseOffset: text.length - 1,
                    extentOffset: text.length,
                  ),
                )
                .single;
            expect(
              end.bottom,
              lessThanOrEqualTo(paragraph.size.height + 0.01),
              reason: '$text should not be clipped vertically',
            );
          }
        }
        await capture('ui-large-text');
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Large text must not overflow the narrow layout',
        );
        await resize(const Size(1200, 760));
        expect(
          tester.takeException(),
          isNull,
          reason: 'Large text must not overflow the wide layout',
        );
      }

      await withHomeTestEnvironment(
        tester,
        api: fakes.FakeRustApi(node),
        devices: devices,
        run: verifyLayout,
      );
    },
  );

  testWidgets(
    'three actions remain reachable and separate during the layout transition',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(699, 160);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      Widget layout(bool wide, {bool disableAnimations = false}) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              height: 220,
              child: HomeResponsiveLayout(
                wide: wide,
                actions: [
                  for (var i = 0; i < 3; i++)
                    FilledButton(
                      key: ValueKey('action-$i'),
                      onPressed: () {},
                      child: Text('Action $i'),
                    ),
                ],
                devices: const ColoredBox(
                  key: ValueKey('device-pane'),
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(layout(false));
      await tester.pumpWidget(layout(true));
      for (var frame = 0; frame < 17; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final device = tester.getRect(
          find.byKey(const ValueKey('device-pane')),
        );
        final actions = [
          for (var i = 0; i < 3; i++)
            tester.getRect(find.byKey(ValueKey('action-$i'))),
        ];
        for (var i = 0; i < actions.length; i++) {
          expect(actions[i].overlaps(device), isFalse);
          for (var j = i + 1; j < actions.length; j++) {
            expect(actions[i].overlaps(actions[j]), isFalse);
          }
        }
        expect(tester.takeException(), isNull);
      }
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -70),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('action-2')).hitTestable(),
        findsOneWidget,
      );
      await tester.pumpWidget(layout(false));
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pumpWidget(layout(false, disableAnimations: true));
      await tester.pump();
      final first = tester.getRect(find.byKey(const ValueKey('action-0')));
      final second = tester.getRect(find.byKey(const ValueKey('action-1')));
      expect(
        second.top,
        closeTo(first.top, .1),
        reason:
            'Enabling reduced motion finishes an active transition immediately',
      );
    },
  );
}
