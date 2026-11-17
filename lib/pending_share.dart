class PendingShare {
  PendingShare({
    List<String>? paths,
    List<String>? uris,
    this.uri,
    this.text,
    this.typed = false,
    this.drop = false,
    this.stage,
  }) : paths = paths == null ? null : List.unmodifiable(paths),
       uris = uris == null ? null : List.unmodifiable(uris) {
    final sources = [paths, uris, uri, text].where((value) => value != null);
    if (sources.length != 1 ||
        !_validFiles(paths) ||
        !_validFiles(uris) ||
        uri == '' ||
        stage == '' ||
        (typed && text == null) ||
        (drop && paths == null)) {
      throw const FormatException('Invalid shared content');
    }
  }

  final List<String>? paths, uris;
  final String? uri, text, stage;
  final bool typed, drop;

  bool get hasFiles => paths != null || uris != null || uri != null;

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

    return PendingShare(
      paths: files('paths'),
      uris: files('uris'),
      uri: string('uri'),
      text: string('text'),
      typed: flag('typed'),
      drop: flag('drop'),
      stage: string('stage'),
    );
  }

  static bool _validFiles(List<String>? files) =>
      files == null ||
      (files.isNotEmpty &&
          files.length <= 100 &&
          files.every((path) => path.isNotEmpty));
}
