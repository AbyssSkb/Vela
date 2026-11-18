import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela/device_pair_dialog.dart';
import 'package:vela/main.dart';
import 'package:vela/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('invalid device code feedback fits a narrow dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final t = lookupAppLocalizations(const Locale('en'));
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AddDeviceDialog()),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-peer')));
    await tester.pumpAndSettle();
    final error = find.text(t.invalidDeviceCode);
    expect(error, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(error).didExceedMaxLines,
      false,
    );
  });

  test('accepts only Vela device codes', () {
    final id = 'ab' * 32;
    expect(deviceIdFromQr('vela:1:$id'), id);
    expect(deviceIdFromQr(id), isNull);
    expect(deviceIdFromQr('vela:1:${'z' * 64}'), isNull);
    expect(deviceIdFromQr('vela:2:$id'), isNull);
    expect(deviceIdFromQr('vela:1:${id}0'), isNull);
  });

  test('clipboard preparation errors describe the cause without implying a transfer started', () {
    final t = lookupAppLocalizations(const Locale('zh'));
    expect(
      sendErrorMessage(
        StateError(t.emptyClipboard),
        transferStarted: false,
        clipboard: true,
        shared: false,
        translations: t,
      ),
      '剪贴板没有可发送的内容',
    );
    expect(
      sendErrorMessage(
        Exception('permission denied'),
        transferStarted: false,
        clipboard: true,
        shared: false,
        translations: t,
      ),
      '无法读取剪贴板，请重新复制后重试',
    );
    expect(
      sendErrorMessage(
        Exception('[vela:declined] transfer declined'),
        transferStarted: true,
        clipboard: true,
        shared: false,
        translations: t,
      ),
      '对方拒绝了接收',
    );
  });

  test('device codes and transfer errors have useful feedback', () {
    expect(isDeviceId('ab' * 32), isTrue);
    expect(isDeviceId('ab' * 31), isFalse);
    expect(isDeviceId('z' * 64), isFalse);
    expect(
      transferErrorMessage(Exception('[vela:declined] changed wording')),
      '对方拒绝了接收',
    );
    expect(transferErrorMessage(StateError('剪贴板为空')), '剪贴板为空');
    expect(transferErrorMessage(Exception('/private/path')), '传输中断，请重试');
  });
}
