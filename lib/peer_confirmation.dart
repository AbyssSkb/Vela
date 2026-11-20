import 'dart:async';

import 'package:flutter/material.dart';

import 'notice.dart';

enum PeerDecision { accepted, declined, connectionClosed }

Future<PeerDecision> showPeerConfirmation(
  BuildContext context, {
  required WidgetBuilder builder,
  required Future<void> peerClosed,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = bottomNoticeRoute<bool>(context, builder: builder);
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
