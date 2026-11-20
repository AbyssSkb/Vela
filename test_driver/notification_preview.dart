import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  final driver = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  try {
    final clear = args.length > 1 && args[1] == 'clear';
    final offer = args.length > 1 && args[1] == 'offer';
    final check = args.length > 1 && args[1] == 'result';
    final finish = args.length > 1 && args[1] == 'finish';
    final message = clear
        ? {'action': 'notification-clear-test'}
        : offer
        ? {'action': 'notification-offer-test'}
        : check
        ? {'action': 'notification-offer-result'}
        : finish
        ? {'action': 'notification-finish-test'}
        : {
            'action': 'notification-preview-test',
            'progress': args.length > 1 && args[1] == 'connect' ? null : 7,
          };
    final result = await driver.requestData(jsonEncode(message));
    if (result !=
        (clear
            ? 'cleared'
            : check
            ? 'accepted'
            : 'shown')) {
      throw StateError('Notification did not update: $result');
    }
    stdout.writeln(
      clear
          ? 'NOTIFICATION_CLEARED'
          : check
          ? 'NOTIFICATION_ACCEPTED'
          : 'NOTIFICATION_PREVIEW_SHOWN',
    );
  } finally {
    await driver.close();
  }
}
