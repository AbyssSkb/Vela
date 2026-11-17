import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/generated/app_localizations.dart';
import 'notice.dart';

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
  static const channel = MethodChannel('vela/background');
  Map<Object?, Object?> status = {};
  bool enabled = false, changing = false;
  bool get isMac => defaultTargetPlatform == TargetPlatform.macOS;
  bool get isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  String get preferenceKey => isMac
      ? 'mac_background_receiving'
      : isDesktop
      ? 'desktop_background_receiving'
      : 'background_receive_${widget.profile}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final current =
        await channel.invokeMapMethod<Object?, Object?>(
          isMac
              ? 'macBackgroundStatus'
              : isDesktop
              ? 'desktopStatus'
              : 'status',
        ) ??
        {};
    if (mounted) {
      setState(() {
        enabled = prefs.getBool(preferenceKey) ?? isDesktop;
        status = current;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() => changing = true);
    final key = preferenceKey;
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
      var success = true;
      if (isMac) {
        await channel.invokeMethod<void>('setMacBackground', value);
      } else if (isDesktop) {
        await channel.invokeMethod<void>('setDesktopBackground', value);
      } else if (value) {
        success =
            await channel.invokeMethod<bool>('start', {
              'message': readyMessage,
            }) ??
            false;
      } else {
        await channel.invokeMethod<void>('stop');
      }
      if (!success) throw StateError('service start failed');
      notified = widget.onChanged != null;
      await widget.onChanged?.call();
      await _refresh();
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
          if (isMac) {
            await channel.invokeMethod<void>(
              'setMacBackground',
              previous == true,
            );
          } else if (isDesktop) {
            await channel.invokeMethod<void>(
              'setDesktopBackground',
              previous ?? true,
            );
          } else if (previous == true) {
            await channel.invokeMethod<bool>('start', {
              'message': readyMessage,
            });
          } else {
            await channel.invokeMethod<void>('stop');
          }
        } catch (_) {}
      }
      if (notified) {
        try {
          await widget.onChanged?.call();
        } catch (_) {}
      }
      if (mounted) {
        try {
          await _refresh();
        } catch (_) {}
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
      await _refresh();
    } catch (_) {
      if (mounted) {
        try {
          await _refresh();
        } catch (_) {}
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
                    subtitle: Text(
                      isMac
                          ? t.macKeepAwakeHint
                          : isDesktop
                          ? t.desktopBackgroundHint
                          : t.backgroundDescription,
                    ),
                    value: enabled,
                    onChanged: changing ? null : _toggle,
                  ),
                ),
                if (isMac || isDesktop) ...[
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
                      if (isDesktop)
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
                        ? t.macKeepAwakeLimits
                        : isDesktop
                        ? t.desktopBackgroundLimits
                        : '${t.backgroundBatteryHint}\n\n${t.backgroundLimits}',
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
