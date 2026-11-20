import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/generated/app_localizations.dart';
import 'notice.dart';
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

  String? recoverySettings(
    Map<Object?, Object?> status, {
    required bool autoAccept,
  }) {
    if (this != androidService) return null;
    return switch (status) {
      {'allNotifications': false} when !autoAccept => 'notification_app',
      {'notifications': false} when !autoAccept => 'notification_requests',
      {'restricted': true} => 'battery',
      {'running': false} || {'nodeReady': false} => null,
      {'batteryExempt': false} => 'battery_exemption',
      _ => null,
    };
  }

  static bool _lowPowerStandbyRestricts(Map<Object?, Object?> status) =>
      status['lowPowerStandbyEnabled'] == true &&
      status['lowPowerStandbyExempt'] == false;

  bool needsAttention(
    bool? enabled,
    Map<Object?, Object?> status, {
    required bool autoAccept,
  }) =>
      enabled == true &&
      switch (this) {
        androidService =>
          recoverySettings(status, autoAccept: autoAccept) != null ||
              status['running'] == false ||
              status['nodeReady'] == false ||
              _lowPowerStandbyRestricts(status),
        macKeepAwake => status['active'] == false,
        desktopTray => status['trayAvailable'] == false,
      };

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
      false => t.backgroundMacInactive,
      _ => t.unknown,
    },
    (_, false) => t.backgroundStartHint,
    (desktopTray, true) => switch (status['trayAvailable']) {
      false => t.backgroundTrayUnavailable,
      true when status['running'] == true => t.backgroundTrayReady,
      _ => t.unknown,
    },
    (androidService, true) => switch (recoverySettings(
      status,
      autoAccept: autoAccept,
    )) {
      'notification_app' => t.backgroundAppNotificationsOff,
      'notification_requests' => t.backgroundAllowRequests,
      'battery' => t.backgroundCheckBattery,
      'battery_exemption' => t.backgroundBatteryLimitsLockedReceiving,
      _ => switch (status) {
        {'running': false} ||
        {'nodeReady': false} => t.backgroundServiceStopped,
        _ when _lowPowerStandbyRestricts(status) =>
          t.backgroundLowPowerStandbyRestricted,
        {'running': true, 'nodeReady': true}
            when status['notifications'] == true || autoAccept =>
          t.backgroundServiceReady,
        _ => t.unknown,
      },
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
      if (mounted &&
          isMac &&
          value &&
          status['loginStatus'] == 'requiresApproval') {
        final t = AppLocalizations.of(context)!;
        showNotice(
          context,
          t.backgroundLoginApproval,
          actionLabel: t.backgroundOpenLoginSettings,
          onAction: () => _openSettings('login'),
        );
      }
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

  Future<void> _openSettings(String section) async {
    try {
      await channel.invokeMethod<void>('settings', {'section': section});
      if (mounted && isMac && section == 'notification_requests') {
        await _refresh();
      }
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
    final checkRequests = !autoAccept;
    final summary = setting.statusText(
      t,
      enabled,
      status,
      autoAccept: autoAccept,
    );
    final recovery = setting.recoverySettings(status, autoAccept: autoAccept);
    final needsRetry =
        setting == BackgroundReceiving.androidService &&
        enabled == true &&
        (status['running'] == false || status['nodeReady'] == false);
    final needsAttention = setting.needsAttention(
      enabled,
      status,
      autoAccept: autoAccept,
    );
    final detail =
        enabled == null || (needsAttention && (recovery == null || needsRetry))
        ? summary
        : null;
    final restricted = status['restricted'] == true;
    final login = status['loginStatus'];
    Widget recoveryButton(String label, VoidCallback? onPressed) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(onPressed: onPressed, child: Text(label)),
      ),
    );
    Widget check(
      String title,
      bool? ok,
      String section, {
      String? whenAllowed,
      String? whenBlocked,
    }) => ListTile(
      leading: Icon(
        ok == true
            ? Icons.check_circle_outline_rounded
            : Icons.info_outline_rounded,
        color: ok == true ? colors.primary : colors.onSurfaceVariant,
      ),
      title: SettingsRowTitle(
        title,
        value: Text(
          ok == null
              ? t.backgroundUnknown
              : ok
              ? (whenAllowed ?? t.backgroundAllowed)
              : (whenBlocked ?? t.backgroundNeedsAttention),
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _openSettings(section),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, isMac ? 38 : 8, 20, 24),
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
                const SizedBox(height: 16),
                Material(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text(
                          isMac ? t.macKeepAwake : t.enableBackgroundReceiving,
                        ),
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
                      if ((isMac || usesTray) &&
                          status['loginSupported'] == true) ...[
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SwitchListTile(
                          title: Text(t.backgroundLogin),
                          value:
                              login == 'enabled' || login == 'requiresApproval',
                          onChanged: changing ? null : _toggleLogin,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!usesTray && (!isMac || checkRequests)) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        if (checkRequests)
                          check(
                            t.notificationRequests,
                            status['allNotifications'] == false
                                ? false
                                : status['notifications'] as bool?,
                            status['allNotifications'] == false
                                ? 'notification_app'
                                : 'notification_requests',
                            whenBlocked: t.backgroundOff,
                          ),
                        if (!isMac) ...[
                          if (checkRequests)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                          check(
                            t.backgroundBattery,
                            restricted
                                ? false
                                : status['batteryExempt'] as bool?,
                            !restricted && status['batteryExempt'] == false
                                ? 'battery_exemption'
                                : 'battery',
                            whenAllowed: t.backgroundBatteryExempt,
                            whenBlocked: restricted
                                ? t.backgroundBatteryRestricted
                                : t.backgroundBatteryOptimized,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (!isMac && !usesTray) ...[
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
