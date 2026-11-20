import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_settings.dart';
import 'l10n/generated/app_localizations.dart';
import 'notice.dart';
import 'notification_settings.dart';
import 'received_storage.dart';
import 'settings_row_title.dart';
import 'app_update.dart';
import 'app_update_tile.dart';
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
  bool invalidName = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _cleanDeviceName(controller.text);
    if (value.isEmpty) {
      setState(() => invalidName = true);
      return;
    }
    Navigator.pop(context, value);
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
        decoration: InputDecoration(
          helperText: widget.hint,
          helperMaxLines: 3,
          errorText: invalidName ? t.deviceNameRequired : null,
        ),
        onChanged: (_) {
          if (invalidName) setState(() => invalidName = false);
        },
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
    this.openGuide,
    this.updates,
  });
  final String profile, language, appearance, deviceName, systemDeviceName;
  final Future<void> Function(String, String) changeSetting;
  final Future<void> Function(String) rename;
  final Future<void> Function() relaySettings;
  final Future<void> Function() diagnostics;
  final Future<void> Function() backgroundChanged;
  final VoidCallback? openGuide;
  final AppUpdateController? updates;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  late String language = widget.language;
  late String appearance = widget.appearance;
  late String name = widget.deviceName;
  static const receivedStorage = ReceivedStorage();
  bool openAfterReceive = false, autoAccept = false;
  bool defaultSaveLocation = true, saveLocationAvailable = true;
  String? saveLocationLabel;
  BackgroundReceiving? get background =>
      BackgroundReceiving.forOS(defaultTargetPlatform.name.toLowerCase());
  bool? backgroundEnabled;
  Map<Object?, Object?> backgroundStatus = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshBackground());
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          openAfterReceive =
              prefs.getBool(
                DesktopPlatform.openAfterReceiveKey(widget.profile),
              ) ??
              false;
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshBackground());
  }

  Future<void> _refreshBackground() async {
    final setting = background;
    if (setting == null) return;
    bool? enabled;
    Map<Object?, Object?> status = {};
    try {
      enabled = setting.enabled(
        await SharedPreferences.getInstance(),
        widget.profile,
      );
      status = await setting.readStatus();
    } catch (error) {
      debugPrint('Could not read background status: $error');
    }
    if (mounted) {
      setState(() {
        backgroundEnabled = enabled;
        backgroundStatus = status;
      });
    }
  }

  Future<void> _showBackgroundSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BackgroundSettingsPage(
          profile: widget.profile,
          onChanged: widget.backgroundChanged,
        ),
      ),
    );
    if (mounted) await _refreshBackground();
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
      builder: (_) => NameDialog(title: t.deviceName, current: name),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final background = this.background;
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
      VoidCallback onTap, {
      String? value,
      Widget? trailing,
    }) => ListTile(
      leading: Icon(icon, size: 20),
      title: SettingsRowTitle(title, value: value == null ? null : Text(value)),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
    Widget divider() => Divider(
      height: 1,
      indent: 52,
      endIndent: 16,
      color: colors.outlineVariant.withValues(alpha: 0.55),
    );
    Widget switchRow(
      IconData icon,
      String title,
      bool value,
      ValueChanged<bool> onChanged,
    ) => SwitchListTile(
      secondary: Icon(icon, size: 20),
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );

    Widget section(String title, List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.primary,
              ),
            ),
          ),
        ),
        Material(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
    final content = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          section(t.settingsGeneral, [
            row(Icons.devices_outlined, t.deviceName, _rename, value: name),
            divider(),
            row(
              Icons.language_rounded,
              t.language,
              () => _choose('language', language, languages),
              value: languages[language] ?? t.systemDefault,
            ),
            divider(),
            row(
              Icons.palette_outlined,
              t.appearance,
              () => _choose('appearance', appearance, appearances),
              value: appearances[appearance] ?? t.systemDefault,
            ),
          ]),
          section(t.settingsReceiving, [
            if (background != null) ...[
              row(
                Icons.notifications_active_outlined,
                t.backgroundReceiving,
                _showBackgroundSettings,
                value: background.statusText(
                  t,
                  backgroundEnabled,
                  backgroundStatus,
                  autoAccept: autoAccept,
                ),
              ),
              divider(),
            ],
            if (Platform.isAndroid ||
                Platform.isMacOS ||
                DesktopPlatform.isWindowsOrLinux) ...[
              row(
                Icons.folder_outlined,
                t.saveLocation,
                () => _chooseSaveLocation(),
                value: !saveLocationAvailable
                    ? t.saveLocationUnavailable
                    : defaultSaveLocation
                    ? t.downloadsFolder
                    : (saveLocationLabel ?? t.chooseFolder),
                trailing: !defaultSaveLocation || !saveLocationAvailable
                    ? IconButton(
                        tooltip: t.useDownloads,
                        onPressed: () => _chooseSaveLocation(reset: true),
                        icon: const Icon(Icons.restart_alt_rounded),
                      )
                    : null,
              ),
              divider(),
            ],
            switchRow(Icons.move_to_inbox_outlined, t.autoAccept, autoAccept, (
              value,
            ) async {
              final prefs = await SharedPreferences.getInstance();
              if (await prefs.setBool('auto_accept_${widget.profile}', value) &&
                  mounted) {
                setState(() => autoAccept = value);
              }
            }),
            if (DesktopPlatform.isDesktop) ...[
              divider(),
              switchRow(
                Icons.open_in_new_rounded,
                t.openAfterReceive,
                openAfterReceive,
                (value) async {
                  final prefs = await SharedPreferences.getInstance();
                  if (await prefs.setBool(
                        DesktopPlatform.openAfterReceiveKey(widget.profile),
                        value,
                      ) &&
                      mounted) {
                    setState(() => openAfterReceive = value);
                  }
                },
              ),
            ],
            if (Platform.isAndroid) ...[
              divider(),
              row(
                Icons.notifications_outlined,
                t.notificationSettings,
                () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        NotificationSettingsPage(autoAccept: autoAccept),
                  ),
                ),
              ),
            ],
          ]),
          section(t.settingsTroubleshooting, [
            row(Icons.dns_outlined, t.relaySettings, widget.relaySettings),
            divider(),
            row(
              Icons.monitor_heart_outlined,
              t.diagnostics,
              widget.diagnostics,
            ),
            if (widget.openGuide != null) ...[
              divider(),
              row(
                Icons.help_outline_rounded,
                t.userGuide,
                widget.openGuide!,
                trailing: const Icon(Icons.open_in_new_rounded, size: 20),
              ),
            ],
          ]),
          if (widget.updates case final updates?)
            section(t.settingsAbout, [AppUpdateTile(controller: updates)]),
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    Platform.isMacOS ? 38 : 8,
                    20,
                    8,
                  ),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 48,
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            t.settings,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListTileTheme(
                    data: ListTileThemeData(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      minLeadingWidth: 24,
                      horizontalTitleGap: 12,
                      minVerticalPadding: 6,
                      minTileHeight: 52,
                      visualDensity: VisualDensity.standard,
                      iconColor: colors.onSurfaceVariant,
                      titleTextStyle: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: content,
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

String _cleanDeviceName(String value) => String.fromCharCodes(
  value.runes.where((c) => c >= 32 && !(c >= 127 && c <= 159)).take(60),
).trim();
