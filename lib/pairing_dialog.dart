import 'dart:async';

import 'package:flutter/material.dart';

enum PairingDialogResult { accepted, declined, connectionClosed }

Future<PairingDialogResult> showPairingDialog(
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
        (value) => value == true
            ? PairingDialogResult.accepted
            : PairingDialogResult.declined,
      );
  final closed = peerClosed.then(
    (_) => PairingDialogResult.connectionClosed,
    onError: (Object _, StackTrace _) => PairingDialogResult.connectionClosed,
  );
  final result = await Future.any([choice, closed]);
  if (result == PairingDialogResult.connectionClosed &&
      route.isActive &&
      navigator.mounted) {
    navigator.removeRoute(route);
  }
  return result;
}
