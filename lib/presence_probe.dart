import 'dart:async';

import 'package:flutter/widgets.dart';

import 'peer_state.dart';

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
  required bool isMacOS,
  bool androidBackgroundReceive = false,
}) =>
    androidBackgroundReceive ||
    (state != AppLifecycleState.detached &&
        (isMacOS || isPresenceVisible(state, windowHidden: windowHidden)));

bool shouldRefreshForVisibility({
  required bool visible,
  required bool becameVisible,
  required bool refreshing,
}) => visible && (!refreshing || becameVisible);

Set<String> invalidatePresenceForPeerMembershipChanges<T>(
  PeerState previous,
  PeerState updated,
  Map<String, T> presence,
  Map<String, int> generations,
  Map<String, Future<void>> active,
) {
  final changed = <String>{...previous.peers.keys, ...updated.peers.keys}
    ..removeWhere(
      (id) => previous.peers.containsKey(id) == updated.peers.containsKey(id),
    );
  for (final id in changed) {
    presence.remove(id);
    generations[id] = (generations[id] ?? 0) + 1;
    active.remove(id);
  }
  return changed;
}

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
