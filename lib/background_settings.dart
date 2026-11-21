import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/generated/app_localizations.dart';
import 'notice.dart';
import 'page_layout.dart';
import 'settings_row_title.dart';

enum BackgroundReceiving {
  androidService('status'),
  macKeepAwake('macBackgroundStatus'),
  desktopTray('desktopStatus');

  const BackgroundReceiving(this.statusMethod);
  final String statusMethod;
  static const channel = MethodChannel('vela/background');

  static BackgroundReceiving? forOS(String os) => switch (os) {
    'android' => androidService,
    'macos' => macKeepAwake,
    'windows' || 'linux' => desktopTray,
    _ => null,
  };

  static BackgroundReceiving? get current => forOS(Platform.operatingSystem);

  String preferenceKey(String profile) => switch (this) {
    androidService => 'background_receive_$profile',
    macKeepAwake => 'mac_background_receiving',
    desktopTray => 'desktop_background_receiving',
  };

  bool get defaultEnabled => true;
  bool enabled(SharedPreferences? prefs, String profile) =>
      prefs?.getBool(preferenceKey(profile)) ?? defaultEnabled;

  Future<Map<Object?, Object?>> readStatus() async =>
      await channel.invokeMapMethod<Object?, Object?>(statusMethod) ?? {};

  String? recoverySettings(Map<Object?, Object?> status) {
    if (this != androidService) return null;
    return switch (status) {
      {'restricted': true} => 'battery',
      {'running': false} || {'nodeReady': false} => null,
      {'batteryExempt': false} => 'battery_exemption',
      _ => null,
    };
  }

  static bool _lowPowerStandbyRestricts(Map<Object?, Object?> status) =>
      status['lowPowerStandbyEnabled'] == true &&
      status['lowPowerStandbyExempt'] == false;

  bool needsAttention(bool? enabled, Map<Object?, Object?> status) =>
      enabled == true &&
      switch (this) {
        androidService =>
          recoverySettings(status) != null ||
              status['running'] == false ||
              status['nodeReady'] == false ||
              _lowPowerStandbyRestricts(status),
        macKeepAwake => status['active'] == false,
        desktopTray => status['trayAvailable'] == false,
      };

  String statusText(
    AppLocalizations t,
    bool? enabled,
    Map<Object?, Object?> status,
  ) => switch ((this, enabled)) {
    (_, null) => t.unknown,
    (macKeepAwake, false) => t.backgroundMacMaySleep,
    (macKeepAwake, true) => switch (status['active']) {
      true => t.backgroundMacAwake,
      false => t.backgroundMacInactive,
      _ => t.unknown,
    },
    (_, false) => t.backgroundStartHint,
    (desktopTray, true) => switch (status['trayAvailable']) {
      false => t.backgroundTrayUnavailable,
      true when status['running'] == true => t.backgroundTrayReady,
      _ => t.unknown,
    },
    (androidService, true) => switch (recoverySettings(status)) {
      'battery' => t.backgroundCheckBattery,
      'battery_exemption' => t.backgroundBatteryLimitsLockedReceiving,
      _ => switch (status) {
        {'running': false} ||
        {'nodeReady': false} => t.backgroundServiceStopped,
        _ when _lowPowerStandbyRestricts(status) =>
          t.backgroundLowPowerStandbyRestricted,
        {'running': true, 'nodeReady': true} => t.backgroundServiceReady,
        _ => t.unknown,
      },
    },
  };

