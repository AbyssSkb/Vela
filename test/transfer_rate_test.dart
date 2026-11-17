import 'package:flutter_test/flutter_test.dart';
import 'package:vela/transfer_rate.dart';

void main() {
  test('calculates speed from byte deltas and elapsed time', () {
    final rate = TransferRate();
    expect(rate.update(1000, 500), isFalse);
    expect(rate.bytesPerSecond, isNull);
    expect(rate.update(3000, 1500), isTrue);
    expect(rate.bytesPerSecond, 2000);
    expect(rate.update(7096, 2500), isTrue);
    expect(rate.bytesPerSecond, 4096);
    expect(rate.update(7096, 3500), isTrue);
    expect(rate.bytesPerSecond, 0);
    expect(rate.update(1, 4500), isTrue);
    expect(rate.bytesPerSecond, isNull);
  });
  test('sender rate follows network traffic after the file was buffered', () {
    final rate = TransferRate(
      initialBytes: transferRateBytes(
        sending: true,
        transferred: 10000,
        udpBytesSent: 1000,
      ),
    );
    final next = transferRateBytes(
      sending: true,
      transferred: 10000,
      udpBytesSent: 5000,
    );
    expect(rate.update(next, 1000), isTrue);
    expect(rate.bytesPerSecond, 4000);
    expect(
      transferRateBytes(sending: false, transferred: 7000, udpBytesSent: 500),
      7000,
    );
  });
  test('starts measuring from the bytes already transferred', () {
    final rate = TransferRate(initialBytes: 4000);
    expect(rate.update(5000, 1000), isTrue);
    expect(rate.bytesPerSecond, 1000);
  });
}
