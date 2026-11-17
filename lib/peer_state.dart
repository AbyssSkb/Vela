import 'dart:convert';

class PeerState {
  PeerState({
    Map<String, String>? peers,
    Map<String, String>? types,
    Map<String, String>? aliases,
  }) : peers = Map.unmodifiable(peers ?? {}),
       types = Map.unmodifiable(types ?? {}),
       aliases = Map.unmodifiable(aliases ?? {});

  final Map<String, String> peers;
  final Map<String, String> types;
  final Map<String, String> aliases;

  factory PeerState.decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    if (data['version'] != 2) {
      throw const FormatException('Unsupported peer state');
    }
    Map<String, String> read(String key) =>
        Map<String, String>.from(data[key] as Map);
    return PeerState(
      peers: read('peers'),
      types: read('types'),
      aliases: read('aliases'),
    );
  }

  String encode() => jsonEncode({
    'version': 2,
    'peers': peers,
    'types': types,
    'aliases': aliases,
  });

  String displayName(String id) => aliases[id] ?? peers[id] ?? id;

  PeerState add(String id, String name, String type) => PeerState(
    peers: {...peers, id: name},
    types: {...types, id: type},
    aliases: aliases,
  );

  PeerState setAlias(String id, String? alias) {
    if (!peers.containsKey(id)) return this;
    final next = Map<String, String>.from(aliases)..remove(id);
    if (alias != null && alias.isNotEmpty) next[id] = alias;
    if (next[id] == aliases[id]) return this;
    return PeerState(peers: peers, types: types, aliases: next);
  }

  PeerState updateInfo(String id, String name, String type) {
    if (!peers.containsKey(id) || (peers[id] == name && types[id] == type)) {
      return this;
    }
    return add(id, name, type);
  }

  PeerState remove(String id) {
    if (!peers.containsKey(id)) return this;
    return PeerState(
      peers: Map<String, String>.from(peers)..remove(id),
      types: Map<String, String>.from(types)..remove(id),
      aliases: Map<String, String>.from(aliases)..remove(id),
    );
  }
}
