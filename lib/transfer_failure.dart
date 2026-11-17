enum TransferFailure {
  cancelled,
  declined,
  saveFailed,
  pairingDeclined,
  unknown,
}

// These codes are emitted by Rust; the explanation after them is diagnostic text.
TransferFailure classifyTransferFailure(Object error) {
  final match = RegExp(r'\[vela:([a-z_]+)\]').firstMatch(error.toString());
  return switch (match?.group(1)) {
    'cancelled' => TransferFailure.cancelled,
    'declined' => TransferFailure.declined,
    'save_failed' => TransferFailure.saveFailed,
    'pairing_declined' => TransferFailure.pairingDeclined,
    _ => TransferFailure.unknown,
  };
}
