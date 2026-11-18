import 'dart:async';

import 'package:vela/presence_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  test('Android presence follows visibility', () {
    expect(
      shouldMonitorPresence(
        null,
        windowHidden: false,
        monitorWhileHidden: false,
      ),
      isTrue,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.resumed,
        windowHidden: false,
        monitorWhileHidden: false,
      ),
      isTrue,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.inactive,
        windowHidden: false,
        monitorWhileHidden: false,
      ),
      isTrue,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.hidden,
        windowHidden: false,
        monitorWhileHidden: false,
      ),
      isFalse,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.paused,
        windowHidden: false,
        monitorWhileHidden: false,
      ),
      isFalse,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.detached,
        windowHidden: false,
        monitorWhileHidden: false,
      ),
      isFalse,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.inactive,
        windowHidden: true,
        monitorWhileHidden: false,
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
          shouldMonitorPresence(
            state,
            windowHidden: false,
            monitorWhileHidden: false,
          ),
          isFalse,
        );
        expect(
          shouldMonitorPresence(
            state,
            windowHidden: false,
            monitorWhileHidden: false,
            androidBackgroundReceive: true,
          ),
          isTrue,
        );
      }
    },
  );

  test('desktop keeps monitoring when the window is closed or hidden', () {
    for (final state in [
      null,
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      expect(
        shouldMonitorPresence(
          state,
          windowHidden: true,
          monitorWhileHidden: true,
        ),
        isTrue,
      );
      expect(
        shouldMonitorPresence(
          state,
          windowHidden: false,
          monitorWhileHidden: true,
        ),
        isTrue,
      );
    }
    expect(
      shouldMonitorPresence(
        AppLifecycleState.detached,
        windowHidden: true,
        monitorWhileHidden: true,
      ),
      isFalse,
    );
    expect(
      shouldMonitorPresence(
        AppLifecycleState.detached,
        windowHidden: false,
        monitorWhileHidden: true,
      ),
      isFalse,
    );
  });

  test('restoring a desktop window still requests a fresh check', () {
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
