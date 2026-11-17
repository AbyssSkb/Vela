import 'dart:async';

import 'package:vela/presence_probe.dart';
import 'package:vela/peer_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  test(
    'removal and re-adding an id never reuse its old status or generation',
    () {
      final previous = PeerState(peers: {'a': 'A'});
      final removed = previous.remove('a');
      final added = removed.add('a', 'A', 'desktop');
      final presence = {'a': 'online'};
      final generations = {'a': 2};
      final oldProbe = Completer<void>();
      final active = <String, Future<void>>{'a': oldProbe.future};

      expect(
        invalidatePresenceForPeerMembershipChanges(
          previous,
          removed,
          presence,
          generations,
          active,
        ),
        {'a'},
      );
      expect(presence, isEmpty);
      expect(generations['a'], 3);
      expect(active, isEmpty);
      oldProbe.complete();
      expect(
        invalidatePresenceForPeerMembershipChanges(
          removed,
          added,
          presence,
          generations,
          active,
        ),
        {'a'},
      );
      expect(presence, isEmpty);
      expect(generations['a'], 4);
    },
  );

  test('renaming and device information changes preserve presence', () {
    final previous = PeerState(peers: {'a': 'A'});
    final updated = previous
        .setAlias('a', 'Alias')
        .updateInfo('a', 'New name', 'desktop');
    final presence = {'a': 'online'};
    final generations = {'a': 2};
    final task = Completer<void>();
    final active = <String, Future<void>>{'a': task.future};

    expect(
      invalidatePresenceForPeerMembershipChanges(
        previous,
        updated,
        presence,
        generations,
        active,
      ),
      isEmpty,
    );
    expect(presence, {'a': 'online'});
    expect(generations['a'], 2);
    expect(active['a'], same(task.future));
    task.complete();
  });

  test('Android presence follows visibility', () {
    expect(
      shouldMonitorPresence(null, windowHidden: false, isMacOS: false),
      isTrue,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.resumed,
        windowHidden: false,
        isMacOS: false,
      ),
      isTrue,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.inactive,
        windowHidden: false,
        isMacOS: false,
      ),
      isTrue,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.hidden,
        windowHidden: false,
        isMacOS: false,
      ),
      isFalse,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.paused,
        windowHidden: false,
        isMacOS: false,
      ),
      isFalse,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.detached,
        windowHidden: false,
        isMacOS: false,
      ),
      isFalse,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.inactive,
        windowHidden: true,
        isMacOS: false,
      ),
      isFalse,
    );
  });

  test(
    'Android background receiving keeps monitoring while its engine lives',
    () {
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        expect(
          shouldMonitorPresence(state, windowHidden: false, isMacOS: false),
          isFalse,
        );
        expect(
          shouldMonitorPresence(
            state,
            windowHidden: false,
            isMacOS: false,
            androidBackgroundReceive: true,
          ),
          isTrue,
        );
      }
    },
  );

  test('macOS keeps monitoring when the window is closed or hidden', () {
    for (final state in [
      null,
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      expect(
        shouldMonitorPresence(state, windowHidden: true, isMacOS: true),
        isTrue,
      );
      expect(
        shouldMonitorPresence(state, windowHidden: false, isMacOS: true),
        isTrue,
      );
    }
    expect(
      shouldMonitorPresence(
        AppLifecycleState.detached,
        windowHidden: true,
        isMacOS: true,
      ),
      isFalse,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.detached,
        windowHidden: false,
        isMacOS: true,
      ),
      isFalse,
    );
  });

  test('restoring a macOS window still requests a fresh check', () {
    final wasVisible = isPresenceVisible(
      AppLifecycleState.inactive,
      windowHidden: true,
    );
    final visible = isPresenceVisible(
      AppLifecycleState.inactive,
      windowHidden: false,
    );
    expect(wasVisible, isFalse);
    expect(
      shouldRefreshForVisibility(
        visible: visible,
        becameVisible: !wasVisible,
        refreshing: true,
      ),
      isTrue,
    );
  });
  test('duplicate visibility events do not restart an active check', () {
    expect(
      shouldRefreshForVisibility(
        visible: true,
        becameVisible: true,
        refreshing: false,
      ),
      isTrue,
    );
    expect(
      shouldRefreshForVisibility(
        visible: true,
        becameVisible: false,
        refreshing: true,
      ),
      isFalse,
    );
    expect(
      shouldRefreshForVisibility(
        visible: true,
        becameVisible: true,
        refreshing: true,
      ),
      isTrue,
    );
    expect(
      shouldRefreshForVisibility(
        visible: false,
        becameVisible: true,
        refreshing: false,
      ),
      isFalse,
    );
  });

  test(
    'system wake retries a failed invalidation before allowing refresh',
    () async {
      var attempts = 0;
      var failures = 0;
      final retry = Completer<void>();
      final result = retryNetworkChangeAfterWake(
        () async {
          attempts++;
          if (attempts == 1) throw StateError('unavailable');
        },
        shouldRetry: () => true,
        onFailure: () => failures++,
        delay: () => retry.future,
      );
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 1);
      expect(failures, 1);
      retry.complete();
      expect(await result, isTrue);
      expect(attempts, 2);
    },
  );

  test('system wake stops retrying when the node is replaced', () async {
    var current = true;
    var attempts = 0;
    final result = await retryNetworkChangeAfterWake(
      () async {
        attempts++;
        current = false;
        throw StateError('closed');
      },
      shouldRetry: () => current,
      onFailure: () => fail('closed node must not schedule a retry'),
    );
    expect(result, isFalse);
    expect(attempts, 1);
  });
}
