import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela/app_update.dart';
import 'package:vela/main.dart';
import 'package:vela/peer_state.dart';

import 'support/fakes.dart';
import 'support/home_environment.dart';

void main() {
  for (final background in [false, true]) {
    testWidgets(
      'verified download requests installation once (background: $background)',
      (tester) async {
        final node = FakeNode();
        final messenger = tester.binding.defaultBinaryMessenger;
        const channel = MethodChannel('vela/update');
        final installs = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'installDownloaded') installs.add(call);
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await withHomeTestEnvironment(
          tester,
          devices: PeerState(),
          api: FakeRustApi(node),
          run: (_) async {
            await tester.pumpWidget(
              const VelaApp(
                profile: 'test',
                initialLanguage: 'en',
                initialAppearance: 'light',
                initialDiagnosticsEnabled: false,
              ),
            );
            final dynamic home = tester.state(find.byType(HomePage));
            final updates = home.updates as AppUpdateController;
            await waitForHome(tester, () => home.node != null && !updates.busy);

            if (background) {
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.paused,
              );
              home.folderOperation = true;
            }
            updates.state = AppUpdateState.downloading;
            await updates.setBusy(true);
            updates.state = AppUpdateState.ready;
            await updates.setBusy(false);
            await tester.pumpAndSettle();
            if (background) {
              expect(find.text('Install update?'), findsNothing);
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
              await tester.pump(const Duration(milliseconds: 300));
              expect(find.text('Install update?'), findsNothing);
              home.folderOperation = false;
              await tester.pump(const Duration(milliseconds: 300));
              await tester.pumpAndSettle();
            }
            expect(find.text('Install update?'), findsOneWidget);
            expect(installs, isEmpty);
            await tester.tap(find.text('Later'));
            await tester.pumpAndSettle();

            updates.state = AppUpdateState.installing;
            await updates.setBusy(true);
            updates.state = AppUpdateState.ready;
            await updates.setBusy(false);
            await tester.pumpAndSettle();
            expect(find.text('Install update?'), findsNothing);
            expect(installs, isEmpty);
          },
        );
      },
    );
  }
}
