import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/generated/app_localizations.dart';
import 'notice.dart';

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

  bool get defaultEnabled => this == desktopTray;
  bool enabled(SharedPreferences? prefs, String profile) =>
      prefs?.getBool(preferenceKey(profile)) ?? defaultEnabled;

  Future<Map<Object?, Object?>> readStatus() async =>
      await channel.invokeMapMethod<Object?, Object?>(statusMethod) ?? {};

  String statusText(
    AppLocalizations t,
    bool? enabled,
    Map<Object?, Object?> status, {
    required bool autoAccept,
  }) => switch ((this, enabled)) {
    (_, null) => t.unknown,
    (macKeepAwake, false) => t.backgroundMacMaySleep,
    (macKeepAwake, true) => switch (status['active']) {
      true => t.backgroundMacAwake,
      false => t.backgroundNeedsAttention,
      _ => t.unknown,
    },
    (_, false) => t.backgroundStartHint,
    (desktopTray, true) => switch (status['trayAvailable']) {
      false => t.backgroundTrayUnavailable,
      true when status['running'] == true => t.backgroundTrayReady,
      _ => t.unknown,
    },
    (androidService, true) => switch (status) {
      {'running': false} || {'nodeReady': false} => t.backgroundServiceStopped,
      {'notifications': false} when !autoAccept => t.backgroundAllowRequests,
      {'restricted': true} ||
      {'batteryExempt': false} ||
      {
        'lowPowerStandbyEnabled': true,
        'lowPowerStandbyExempt': false,
      } => t.backgroundCheckBattery,
      {'running': true, 'nodeReady': true}
          when status['notifications'] == true || autoAccept =>
        t.backgroundServiceReady,
      _ => t.unknown,
    },
  };

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
  bool autoAccept = false, changing = false;
  BackgroundReceiving get setting =>
      BackgroundReceiving.forOS(defaultTargetPlatform.name.toLowerCase()) ??
      BackgroundReceiving.androidService;
  bool get isMac => setting == BackgroundReceiving.macKeepAwake;
  bool get usesTray => setting == BackgroundReceiving.desktopTray;
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
        autoAccept = prefs?.getBool('auto_accept_${widget.profile}') ?? false;
        status = current;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() => changing = true);
    final key = setting.preferenceKey(widget.profile);
    SharedPreferences? prefs;
    bool? previous;
    var saved = false;
    var serviceAttempted = false;
    var notified = false;
    final readyMessage = AppLocalizations.of(context)!.backgroundReady;
    try {
      prefs = await SharedPreferences.getInstance();
      previous = prefs.getBool(key);
      saved = true;
      if (!await prefs.setBool(key, value)) throw StateError('settings failed');
      serviceAttempted = true;
      await setting.setEnabled(value, readyMessage: readyMessage);
      notified = widget.onChanged != null;
      await widget.onChanged?.call();
      await _refresh(strict: true);
    } catch (_) {
      if (saved && prefs != null) {
        try {
          if (previous == null) {
            await prefs.remove(key);
          } else {
            await prefs.setBool(key, previous);
          }
        } catch (_) {}
      }
      if (serviceAttempted) {
        try {
          await setting.setEnabled(
            previous ?? setting.defaultEnabled,
            readyMessage: readyMessage,
          );
        } catch (_) {}
      }
      if (notified) {
        try {
          await widget.onChanged?.call();
        } catch (_) {}
      }
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

  Future<void> _toggleLogin(bool value) async {
    setState(() => changing = true);
    try {
      await channel.invokeMethod<String>('setLaunchAtLogin', value);
      await _refresh(strict: true);
    } catch (_) {
      if (mounted) {
        await _refresh();
        if (mounted) {
          showNotice(
            context,
            AppLocalizations.of(context)!.backgroundLoginFailed,
            kind: NoticeKind.error,
          );
        }
      }
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final manufacturer = (status['manufacturer'] as String? ?? '')
        .toLowerCase();
    final isOplus = ['oneplus', 'oppo', 'realme'].contains(manufacturer);
    final summary = setting.statusText(
      t,
      enabled,
      status,
      autoAccept: autoAccept,
    );
    Widget check(String title, bool? ok, String? section) => ListTile(
      leading: Icon(
        ok == true
            ? Icons.check_circle_outline_rounded
            : Icons.info_outline_rounded,
        color: ok == true ? colors.primary : colors.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(
        ok == null
            ? t.backgroundUnknown
            : ok
            ? t.backgroundAllowed
            : t.backgroundNeedsAttention,
      ),
      trailing: section == null
          ? null
          : const Icon(Icons.chevron_right_rounded),
      onTap: section == null
          ? null
          : () => channel.invokeMethod<void>('settings', {'section': section}),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: MaterialLocalizations.of(context)
                          .backButtonTooltip,
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
                const SizedBox(height: 24),
                Material(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  child: SwitchListTile(
                    title: Text(isMac ? t.macKeepAwake : t.backgroundReceiving),
                    subtitle: Text(summary),
                    value: enabled ?? false,
                    onChanged: changing || enabled == null ? null : _toggle,
                  ),
                ),
                if (isMac || usesTray) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    child: SwitchListTile(
                      title: Text(t.backgroundLogin),
                      subtitle: Text(switch (status['loginStatus']) {
                        'enabled' => t.backgroundAllowed,
                        'notRegistered' => t.backgroundOff,
                        'requiresApproval' => t.backgroundLoginApproval,
                        'notFound' => t.backgroundLoginNotFound,
                        'unsupported' => t.backgroundLoginUnsupported,
                        _ => t.backgroundUnknown,
                      }),
                      value:
                          status['loginStatus'] == 'enabled' ||
                          status['loginStatus'] == 'requiresApproval',
                      onChanged:
                          changing ||
                              status['loginSupported'] != true ||
                              status['loginStatus'] == 'notFound'
                          ? null
                          : _toggleLogin,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    t.backgroundDiagnostic,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      if (usesTray)
                        check(
                          t.desktopTray,
                          status['trayAvailable'] as bool?,
                          null,
                        )
                      else if (isMac)
                        check(
                          t.macKeepAwakeActive,
                          status['active'] as bool?,
                          null,
                        )
                      else ...[
                        check(
                          t.backgroundRunning,
                          status['running'] as bool?,
                          null,
                        ),
                        ListTile(
                          leading: Icon(
                            status['nodeReady'] == true
                                ? Icons.check_circle_outline_rounded
                                : Icons.info_outline_rounded,
                            color: status['nodeReady'] == true
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          title: Text(t.backgroundNode),
                          subtitle: Text(
                            status['nodeReady'] == true
                                ? t.backgroundNodeInitialized
                                : status['nodeReady'] == false
                                ? t.backgroundNodeNotInitialized
                                : t.backgroundUnknown,
                          ),
                        ),
                        check(
                          t.backgroundNotification,
                          status['notifications'] as bool?,
                          'notifications',
                        ),
                        check(
                          t.backgroundBattery,
                          status['batteryExempt'] as bool?,
                          'battery',
                        ),
                        check(
                          t.backgroundRestricted,
                          status['restricted'] is bool
                              ? status['restricted'] == false
                              : null,
                          'battery',
                        ),
                        if (status['lowPowerStandbyEnabled'] == true)
                          check(
                            t.backgroundLowPowerStandby,
                            status['lowPowerStandbyExempt'] as bool?,
                            null,
                          ),
                        ListTile(
                          leading: const Icon(Icons.open_in_new_rounded),
                          title: Text(t.backgroundAutoStart),
                          subtitle: Text(
                            isOplus
                                ? t.backgroundAutoStartOplusHint
                                : t.backgroundAutoStartHint,
                          ),
                          onTap: () => channel.invokeMethod<void>('settings', {
                            'section': 'autostart',
                          }),
                        ),
                        ListTile(
                          leading: const Icon(Icons.open_in_new_rounded),
                          title: Text(t.backgroundVendorGuide),
                          onTap: () => channel.invokeMethod<void>('settings', {
                            'section': 'guide',
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    isMac
                        ? '${t.macKeepAwakeHint}\n\n${t.macKeepAwakeLimits}'
                        : usesTray
                        ? '${t.desktopBackgroundHint}\n\n${t.desktopBackgroundLimits}'
                        : '${t.backgroundDescription}\n\n${t.backgroundLimits}',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
