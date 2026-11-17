const folderArchiveSuffix = '.vela-folder.zip';

enum TransferKind {
  file('file'),
  text('text'),
  typedText('typed_text'),
  image('image'),
  clipboardFile('clipboard_file'),
  batch('batch');

  const TransferKind(this.wireName);
  final String wireName;

  static TransferKind fromWire(String value) => values.firstWhere(
    (kind) => kind.wireName == value,
    orElse: () => throw FormatException('Unknown transfer kind: $value'),
  );

  bool get isText => this == text || this == typedText;
  bool get isFile => this == file || this == clipboardFile || this == batch;
  bool get copiesTextToClipboard => this == text;

  HistoryKind historyKind(String filename) => switch (this) {
    file when filename.endsWith(folderArchiveSuffix) =>
      HistoryKind.folderArchive,
    file || batch => HistoryKind.file,
    text => HistoryKind.text,
    typedText => HistoryKind.typedText,
    image => HistoryKind.image,
    clipboardFile => HistoryKind.clipboardFile,
  };
}

enum HistoryKind {
  file('file'),
  text('text'),
  typedText('typed_text'),
  image('image'),
  clipboardFile('clipboard_file'),
  folderArchive('folder_archive');

  const HistoryKind(this.storageName);
  final String storageName;

  static HistoryKind fromStorage(String value) => values.firstWhere(
    (kind) => kind.storageName == value,
    orElse: () => throw FormatException('Unknown history kind: $value'),
  );

  bool get isText => this == text || this == typedText;
  bool get isFile =>
      this == file || this == clipboardFile || this == folderArchive;
  bool get canRestoreFolder => this == folderArchive;
}
