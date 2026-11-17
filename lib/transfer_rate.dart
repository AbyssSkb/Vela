int transferRateBytes({
  required bool sending,
  required int transferred,
  required int udpBytesSent,
}) => sending ? udpBytesSent : transferred;

class TransferRate {
  TransferRate({int initialBytes = 0}) : _previousBytes = initialBytes;
  int _previousBytes;
  int _previousMilliseconds = 0;
  double? bytesPerSecond;

  bool update(int bytes, int elapsedMilliseconds) {
    final elapsed = elapsedMilliseconds - _previousMilliseconds;
    if (elapsed < 1000) return false;
    final transferred = bytes - _previousBytes;
    bytesPerSecond = transferred < 0 ? null : transferred * 1000 / elapsed;
    _previousBytes = bytes;
    _previousMilliseconds = elapsedMilliseconds;
    return true;
  }
}
