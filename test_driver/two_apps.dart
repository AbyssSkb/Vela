import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<String> readId(FlutterDriver driver) async {
  await driver.waitFor(
    find.byTooltip('我的设备'),
    timeout: const Duration(seconds: 30),
  );
  await driver.tap(find.byTooltip('我的设备'));
  final id = await driver.getText(find.byValueKey('device-id'));
  await driver.tap(find.text('关闭'));
  return id;
}

Future<void> addPeer(
  FlutterDriver sender,
  FlutterDriver receiver,
  String id,
  String senderName,
  String receiverName,
) async {
  await sender.tap(find.byValueKey('add-device'));
  await sender.tap(find.byValueKey('peer-id'));
  await sender.enterText(id);
  await sender.tap(find.byValueKey('confirm-peer'));
  await receiver.waitFor(
    find.byValueKey('accept-pair'),
    timeout: const Duration(seconds: 75),
  );
  await receiver.tap(find.byValueKey('accept-pair'));
  await sender.waitFor(
    find.text(receiverName),
    timeout: const Duration(seconds: 75),
  );
  await receiver.waitFor(
    find.text(senderName),
    timeout: const Duration(seconds: 75),
  );
}

Future<void> checkValidation(FlutterDriver driver) async {
  await driver.tap(find.byValueKey('add-device'));
  await driver.tap(find.byValueKey('peer-id'));
  await driver.enterText('invalid');
  await driver.tap(find.byValueKey('confirm-peer'));
  await driver.waitFor(find.text('请输入 64 位设备码'));
  await driver.tap(find.text('取消'));
}

Future<void> sendAndAccept(
  FlutterDriver sender,
  FlutterDriver receiver,
  String peerId,
  String peerName,
) async {
  final result = await sender.requestData(
    jsonEncode({'action': 'send', 'peer': peerId, 'content': '双向文件测试内容'}),
  );
  if (result != 'started') throw StateError('send did not start: $result');
  await receiver.waitFor(
    find.byValueKey('accept-offer'),
    timeout: const Duration(seconds: 75),
  );
  await receiver.tap(find.byValueKey('accept-offer'));
  await sender.waitFor(
    find.text('已发送给 $peerName'),
    timeout: const Duration(seconds: 75),
  );
  final senderBottom = await sender.getBottomRight(find.byType('Scaffold'));
  final sentNotice = await sender.getTopLeft(find.text('已发送给 $peerName'));
  if (sentNotice.dy < senderBottom.dy - 180) {
    throw StateError('sent notice is not at the bottom');
  }
  await sender.waitForAbsent(find.byValueKey('activity-status'));
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  String status;
  while (true) {
    final state = jsonDecode(
      await receiver.requestData(jsonEncode({'action': 'state'})),
    ) as Map;
    status = state['activity'] as String? ?? '';
    if (state['busy'] == false && status.startsWith('已接收 ')) break;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('receiver did not finish');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await receiver.waitFor(find.text(status));
  await receiver.waitFor(find.byValueKey('notice-action'));
  await receiver.waitForAbsent(find.byValueKey('activity-status'));
  final bottom = await receiver.getBottomRight(find.byType('Scaffold'));
  final notice = await receiver.getTopLeft(find.text(status));
  if (notice.dy < bottom.dy - 180) {
    throw StateError('received notice is not at the bottom');
  }
  stdout.writeln('UI send and accept passed: $peerName');
}

Future<void> clipboardRoundTrip(
  FlutterDriver sender,
  FlutterDriver receiver,
  String peerId,
  String peerName,
  String kind,
) async {
  const png =
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGP4z8DAAMIM/4EAAB/uBfsL2WiLAAAAAElFTkSuQmCC';
  final expected = kind == 'image' ? png : 'clipboard-$kind-内容';
  stdout.writeln('clipboard $kind: set');
  await sender.requestData(
    jsonEncode({'action': 'set-clipboard', 'kind': kind, 'content': expected}),
  );
  stdout.writeln('clipboard $kind: tap');
  await sender.tap(find.byValueKey('send-clipboard'));
  await sender.tap(find.byValueKey('send-recipient-$peerId'));
  stdout.writeln('clipboard $kind: waiting for offer');
  try {
    await receiver.waitFor(
      find.byValueKey('accept-offer'),
      timeout: const Duration(seconds: 15),
    );
  } catch (_) {
    stdout.writeln(
      'sender state: ${await sender.requestData(jsonEncode({'action': 'state'}))}',
    );
    rethrow;
  }
  stdout.writeln('clipboard $kind: offer arrived');
  await receiver.requestData(
    jsonEncode({
      'action': 'set-clipboard',
      'kind': 'text',
      'content': 'temporary sentinel',
    }),
  );
  await receiver.tap(find.byValueKey('accept-offer'));
  await receiver.waitFor(
    find.text('剪贴板内容已接收'),
    timeout: const Duration(seconds: 75),
  );
  await receiver.waitFor(find.byValueKey('notice-action'));
  stdout.writeln('clipboard $kind: received');
  await sender.waitFor(
    find.text('已发送给 $peerName'),
    timeout: const Duration(seconds: 75),
  );
  final actual = await receiver.requestData(
    jsonEncode({'action': 'get-clipboard', 'kind': kind}),
  );
  if (actual != (kind == 'image' ? 'image' : expected)) {
    throw StateError('clipboard $kind mismatch');
  }
  stdout.writeln('UI clipboard $kind passed');
}

Future<void> main(List<String> args) async {
  final a = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final b = await FlutterDriver.connect(dartVmServiceUrl: args[1]);
  try {
    stdout.writeln('reading device A');
    final idA = await readId(a);
    stdout.writeln('reading device B');
    final idB = await readId(b);
    if (idA == idB) throw StateError('identities are not independent');
    final nameA =
        (jsonDecode(await a.requestData(jsonEncode({'action': 'device'})))
                as Map)['name']
            as String;
    final nameB =
        (jsonDecode(await b.requestData(jsonEncode({'action': 'device'})))
                as Map)['name']
            as String;
    await checkValidation(a);
    stdout.writeln('pairing A');
    await addPeer(a, b, idB, nameA, nameB);
    await sendAndAccept(a, b, idB, nameB);
    await sendAndAccept(b, a, idA, nameA);
    for (final kind in ['text', 'image', 'file']) {
      await clipboardRoundTrip(a, b, idB, nameB, kind);
      await clipboardRoundTrip(b, a, idA, nameA, kind);
    }
    await a.tap(find.byValueKey('peer-$idB'));
    await a.tap(find.text('移除设备'));
    await a.waitFor(find.text('移除设备？'));
    await a.tap(find.text('取消'));
    await a.waitFor(find.text(nameB));
    stdout.writeln('TWO_APP_UI_TEST_OK');
  } finally {
    await a.close();
    await b.close();
  }
}
