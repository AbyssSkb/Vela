import 'dart:async';

import 'package:flutter/widgets.dart';

bool isPresenceVisible(
  AppLifecycleState? state, {
  required bool windowHidden,
}) =>
    !windowHidden &&
    (state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive);

bool shouldMonitorPresence(
  AppLifecycleState? state, {
  required bool windowHidden,
  required bool monitorWhileHidden,
  bool androidBackgroundReceive = false,
}) =>
    androidBackgroundReceive ||
    (state != AppLifecycleState.detached &&
        (monitorWhileHidden ||
            isPresenceVisible(state, windowHidden: windowHidden)));

bool shouldRefreshForVisibility({
  required bool visible,
  required bool becameVisible,
  required bool refreshing,
}) => visible && (!refreshing || becameVisible);

Future<bool> retryNetworkChangeAfterWake(
  Future<void> Function() invalidate, {
  required bool Function() shouldRetry,
  required void Function() onFailure,
  Future<void> Function()? delay,
}) async {
  while (shouldRetry()) {
    try {
      await invalidate();
      return true;
    } catch (_) {
      if (!shouldRetry()) return false;
      onFailure();
      await (delay?.call() ?? Future<void>.delayed(const Duration(seconds: 5)));
    }
  }
  return false;
}