  Future<void> setPreferenceEnabled(
    String profile,
    bool value, {
    String? readyMessage,
    Future<void> Function()? onChanged,
    Future<void> Function()? verify,
  }) async {
    final key = preferenceKey(profile);
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getBool(key);
    var serviceAttempted = false;
    var notified = false;
    try {
      if (!await prefs.setBool(key, value)) throw StateError('settings failed');
      serviceAttempted = true;
      await setEnabled(value, readyMessage: readyMessage);
      notified = onChanged != null;
      await onChanged?.call();
      await verify?.call();
    } catch (_) {
      try {
        if (previous == null) {
          await prefs.remove(key);
        } else {
          await prefs.setBool(key, previous);
        }
      } catch (_) {}
      if (serviceAttempted) {
        try {
          await setEnabled(
            previous ?? defaultEnabled,
            readyMessage: readyMessage,
          );
        } catch (_) {}
      }
      if (notified) {
        try {
          await onChanged?.call();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> setEnabled(bool value, {String? readyMessage}) async {
    switch (this) {
      case macKeepAwake:
        await channel.invokeMethod<void>('setMacBackground', value);
      case desktopTray:
        await channel.invokeMethod<void>('setDesktopBackground', value);
      case androidService:
        if (value) {
          final started = await channel.invokeMethod<bool>('start', {
            'message': readyMessage,
          });
          if (started != true) throw StateError('service start failed');
        } else {
          await channel.invokeMethod<void>('stop');
        }
    }
  }
}

class BackgroundSettingsPage extends StatefulWidget {
  const BackgroundSettingsPage({
    super.key,
    required this.profile,
    this.onChanged,
  });
  final String profile;
  final Future<void> Function()? onChanged;
  @override
  State<BackgroundSettingsPage> createState() => _BackgroundSettingsPageState();
}

class _BackgroundSettingsPageState extends State<BackgroundSettingsPage>
    with WidgetsBindingObserver {
  static const channel = BackgroundReceiving.channel;
  Map<Object?, Object?> status = {};
  bool? enabled;
  bool changing = false;
  static const setting = BackgroundReceiving.androidService;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh({bool strict = false}) async {
    Map<Object?, Object?> current = {};
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      current = await setting.readStatus();
    } catch (error) {
      if (strict) rethrow;
      debugPrint('Could not read background status: $error');
    }
    if (mounted) {
      setState(() {
        enabled = prefs == null ? null : setting.enabled(prefs, widget.profile);
        status = current;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() => changing = true);
    final readyMessage = AppLocalizations.of(context)!.backgroundReady;
    try {
      await setting.setPreferenceEnabled(
        widget.profile,
        value,
        readyMessage: readyMessage,
        onChanged: widget.onChanged,
        verify: () => _refresh(strict: true),
      );
    } catch (_) {
      if (mounted) {
        await _refresh();
        if (mounted) {
          showNotice(
            context,
            AppLocalizations.of(context)!.backgroundUnavailable,
            kind: NoticeKind.error,
          );
        }
      }
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  Future<void> _openSettings(String section) async {
    try {
      await channel.invokeMethod<void>('settings', {'section': section});
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          AppLocalizations.of(context)!.backgroundSettingsOpenFailed,
          kind: NoticeKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final manufacturer = (status['manufacturer'] as String? ?? '')
        .toLowerCase();
    final isOplus = ['oneplus', 'oppo', 'realme'].contains(manufacturer);
    final summary = setting.statusText(t, enabled, status);
    final recovery = setting.recoverySettings(status);
    final needsRetry =
        enabled == true &&
        (status['running'] == false || status['nodeReady'] == false);
    final needsAttention = setting.needsAttention(enabled, status);
    final detail =
        enabled == null || (needsAttention && (recovery == null || needsRetry))
        ? summary
        : null;
    final restricted = status['restricted'] == true;
    Widget recoveryButton(String label, VoidCallback? onPressed) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(onPressed: onPressed, child: Text(label)),
      ),
    );
    final exempt = status['batteryExempt'] as bool?;
    return Scaffold(
      body: PageLayout(
        header: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.backgroundReceiving,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(t.enableBackgroundReceiving),
                    subtitle: detail == null
                        ? null
                        : Text(
                            detail,
                            style: needsAttention
                                ? TextStyle(color: colors.error)
                                : null,
                          ),
                    value: enabled ?? false,
                    onChanged: changing || enabled == null ? null : _toggle,
                  ),
                  if (needsRetry)
                    recoveryButton(
                      t.retry,
                      changing ? null : () => _toggle(true),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      exempt == true
                          ? Icons.check_circle_outline_rounded
                          : Icons.info_outline_rounded,
                      color: exempt == true
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    title: SettingsRowTitle(
                      t.backgroundBattery,
                      value: Text(switch (exempt) {
                        true => t.backgroundBatteryExempt,
                        false => t.backgroundBatteryOptimized,
                        null => t.backgroundUnknown,
                      }),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openSettings('battery_exemption'),
                  ),
                  if (restricted) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      title: SettingsRowTitle(
                        t.backgroundRestricted,
                        value: Text(t.backgroundBatteryRestricted),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openSettings('battery'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    title: Text(t.backgroundAutoStart),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () =>
                        _openSettings(isOplus ? 'battery' : 'autostart'),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(t.backgroundVendorGuide),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => _openSettings('guide'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
