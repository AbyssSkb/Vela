import 'package:vela/notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'activity notice reaches the bottom and keeps its action accessible',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ActivityNotice(
              child: Row(
                children: [
                  const Expanded(child: Text('正在发送给设备')),
                  IconButton(
                    onPressed: () => cancelled = true,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('activity-notice'))).dy,
        640,
      );
      expect(
        tester
            .widget<Material>(find.byKey(const ValueKey('activity-notice')))
            .elevation,
        0,
      );
      await tester.tap(find.byIcon(Icons.close));
      expect(cancelled, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  for (final kind in NoticeKind.values) {
    testWidgets('$kind notice uses a bottom snackbar with its own icon', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showNotice(context, 'Example', kind: kind),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.behavior, SnackBarBehavior.fixed);
      expect(snack.width, isNull);
      expect(snack.elevation, 0);
      expect(tester.getBottomLeft(find.byType(SnackBar)).dy, 640);
      expect(find.text('Example'), findsOneWidget);
      expect(
        find.byIcon(switch (kind) {
          NoticeKind.info => Icons.info_outline_rounded,
          NoticeKind.success => Icons.check_circle_outline_rounded,
          NoticeKind.error => Icons.error_outline_rounded,
        }),
        findsOneWidget,
      );
    });
  }
  testWidgets('Android notice is flush with the bottom without a shadow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showNotice(context, 'Received', kind: NoticeKind.success),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.behavior, SnackBarBehavior.fixed);
    expect(snack.width, isNull);
    expect(snack.elevation, 0);
    expect(find.text('Received'), findsOneWidget);
  });
  testWidgets('received file notice keeps an accessible open action', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNotice(
                context,
                'File received',
                kind: NoticeKind.success,
                actionLabel: 'Open',
                onAction: () => opened = true,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('File received'), findsOneWidget);
    expect(find.byKey(const ValueKey('notice-close')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notice-action')));
    expect(opened, isTrue);
  });
  testWidgets('long received names fit beside the open action on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNotice(
                context,
                'Received ${'long-file-name-' * 20}.pdf',
                kind: NoticeKind.success,
                actionLabel: 'Open',
                onAction: () {},
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('notice-action')), findsOneWidget);
    expect(
      tester.getSize(find.byType(SnackBar)).height,
      lessThanOrEqualTo(120),
    );
  });

  testWidgets('received batch action remains readable at 2× text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNotice(
                context,
                'Received 3 files',
                kind: NoticeKind.success,
                actionLabel: 'View received items',
                onAction: () {},
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('View received items').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
