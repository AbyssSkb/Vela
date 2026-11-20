import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela/incoming_offer_prompt.dart';

void main() {
  const channel = MethodChannel('vela/background');

  test('only a matching notification button can decide this offer', () async {
    final prompt = IncomingOfferPrompt(channel, notificationId: 'current');
    prompt.notificationDecision('invalid payload');
    prompt.notificationDecision({'id': 'previous', 'accepted': true});
    prompt.notificationDecision({'id': 'current', 'accepted': 'yes'});
    expect(prompt.decidedAction, isNull);
    prompt.notificationDecision({'id': 'current', 'accepted': false});
    prompt.notificationDecision({'id': 'current', 'accepted': true});
    prompt.becameVisible();
    expect(await prompt.decidedAction, BackgroundOfferAction.decline);
  });

  test('returning to the app takes precedence over a later button', () async {
    final prompt = IncomingOfferPrompt(channel, notificationId: 'current');
    prompt.becameVisible();
    prompt.notificationDecision({'id': 'current', 'accepted': true});
    expect(await prompt.decidedAction, BackgroundOfferAction.showDialog);
  });
}
