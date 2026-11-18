import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela/peer_state.dart';

void main() {
  test('stores peers and aliases, updates and removes one device', () {
    final original = PeerState()
        .add('a', 'Phone', 'mobile')
        .add('b', 'Laptop', 'desktop')
        .setAlias('a', 'My phone');
    final state = PeerState.decode(original.encode());
    expect(jsonDecode(state.encode()), {
      'version': 2,
      'peers': {'a': 'Phone', 'b': 'Laptop'},
      'types': {'a': 'mobile', 'b': 'desktop'},
      'aliases': {'a': 'My phone'},
    });
    expect(state.deviceIds, ['a', 'b']);
    expect(state.containsDevice('a'), isTrue);
    expect(state.containsDevice('missing'), isFalse);
    expect(state.reportedName('a'), 'Phone');
    expect(state.deviceType('a'), 'mobile');
    final updated = state.updateInfo('a', 'New name', 'tablet');
    expect(updated.displayName('a'), 'My phone');
    expect(updated.setAlias('a', null).displayName('a'), 'New name');
    expect(updated.remove('a').peers, {'b': 'Laptop'});
    expect(updated.remove('a').types, {'b': 'desktop'});
    expect(updated.remove('a').aliases, isEmpty);
    expect(original.peers['a'], 'Phone');
    expect(() => state.peers['a'] = 'changed', throwsUnsupportedError);
  });

  test(
    'unknown peers cannot be updated or renamed and old format is rejected',
    () {
      final state = PeerState();
      expect(
        identical(state.updateInfo('a', 'Phone', 'mobile'), state),
        isTrue,
      );
      expect(identical(state.setAlias('a', 'Alias'), state), isTrue);
      expect(identical(state.remove('a'), state), isTrue);
      expect(state.displayName('a'), 'a');
      expect(() => PeerState.decode('{"version":1}'), throwsFormatException);
    },
  );
}
