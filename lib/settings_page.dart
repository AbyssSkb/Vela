import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_settings.dart';
import 'l10n/generated/app_localizations.dart';
import 'notice.dart';
import 'notification_settings.dart';
import 'received_storage.dart';
import 'app_update.dart';
import 'desktop_platform.dart';

class NameDialog extends StatefulWidget {
  const NameDialog({
    super.key,
    required this.title,
    required this.current,
    this.hint,
  });
  final String title, current;
  final String? hint;
  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final controller = TextEditingController(text: widget.current);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _cleanDeviceName(controller.text);
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(helperText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.profile,
    required this.language,
    required this.appearance,
    required this.deviceName,
    required this.systemDeviceName,
    required this.changeSetting,
    required this.rename,
    required this.relaySettings,
    required this.diagnostics,
    required this.backgroundChanged,
    this.updates,
  });
  final String profile, language, appearance, deviceName, systemDeviceName;
  final Future<void> Function(String, String) changeSetting;
  final Future<void> Function(String) rename;
  final Future<void> Function() relaySettings;
  final Future<void> Function() diagnostics;
  final Future<void> Function() backgroundChanged;
  final AppUpdateController? updates;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String language = widget.language;
  late String appearance = widget.appearance;
  late String name = widget.deviceName;
  static const receivedStorage = ReceivedStorage();
  bool macFocus = true, autoAccept = false;
  bool defaultSaveLocation = true, saveLocationAvailable = true;
  String? saveLocationLabel;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          macFocus =
              prefs.getBool('mac_focus_on_offer_${widget.profile}') ?? true;
          autoAccept = prefs.getBool('auto_accept_${widget.profile}') ?? false;
        });
      }
    });
    if (Platform.isAndroid ||
        Platform.isMacOS ||
        DesktopPlatform.isWindowsOrLinux) {
      unawaited(_loadSaveLocation());
    }
  }

  Future<void> _loadSaveLocation() async {
    try {
      final location = await receivedStorage.location();
      if (mounted) {
        setState(() {
          defaultSaveLocation = location.isDefault;
          saveLocationLabel = location.displayPath;
          saveLocationAvailable = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => saveLocationAvailable = false);
    }
  }

  Future<void> _chooseSaveLocation({bool reset = false}) async {
    final t = AppLocalizations.of(context)!;
    try {
      if (reset) {
        await receivedStorage.resetLocation();
      } else {
        await receivedStorage.chooseLocation();
      }
      await _loadSaveLocation();
    } catch (e) {
      debugPrint('Could not change save location: $e');
      if (mounted) {
        showNotice(context, t.saveLocationUnavailable, kind: NoticeKind.error);
      }
    }
  }

  Future<void> _rename() async {
    final t = AppLocalizations.of(context)!;
    final updated = await showDialog<String>(
      context: context,
      builder: (_) =>
          NameDialog(title: t.deviceName, current: name, hint: t.nameVisible),
    );
    if (updated == null || !mounted) return;
    try {
      await widget.rename(updated);
      if (mounted) setState(() => name = updated);
    } catch (_) {
      if (mounted) showNotice(context, t.storageFailed, kind: NoticeKind.error);
    }
  }

  Future<void> _choose(
    String key,
    String current,
    Map<String, String> choices,
  ) async {
    final t = AppLocalizations.of(context)!;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(key == 'language' ? t.language : t.appearance),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in choices.entries)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  title: Text(entry.value),
                  trailing: current == entry.key
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  selected: current == entry.key,
                  onTap: () => Navigator.pop(context, entry.key),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.cancel),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await widget.changeSetting(key, selected);
      if (mounted) {
        setState(() {
          if (key == 'language') {
            language = selected;
          } else {
            appearance = selected;
          }
        });
      }
    } catch (_) {
      if (mounted) showNotice(context, t.storageFailed, kind: NoticeKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final languages = {
      'system': t.systemDefault,
      'zh': t.simplifiedChinese,
      'en': t.english,
    };
    final appearances = {
      'system': t.systemDefault,
      'light': t.light,
      'dark': t.dark,
    };
    Widget row(
      IconData icon,
      String title,
      String value,
      VoidCallback onTap, {
      Widget? trailing,
    }) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: Icon(icon, color: colors.primary, size: 22),
      minLeadingWidth: 24,
      horizontalTitleGap: 16,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.onSurfaceVariant),
      ),
      trailing:
          trailing ??
          Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
      onTap: onTap,
    );
    Widget divider() => Divider(
      height: 1,
      indent: 60,
      endIndent: 20,
      color: colors.outlineVariant.withValues(alpha: 0.45),
    );
    Widget switchRow(
      IconData icon,
      String title,
      String subtitle,
      bool value,
      ValueChanged<bool> onChanged,
    ) => SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      secondary: Icon(icon, color: colors.primary, size: 22),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: colors.onSurfaceVariant),
      ),
      value: value,
      onChanged: onChanged,
    );
    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: colors.primary),
            ),
          ),
          Material(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                Platform.isMacOS ? 38 : 8,
                20,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        t.settings,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  section(t.settingsDevice, [
                    row(Icons.devices_outlined, t.deviceName, name, _rename),
                    divider(),
                    row(
                      Icons.dns_outlined,
                      t.relaySettings,
                      t.relaySettingsHint,
                      widget.relaySettings,
                    ),
                    divider(),
                    row(
                      Icons.monitor_heart_outlined,
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? '诊断'
                          : 'Diagnostics',
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? '查看连接状态与事件'
                          : 'Connection status and events',
                      widget.diagnostics,
                    ),
                  ]),
                  section(t.settingsReceiving, [
                    if (Platform.isAndroid ||
                        Platform.isMacOS ||
                        DesktopPlatform.isWindowsOrLinux) ...[
                      row(
                        Icons.folder_outlined,
                        t.saveLocation,
                        !saveLocationAvailable
                            ? t.saveLocationUnavailable
                            : defaultSaveLocation
                            ? t.downloadsFolder
                            : (saveLocationLabel ?? t.chooseFolder),
                        () => _chooseSaveLocation(),
                        trailing: !defaultSaveLocation || !saveLocationAvailable
                            ? IconButton(
                                tooltip: t.useDownloads,
                                onPressed: () =>
                                    _chooseSaveLocation(reset: true),
                                icon: const Icon(Icons.restart_alt_rounded),
                              )
                            : null,
                      ),
                      divider(),
                    ],
                    switchRow(
                      Icons.move_to_inbox_outlined,
                      t.autoAccept,
                      t.autoAcceptHint,
                      autoAccept,
                      (value) async {
                        final prefs = await SharedPreferences.getInstance();
                        if (await prefs.setBool(
                              'auto_accept_${widget.profile}',
                              value,
                            ) &&
                            mounted) {
                          setState(() => autoAccept = value);
                        }
                      },
                    ),
                    if (Platform.isMacOS) ...[
                      divider(),
                      switchRow(
                        Icons.open_in_new_rounded,
                        t.focusOnReceive,
                        t.focusOnReceiveHint,
                        macFocus,
                        (value) async {
                          final prefs = await SharedPreferences.getInstance();
                          if (await prefs.setBool(
                                'mac_focus_on_offer_${widget.profile}',
                                value,
                              ) &&
                              mounted) {
                            setState(() => macFocus = value);
                          }
                        },
                      ),
                    ],
                    if (Platform.isAndroid) ...[
                      divider(),
                      row(
                        Icons.notifications_outlined,
                        t.notificationSettings,
                        t.notificationChannelHint,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const NotificationSettingsPage(),
                          ),
                        ),
                      ),
                    ],
                    if (Platform.isAndroid ||
                        Platform.isMacOS ||
                        DesktopPlatform.isWindowsOrLinux) ...[
                      divider(),
                      row(
                        Icons.notifications_active_outlined,
                        t.backgroundReceiving,
                        t.backgroundDiagnostic,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => BackgroundSettingsPage(
                              profile: widget.profile,
                              onChanged: widget.backgroundChanged,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ]),
                  section(t.settingsDisplay, [
                    row(
                      Icons.language_rounded,
                      t.language,
                      languages[language] ?? t.systemDefault,
                      () => _choose('language', language, languages),
                    ),
                    divider(),
                    row(
                      Icons.palette_outlined,
                      t.appearance,
                      appearances[appearance] ?? t.systemDefault,
                      () => _choose('appearance', appearance, appearances),
                    ),
                  ]),
                  if (widget.updates != null) ...[
                    const SizedBox(height: 12),
                    AppUpdateTile(controller: widget.updates!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _cleanDeviceName(String value) => String.fromCharCodes(
  value.runes.where((c) => c >= 32 && !(c >= 127 && c <= 159)).take(60),
).trim();
