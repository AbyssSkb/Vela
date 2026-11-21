import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vela/home_device_widgets.dart';
import 'package:vela/main.dart' as vela;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts the Vela node and detects the iOS device', (
    tester,
  ) async {
    // XCTest can enable platform semantics while the startup test is running.
    tester.platformDispatcher.semanticsEnabledTestValue = false;
    addTearDown(tester.platformDispatcher.clearSemanticsEnabledTestValue);
    await vela.main([]);
    final ready = find.byType(EmptyDevicesSliver);
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (ready.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(ready, findsOneWidget);

    final device = await const MethodChannel('vela/device')
        .invokeMapMethod<String, String>('info');
    const expected = String.fromEnvironment('VELA_SIMULATOR_DEVICE');
    expect(device?['type'], expected);
    expect(device?['name'], isNotEmpty);
  }, semanticsEnabled: false);
}
