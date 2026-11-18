import 'dart:async';

import 'package:vela/peer_confirmation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('closes the exact pairing dialog when its peer disconnects', (
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
              builder: (_) => const AlertDialog(title: Text('Pair request')),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Pair request'), findsOneWidget);
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
              builder: (context) => AlertDialog(
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
