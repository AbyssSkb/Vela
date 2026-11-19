class PendingShare {
  PendingShare({
    List<String>? paths,
    List<String>? uris,
    this.text,
    this.typed = false,
    this.drop = false,
    this.stage,
    this.preferredPeer,
  }) : paths = paths == null ? null : List.unmodifiable(paths),
       uris = uris == null ? null : List.unmodifiable(uris) {
    final sources = [paths, uris, text].where((value) => value != null);
    if (sources.length != 1 ||
        !_validFiles(paths) ||
        !_validFiles(uris) ||
        stage == '' ||
        preferredPeer == '' ||
        (typed && text == null) ||
        (drop && paths == null)) {
      throw const FormatException('Invalid shared content');
    }
  }

  final List<String>? paths, uris;
  final String? text, stage;
  final String? preferredPeer;
  final bool typed, drop;

  bool get hasFiles => paths != null || uris != null;

  String? quickSendRecipient(Iterable<String> pairedPeers) {
    final peer = preferredPeer;
    if (peer == null) return pairedPeers.singleOrNull;
    return pairedPeers.contains(peer) ? peer : null;
  }

  factory PendingShare.fromMap(Map<dynamic, dynamic> value) {
    String? string(String key) {
      final item = value[key];
      if (item == null || item is String) return item as String?;
      throw FormatException('Invalid shared content field: $key');
    }

    bool flag(String key) {
      final item = value[key];
      if (item == null) return false;
      if (item is bool) return item;
      throw FormatException('Invalid shared content field: $key');
    }

    List<String>? files(String key) {
      final item = value[key];
      if (item == null) return null;
      if (item is! List || item.any((path) => path is! String)) {
        throw FormatException('Invalid shared content field: $key');
      }
      return item.cast<String>();
    }

    final uris = files('uris');
    final uri = string('uri');
    if (uris != null && uri != null) {
      throw const FormatException('Invalid shared content');
    }
    return PendingShare(
      paths: files('paths'),
      uris: uri == null ? uris : [uri],
      text: string('text'),
      typed: flag('typed'),
      drop: flag('drop'),
      stage: string('stage'),
      preferredPeer: string('preferredPeer'),
    );
  }

  static bool _validFiles(List<String>? files) =>
      files == null ||
      (files.isNotEmpty &&
          files.length <= 100 &&
          files.every((path) => path.isNotEmpty));
}
