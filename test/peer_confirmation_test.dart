import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela/notice.dart';
import 'package:vela/peer_confirmation.dart';

void main() {
  testWidgets('closes the bottom pairing notice when its peer disconnects', (
    tester,
  ) async {
    final peerClosed = Completer<void>();
    PeerDecision? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showPeerConfirmation(
              context,
              peerClosed: peerClosed.future,
              builder: (_) =>
                  const NoticePrompt(title: 'Pair request', actions: []),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Pair request'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    final screen = tester.getSize(find.byType(Navigator));
    final notice = tester.getRect(find.byType(ActivityNotice));
    expect(notice.left, 0);
    expect(notice.right, screen.width);
    expect(notice.bottom, screen.height);
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(find.byType(ActivityNotice), findsNothing);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.byType(ActivityNotice), findsOneWidget);
    peerClosed.complete();
    await tester.pumpAndSettle();
    expect(find.text('Pair request'), findsNothing);
    expect(result, PeerDecision.connectionClosed);
  });

  testWidgets('explicit rejection remains a rejection', (tester) async {
    final peerClosed = Completer<void>();
    PeerDecision? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showPeerConfirmation(
              context,
              peerClosed: peerClosed.future,
              builder: (context) => NoticePrompt(
                title: 'Pair request',
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Reject'),
                  ),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(result, PeerDecision.declined);
    peerClosed.complete();
  });
}
