import 'package:vela/notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('activity notice reaches the window edges around safe actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    const insets = FakeViewPadding(left: 18, right: 18, bottom: 24);
    tester.view.viewPadding = insets;
    tester.view.padding = insets;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewPadding();
      tester.view.resetPadding();
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
    final panel = find.byKey(const ValueKey('activity-notice'));
    expect(tester.getBottomLeft(panel), const Offset(0, 640));
    expect(tester.getBottomRight(panel), const Offset(320, 640));
    final material = tester.widget<Material>(panel);
    expect(material.elevation, 0);
    expect(
      material.shape,
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
    );
    final button = find.byType(IconButton);
    final action = tester.getRect(button);
    expect(action.top - tester.getTopLeft(panel).dy, 24);
    expect(action.bottom, 616);
    expect(action.right, lessThanOrEqualTo(302));
    const sidesOnly = FakeViewPadding(left: 18, right: 18);
    tester.view.viewPadding = sidesOnly;
    tester.view.padding = sidesOnly;
    await tester.pump();
    expect(tester.getRect(button).top - tester.getTopLeft(panel).dy, 12);
    expect(tester.getRect(button).bottom, 628);
    tester.view.physicalSize = const Size(640, 320);
    tester.view.viewPadding = insets;
    tester.view.padding = insets;
    await tester.pump();
    expect(tester.getRect(button).top - tester.getTopLeft(panel).dy, 12);
    expect(tester.getRect(button).bottom, 296);
    await tester.tap(find.byIcon(Icons.close));
    expect(cancelled, isTrue);
    expect(tester.takeException(), isNull);
  });
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
      expect(
        snack.shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
      );
      final panel = find.byKey(const ValueKey('message-notice'));
      expect(tester.getBottomLeft(panel), const Offset(0, 640));
      expect(tester.getBottomRight(panel), const Offset(320, 640));
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
  testWidgets('Android receipt follows changes in the bottom system inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNotice(
                context,
                'Received',
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
    final panel = find.byKey(const ValueKey('message-notice'));
    expect(
      tester.widget<SnackBar>(panel).backgroundColor,
      const Color(0xffd9f1df),
    );
    final open = find.byKey(const ValueKey('notice-action'));
    final close = find.byKey(const ValueKey('notice-close'));
    for (final (inset, top, bottom) in [
      (24.0, 24.0, 24.0),
      (40.0, 40.0, 40.0),
      (0.0, 12.0, 12.0),
    ]) {
      tester.view.viewPadding = FakeViewPadding(bottom: inset);
      tester.view.padding = FakeViewPadding(bottom: inset);
      await tester.pump();
      final bounds = tester.getRect(panel);
      expect(bounds.bottomLeft, const Offset(0, 800));
      expect(bounds.bottomRight, const Offset(360, 800));
      for (final control in [open, close]) {
        final rect = tester.getRect(control);
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.top - bounds.top, top);
        expect(bounds.bottom - rect.bottom, bottom);
      }
    }
    expect(find.text('Received'), findsOneWidget);
    tester.view.physicalSize = const Size(800, 360);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    tester.view.padding = const FakeViewPadding(bottom: 24);
    await tester.pump();
    expect(tester.getRect(open).top - tester.getTopLeft(panel).dy, 12);
    expect(tester.getRect(open).bottom, 336);
    await tester.tap(open);
    expect(opened, isTrue);
  });
  testWidgets('short confirmations align their message and actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ActivityNotice(
            child: NoticePrompt(
              title: 'From Mac',
              inlineActions: true,
              actions: [
                TextButton(onPressed: () {}, child: const Text('Decline')),
                FilledButton(onPressed: () {}, child: const Text('Receive')),
              ],
            ),
          ),
        ),
      ),
    );
    final action = tester.getRect(find.text('Receive'));
    final title = tester.getRect(find.text('From Mac'));
    expect(title.right, lessThan(action.left));
    expect(title.center.dy, action.center.dy);
    expect(tester.takeException(), isNull);
  });
  testWidgets('received file notice keeps an accessible open action', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
          child: child!,
        ),
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
    await tester.pump();
    expect(find.text('File received'), findsNothing);
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
    final savedTo = 'Saved to /${'nested-directory/' * 15}';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNotice(
                context,
                'Received ${'long-file-name-' * 20}.pdf',
                detail: savedTo,
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
    final detail = tester.widget<Text>(find.text(savedTo));
    expect(detail.maxLines, 1);
    expect(detail.overflow, TextOverflow.ellipsis);
    expect(
      tester.getSize(find.byType(SnackBar)).height,
      lessThanOrEqualTo(128),
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
  testWidgets('actionable notice expires when the keyboard opens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 320);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNotice(
                context,
                'Received a very long file name that would wrap',
                detail: 'Saved to Downloads',
                actionLabel: 'Open file',
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
    tester.view.viewInsets = const FakeViewPadding(bottom: 248);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsNothing);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
