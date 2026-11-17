import 'prepared_transfer.dart';

class SendSession {
  SendSession(this.content, {this.releaseSource});

  final PreparedTransfer content;
  final Future<void> Function()? releaseSource;
  SendRetry? _retry;
  Future<void>? _cleanup;

  Future<void> complete() async {
    try {
      await releaseSource?.call();
    } finally {
      await discard();
    }
  }

  Future<void> discard() {
    _retry = null;
    return _cleanup ??= content.cleanup();
  }

  SendRetry allowRetry() {
    if (_cleanup != null) throw StateError('Send session already released');
    return _retry = SendRetry._(this);
  }
}

class SendRetry {
  SendRetry._(this._session);
  SendSession? _session;

  SendSession? take() {
    final session = _session;
    _session = null;
    if (session == null || !identical(session._retry, this)) return null;
    session._retry = null;
    return session;
  }

  Future<void> dismiss() async {
    await take()?.discard();
  }
}
