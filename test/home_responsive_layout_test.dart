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
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart' as fakes;
import 'support/home_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home overlays background problems without moving devices', (
    tester,
  ) async {
    await withHomeTestEnvironment(
      tester,
      devices: PeerState(peers: {fakes.peerId: 'Phone'}),
      api: fakes.FakeRustApi(fakes.FakeNode()),
      run: (_) async {
        tester.view.physicalSize = const Size(390, 480);
        SharedPreferences.setMockInitialValues({
          'background_receive_test': true,
        });
        var permission = false;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('vela/background'),
          (call) async => call.method == 'status'
              ? {
                  'running': true,
                  'nodeReady': true,
                  'notifications': permission,
                }
              : null,
        );
        await tester.pumpWidget(
          const VelaApp(
            profile: 'test',
            initialLanguage: 'en',
            initialAppearance: 'light',
            initialDiagnosticsEnabled: false,
          ),
        );
        final availability = find.byKey(
          const ValueKey('local-background-availability'),
        );
        await waitForHome(tester, () => availability.evaluate().isNotEmpty);
        expect(availability.hitTestable(), findsOneWidget);
        final peer = find.byKey(const ValueKey('peer-${fakes.peerId}'));
        final before = tester.getTopLeft(peer);
        final notice = find.ancestor(
          of: availability,
          matching: find.byKey(const ValueKey('activity-notice')),
        );
        expect(tester.getBottomLeft(notice).dy, 480);
        expect(find.text('Request notifications are off'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Settings'));
        await tester.pumpAndSettle();
        expect(find.text('Allow background receiving'), findsOneWidget);
        permission = true;
        await tester.pageBack();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(availability, findsNothing);
        expect(tester.getTopLeft(peer).dy, before.dy);
      },
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'tray menu follows the resolved app language',
    (tester) async {
      await withHomeTestEnvironment(
        tester,
        devices: PeerState(),
        api: fakes.FakeRustApi(fakes.FakeNode()),
        run: (_) async {
          final labels = <Object?>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('vela/background'),
            (call) async {
              if (call.method == 'setTrayLabels' ||
                  call.method == 'setMenuLanguage') {
                labels.add(call.arguments);
              }
              return call.method == 'getWindowVisible' ? true : null;
            },
          );
          await tester.pumpWidget(
            const VelaApp(
              profile: 'test',
              initialLanguage: 'en',
              initialAppearance: 'light',
              initialDiagnosticsEnabled: false,
            ),
          );
          final mac =
              Theme.of(tester.element(find.byType(HomePage))).platform ==
              TargetPlatform.macOS;
          expect(
            labels.last,
            mac
                ? 'en'
                : {
                    'open': 'Open Vela',
                    'quit': 'Quit',
                    'transferring': 'Transferring',
                    'completed': 'Transfer complete',
                    'incoming': 'Incoming',
                  },
          );
          await tester
              .widget<HomePage>(find.byType(HomePage))
              .changeSetting('language', 'zh');
          await tester.pump();
          expect(
            labels.last,
            mac
                ? 'zh'
                : {
                    'open': '打开 Vela',
                    'quit': '退出',
                    'transferring': '正在传输',
                    'completed': '传输完成',
                    'incoming': '待接收',
                  },
          );
        },
      );
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }),
  );

  testWidgets('settings opens troubleshooting in the selected language', (
    tester,
  ) async {
    await withHomeTestEnvironment(
      tester,
      devices: PeerState(),
      api: fakes.FakeRustApi(fakes.FakeNode()),
      run: (_) async {
        const files = MethodChannel('vela/files');
        final opened = <Uri>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(files, (call) async {
          if (call.method == 'openUrl') {
            opened.add(Uri.parse(call.arguments['url'] as String));
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(files, null));
        await tester.pumpWidget(
          const VelaApp(
            profile: 'test',
            initialLanguage: 'en',
            initialAppearance: 'light',
            initialDiagnosticsEnabled: false,
          ),
        );
        final settings = find.byTooltip('Settings');
        await waitForHome(tester, () => settings.evaluate().isNotEmpty);
        await tester.tap(settings);
        await tester.pumpAndSettle();
        final english = find.text('User guide');
        await tester.ensureVisible(english);
        await tester.tap(english);
        expect(opened.single.path, endsWith('/docs/user-guide.md'));
        expect(opened.single.fragment, 'troubleshooting');

        await tester
            .widget<HomePage>(find.byType(HomePage, skipOffstage: false))
            .changeSetting('language', 'zh');
        await tester.pumpAndSettle();
        final chinese = find.text('使用指南');
        await tester.ensureVisible(chinese);
        await tester.tap(chinese);
        expect(opened.last.path, endsWith('/README.zh-CN.md'));
        expect(Uri.decodeComponent(opened.last.fragment), '故障排查');
      },
    );
  });

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
        final showCode = find.text('Device code');
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pump();
        expect(add.hitTestable(), findsOneWidget);
        expect(showCode.hitTestable(), findsOneWidget);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pump();
        await tester.tap(showCode);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('device-id')), findsOneWidget);
        String? copied;
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await tester.tap(find.text('Copy device code'));
        await tester.pumpAndSettle();
        expect(copied, fakes.FakeNode().id());
        expect(find.text('Device code copied'), findsOneWidget);
        expect(find.byKey(const ValueKey('device-id')), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(1000, 700);
        await tester.pump();
        await tester.tap(showCode);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('device-id')).hitTestable(),
          findsOneWidget,
        );
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
        expect(find.text('Rename device'), findsOneWidget);
        expect(find.text('Only shown on this device.'), findsNothing);
        expect(
          find.descendant(
            of: find.widgetWithText(ListTile, 'Restore device name'),
            matching: find.text('Phone'),
          ),
          findsOneWidget,
        );

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
        expect(find.byKey(const ValueKey('transfer-history')), findsNothing);
        expect(
          find.byKey(const ValueKey('local-background-availability')),
          findsNothing,
        );
        expect(find.text('Send content'), findsNothing);
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
        expect(find.byKey(const ValueKey('transfer-history')), findsNothing);
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
        final received = find.byKey(const ValueKey('transfer-history'));
        final graphToggle = find.byKey(const ValueKey('toggle-device-view'));
        expect(find.byKey(const ValueKey('home-settings')), findsOneWidget);
        expect(received.hitTestable(), findsOneWidget);
        expect(graphToggle.hitTestable(), findsOneWidget);
        expect(tester.getCenter(graphToggle).dy, tester.getCenter(received).dy);
        expect(
          tester.getTopLeft(received).dy,
          lessThan(tester.getTopLeft(file).dy),
        );
        await resize(const Size(303, 844));
        await tester.pumpWidget(home(animations: true));
        await tester.pump();
        await resize(const Size(304, 844));
        await tester.pump(const Duration(milliseconds: 80));
        final animatedSlot = find
            .descendant(
              of: find.byKey(const ValueKey('toolbar-fade-refresh')),
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
        expect(received.hitTestable(), findsOneWidget);
        expect(
          find.byKey(const ValueKey('add-device')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.getRect(device).top - tester.getRect(file).bottom, 16);
        expect(
          find.byType(DeviceGraph),
          findsNothing,
          reason: 'The default list survives rotation',
        );
        await capture('ui-landscape');
        await resize(const Size(699, 250));
        final listScroll = tester.state<ScrollableState>(
          find.descendant(of: devices, matching: find.byType(Scrollable)).first,
        );
        expect(listScroll.position.maxScrollExtent, greaterThan(0));
        final listOffset = listScroll.position.maxScrollExtent / 2;
        listScroll.position.jumpTo(listOffset);
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
          closeTo(listOffset, .1),
          reason: 'List scroll position survives the breakpoint',
        );
        expect(
          find.byType(DeviceGraph),
          findsNothing,
          reason: 'The list stays selected across the breakpoint',
        );
        expect(
          node.closed,
          isFalse,
          reason: 'Resizing does not close or restart the node',
        );
        await resize(const Size(844, 390));

        await tester.tap(find.byKey(const ValueKey('select-devices')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
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
          await tester.ensureVisible(file);
          await tester.pump();
          for (final key in [
            'send-file',
            'send-folder',
            'send-text',
            'send-clipboard',
          ]) {
            expect(
              find.byKey(ValueKey(key)).hitTestable(),
              findsOneWidget,
              reason: '$key must fit in landscape',
            );
          }
          for (final key in [
            'graph-self',
            'peer-${fakes.peerId}',
            'peer-${'c' * 64}',
            'peer-${'d' * 64}',
            'peer-${'e' * 64}',
          ]) {
            final device = find.byKey(ValueKey(key));
            await tester.ensureVisible(device);
            await tester.pump();
            expect(
              device.hitTestable(),
              findsOneWidget,
              reason: '$key must be reachable in landscape at $height',
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
        expect(
          clipboard.hitTestable(),
          findsOneWidget,
          reason: 'The desktop send row fits in a short window',
        );
        expect(tester.takeException(), isNull);
        await capture('ui-short-wide');
        if (find.byType(DeviceGraph).evaluate().isNotEmpty) {
          await resize(const Size(1200, 760));
          await tester.tap(find.byKey(const ValueKey('toggle-device-view')));
          await tester.pump();
        }
        await tester.pumpWidget(home(scale: 2));
        await resize(const Size(320, 640));
        expect(
          find.byKey(const ValueKey('home-more')).hitTestable(),
          findsOneWidget,
        );
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

  testWidgets(
    'desktop layout keeps its bounds as devices are added or removed',
    (tester) async {
      final extraId = 'c' * 64;
      await withHomeTestEnvironment(
        tester,
        devices: PeerState(peers: {fakes.peerId: 'Phone'}),
        api: fakes.FakeRustApi(fakes.FakeNode()),
        run: (_) async {
          Future<void> finishTransition() async {
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
          }

          SharedPreferences.setMockInitialValues({'device_view_test': 'list'});
          tester.view.physicalSize = const Size(1030, 680);
          await tester.pumpWidget(
            const VelaApp(
              profile: 'test',
              initialLanguage: 'en',
              initialAppearance: 'light',
              initialDiagnosticsEnabled: false,
            ),
          );
          final first = find.byKey(const ValueKey('peer-${fakes.peerId}'));
          final extra = find.byKey(ValueKey('peer-$extraId'));
          final files = find.byKey(const ValueKey('send-file'));
          final clipboard = find.byKey(const ValueKey('send-clipboard'));
          await waitForHome(tester, () => first.evaluate().isNotEmpty);
          final action = tester.getRect(files);
          final firstDevice = tester.getRect(first);
          expect(action.top, tester.getTopLeft(clipboard).dy);
          expect(action.left, 24);
          expect(firstDevice.left, action.left);
          expect(firstDevice.top - action.bottom, 16);
          expect(firstDevice.width, closeTo((1030 - 48 - 24) / 3, .01));

          await tester.tap(find.byKey(const ValueKey('add-device')));
          await finishTransition();
          await tester.enterText(
            find.byKey(const ValueKey('peer-id')),
            extraId,
          );
          await tester.tap(find.byKey(const ValueKey('confirm-peer')));
          await waitForHome(tester, () => extra.evaluate().isNotEmpty);
          await finishTransition();
          expect(tester.getRect(files), action);
          expect(tester.getRect(first), firstDevice);
          final secondDevice = tester.getRect(extra);
          expect(secondDevice.left - firstDevice.right, closeTo(12, .01));
          expect(secondDevice.top, firstDevice.top);
          expect(secondDevice.width, closeTo(firstDevice.width, .01));

          await tester.tap(extra);
          await finishTransition();
          await tester.tap(find.text('Remove device'));
          await finishTransition();
          await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
          await waitForHome(tester, () => extra.evaluate().isEmpty);
          expect(tester.getRect(files), action);
          expect(tester.getRect(first), firstDevice);

          tester.view.physicalSize = const Size(336, 680);
          await finishTransition();
          final narrowFiles = tester.getRect(files);
          final folder = find.byKey(const ValueKey('send-folder'));
          final text = find.byKey(const ValueKey('send-text'));
          expect(tester.getTopLeft(folder).dy, narrowFiles.top);
          expect(tester.getTopLeft(text).dy, greaterThan(narrowFiles.bottom));
          expect(tester.getTopLeft(clipboard).dy, tester.getTopLeft(text).dy);
          for (final button in [files, folder, text, clipboard]) {
            expect(tester.getSize(button).height, action.height);
          }
        },
      );
    },
  );

  for (final savedView in [null, 'list', 'graph']) {
    testWidgets('wide home opens with ${savedView ?? 'the default graph'}', (
      tester,
    ) async {
      await withHomeTestEnvironment(
        tester,
        devices: PeerState(peers: {fakes.peerId: 'Phone'}),
        api: fakes.FakeRustApi(fakes.FakeNode()),
        run: (_) async {
          if (savedView != null) {
            SharedPreferences.setMockInitialValues({
              'device_view_test': savedView,
            });
          }
          tester.view.physicalSize = const Size(1100, 690);
          await tester.pumpWidget(
            const VelaApp(
              profile: 'test',
              initialLanguage: 'en',
              initialAppearance: 'light',
              initialDiagnosticsEnabled: false,
            ),
          );
          final toggle = find.byKey(const ValueKey('toggle-device-view'));
          await waitForHome(tester, () => toggle.evaluate().isNotEmpty);
          final graph = find.byType(DeviceGraph);
          expect(graph, savedView == 'list' ? findsNothing : findsOneWidget);
          final firstAction = find.byKey(const ValueKey('send-file'));
          final devices = find.byKey(const ValueKey('home-devices'));
          expect(
            tester.getTopLeft(devices).dy -
                tester.getBottomLeft(firstAction).dy,
            16,
            reason: 'The desktop device view sits below the send actions',
          );
          if (savedView == 'graph') {
            tester.platformDispatcher.textScaleFactorTestValue = 2;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await tester.pump();
            expect(graph, findsNothing);
            expect(toggle, findsNothing);
            expect(find.widgetWithText(ListTile, 'Phone'), findsOneWidget);
            tester.platformDispatcher.clearTextScaleFactorTestValue();
            await tester.pump();
            expect(graph, findsOneWidget);
          }
          await tester.tap(toggle);
          await tester.pump();
          expect(graph, savedView == 'list' ? findsOneWidget : findsNothing);
          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs.getString('device_view_test'),
            savedView == 'list' ? 'graph' : 'list',
          );
        },
      );
    });
  }
}
