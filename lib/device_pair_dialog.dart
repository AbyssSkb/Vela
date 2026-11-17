import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'l10n/generated/app_localizations.dart';

class AddDeviceDialog extends StatefulWidget {
  const AddDeviceDialog({super.key});
  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> {
  final id = TextEditingController();
  String? idError;
  @override
  void dispose() {
    id.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final value = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _ScanDevicePage()));
    if (mounted && value != null) {
      setState(() {
        id.text = value;
        idError = null;
      });
    }
  }

  void _submit() {
    final deviceId = id.text.trim().toLowerCase();
    setState(() {
      idError = isDeviceId(deviceId)
          ? null
          : AppLocalizations.of(context)!.invalidDeviceCode;
    });
    if (idError == null) Navigator.pop(context, deviceId);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(t.addDevice),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Platform.isAndroid ? t.enterOrScan : t.enterCode,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('peer-id'),
                controller: id,
                onChanged: (_) {
                  if (idError != null) setState(() => idError = null);
                },
                onSubmitted: (_) => _submit(),
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: t.deviceCode,
                  errorText: idError,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: const OutlineInputBorder(),
                  suffixIcon: Platform.isAndroid
                      ? IconButton(
                          tooltip: t.scanCode,
                          onPressed: _scan,
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(
          key: const ValueKey('confirm-peer'),
          onPressed: _submit,
          child: Text(t.connect),
        ),
      ],
    );
  }
}

bool isDeviceId(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

String? deviceIdFromQr(String value) {
  final match = RegExp(r'^vela:1:([0-9a-f]{64})$').firstMatch(value);
  return match?.group(1);
}

class _ScanDevicePage extends StatefulWidget {
  const _ScanDevicePage();
  @override
  State<_ScanDevicePage> createState() => _ScanDevicePageState();
}

class _ScanDevicePageState extends State<_ScanDevicePage> {
  bool scanned = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context)!.scanTitle)),
    body: MobileScanner(
      errorBuilder: (_, _) =>
          Center(child: Text(AppLocalizations.of(context)!.cameraError)),
      onDetect: (capture) {
        if (scanned) return;
        for (final barcode in capture.barcodes) {
          final value = deviceIdFromQr(barcode.rawValue ?? '');
          if (value != null) {
            scanned = true;
            Navigator.pop(context, value);
            return;
          }
        }
      },
    ),
  );
}
