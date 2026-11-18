import 'dart:async';

import 'package:flutter/material.dart';

enum PeerDecision { accepted, declined, connectionClosed }

Future<PeerDecision> showPeerConfirmation(
  BuildContext context, {
  required WidgetBuilder builder,
  required Future<void> peerClosed,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<bool>(
    context: context,
    barrierDismissible: false,
    builder: builder,
  );
  final choice = navigator
      .push(route)
      .then(
        (value) =>
            value == true ? PeerDecision.accepted : PeerDecision.declined,
      );
  final closed = peerClosed.then(
    (_) => PeerDecision.connectionClosed,
    onError: (Object _, StackTrace _) => PeerDecision.connectionClosed,
  );
  final result = await Future.any([choice, closed]);
  if (result == PeerDecision.connectionClosed &&
      route.isActive &&
      navigator.mounted) {
    navigator.removeRoute(route);
  }
  return result;
}
