import 'dart:io';

import 'package:flutter/material.dart';

import 'l10n/generated/app_localizations.dart';
import 'notice.dart';
import 'page_layout.dart';

class RelayBusyException implements Exception {}

bool useCustomRelays(bool enabled, List<String> relays) =>
    enabled && relays.isNotEmpty;

class RelaySettingsPage extends StatefulWidget {
  const RelaySettingsPage({
    super.key,
    required this.relays,
    required this.enabled,
    required this.setEnabled,
    required this.add,
    required this.readToken,
    required this.update,
    required this.remove,
    required this.test,
  });
  final List<String> relays;
  final bool enabled;
  final Future<void> Function(bool enabled) setEnabled;
  final Future<String> Function(String url, String? token) add;
  final Future<String?> Function(String url) readToken;
  final Future<String> Function(String oldUrl, String url, String? token)
  update;
  final Future<void> Function(String url) remove;
  final Future<String> Function(String url, String? token) test;

  @override
  State<RelaySettingsPage> createState() => _RelaySettingsPageState();
}

class _RelaySettingsPageState extends State<RelaySettingsPage> {
  late final relays = List<String>.of(widget.relays);
  late bool enabled = widget.enabled;
  bool changingEnabled = false;
  String? testingRelay;
  final testResults = <String, String>{};

  Future<void> _setEnabled(bool value) async {
    if (changingEnabled) return;
    setState(() => changingEnabled = true);
    try {
      await widget.setEnabled(value);
      if (mounted) setState(() => enabled = value);
    } on RelayBusyException {
      if (mounted) {
        showNotice(
          context,
          AppLocalizations.of(context)!.relayBusy,
          kind: NoticeKind.info,
        );
      }
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          AppLocalizations.of(context)!.relayToggleFailed,
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => changingEnabled = false);
    }
  }

  Future<void> _testRelay(String url) async {
    if (testingRelay != null || changingEnabled) return;
    setState(() {
      testingRelay = url;
      testResults.remove(url);
    });
    var result = 'failed';
    try {
      result = await widget.test(url, await widget.readToken(url));
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      testingRelay = null;
      testResults[url] = result;
    });
  }

  Future<void> _add() async {
    final added = await showDialog<String>(
      context: context,
      builder: (_) =>
          _AddRelayDialog(relays: relays, add: widget.add, test: widget.test),
    );
    if (added != null && mounted) setState(() => relays.add(added));
  }

  Future<void> _edit(String oldUrl) async {
    try {
      final token = await widget.readToken(oldUrl);
      if (!mounted || testingRelay == oldUrl) return;
      final result = await showDialog<String>(
        context: context,
        builder: (_) => _AddRelayDialog(
          relays: relays.where((url) => url != oldUrl).toList(),
          initialUrl: oldUrl,
          initialToken: token,
          test: widget.test,
          add: (url, token) => widget.update(oldUrl, url, token),
          remove: () => widget.remove(oldUrl),
        ),
      );
      if (result != null && mounted) {
        setState(() {
          testResults.remove(oldUrl);
          final index = relays.indexOf(oldUrl);
          if (result.isEmpty) {
            relays.removeAt(index);
          } else {
            relays[index] = result;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          AppLocalizations.of(context)!.relayFailed,
          kind: NoticeKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final customActive = useCustomRelays(enabled, relays);
    Widget divider() => Divider(
      height: 1,
      indent: 60,
      endIndent: 20,
      color: colors.outlineVariant.withValues(alpha: .45),
    );
    return Scaffold(
      body: PageLayout(
        header: Padding(
          padding: EdgeInsets.fromLTRB(20, Platform.isMacOS ? 38 : 8, 20, 16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.relaySettings,
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
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                key: const ValueKey('relay-enabled'),
                value: enabled,
                onChanged: changingEnabled ? null : _setEnabled,
                title: Text(
                  t.relayEnabled,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: customActive
                    ? Text(t.relayCustomOnly)
                    : enabled
                    ? Text(t.relayEnabledDetail)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final url in relays) ...[
                    if (url != relays.first) divider(),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      leading: Icon(
                        Icons.dns_outlined,
                        size: 22,
                        color: colors.primary,
                      ),
                      title: Text(
                        Uri.tryParse(url)?.authority ?? url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: switch (testResults[url]) {
                        final result? => Semantics(
                          liveRegion: true,
                          child: Text(_relayTestMessage(t, result)),
                        ),
                        null => null,
                      },
                      trailing: TextButton(
                        key: ValueKey('test-relay-$url'),
                        onPressed: testingRelay == null && !changingEnabled
                            ? () => _testRelay(url)
                            : null,
                        child: testingRelay == url
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(t.relayTestShort),
                      ),
                      onTap: changingEnabled || testingRelay == url
                          ? null
                          : () => _edit(url),
                    ),
                  ],
                  if (relays.isNotEmpty) divider(),
                  ListTile(
                    key: const ValueKey('add-relay'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    leading: Icon(
                      Icons.add_rounded,
                      size: 22,
                      color: colors.primary,
                    ),
                    title: Text(
                      t.addRelay,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                    onTap: changingEnabled ? null : _add,
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

String _relayTestMessage(AppLocalizations t, String result) => switch (result) {
  'connected' => t.relayTestSuccess,
  'auth' => t.relayTestAuth,
  'timeout' => t.relayTestTimeout,
  _ => t.relayTestFailed,
};

class _AddRelayDialog extends StatefulWidget {
  const _AddRelayDialog({
    required this.relays,
    required this.add,
    required this.test,
    this.initialUrl,
    this.initialToken,
    this.remove,
  });
  final List<String> relays;
  final Future<String> Function(String url, String? token) add;
  final Future<String> Function(String url, String? token) test;
  final String? initialUrl;
  final String? initialToken;
  final Future<void> Function()? remove;
  @override
  State<_AddRelayDialog> createState() => _AddRelayDialogState();
}

class _AddRelayDialogState extends State<_AddRelayDialog> {
  late final url = TextEditingController(text: widget.initialUrl);
  late final token = TextEditingController(text: widget.initialToken);
  final form = GlobalKey<FormState>();
  bool saving = false;
  bool showToken = false;
  bool failed = false;
  bool busyFailure = false;
  bool testing = false;
  String? testResult;

  Future<void> _test() async {
    if (saving || testing || !form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      testing = true;
      testResult = null;
    });
    var result = 'failed';
    try {
      final value = token.text.trim();
      result = await widget.test(url.text.trim(), value.isEmpty ? null : value);
    } catch (_) {}
    if (mounted) {
      setState(() {
        testing = false;
        testResult = result;
      });
    }
  }

  @override
  void dispose() {
    url.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving || testing || !form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      saving = true;
      failed = false;
      busyFailure = false;
    });
    try {
      final value = token.text.trim();
      final result = await widget.add(
        url.text.trim(),
        value.isEmpty ? null : value,
      );
      if (mounted) Navigator.pop(context, result);
    } on RelayBusyException {
      if (mounted) {
        setState(() {
          saving = false;
          failed = true;
          busyFailure = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          failed = true;
        });
      }
    }
  }

  Future<void> _remove() async {
    final t = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.relayRemove),
        content: Text(
          widget.initialUrl!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      saving = true;
      failed = false;
      busyFailure = false;
    });
    try {
      await widget.remove!();
      if (mounted) Navigator.pop(context, '');
    } on RelayBusyException {
      if (mounted) {
        setState(() {
          saving = false;
          failed = true;
          busyFailure = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !saving && !testing,
      child: AlertDialog(
        title: Text(widget.initialUrl == null ? t.addRelay : t.editRelay),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: url,
                    autofocus: widget.initialUrl == null,
                    enabled: !saving && !testing,
                    onChanged: (_) => setState(() => testResult = null),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: t.relayUrl,
                      hintText: 'https://example.com',
                    ),
                    validator: (value) {
                      final uri = Uri.tryParse((value ?? '').trim());
                      if (uri == null ||
                          uri.scheme != 'https' ||
                          uri.host.isEmpty ||
                          uri.userInfo.isNotEmpty ||
                          uri.hasQuery ||
                          uri.hasFragment ||
                          (uri.path.isNotEmpty && uri.path != '/')) {
                        return t.relayInvalid;
                      }
                      if (widget.relays.contains(
                        uri.replace(path: '/').toString(),
                      )) {
                        return t.relayDuplicate;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: token,
                    enabled: !saving && !testing,
                    onChanged: (_) => setState(() => testResult = null),
                    obscureText: !showToken,
                    enableSuggestions: false,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      labelText: t.relayToken,
                      suffixIcon: IconButton(
                        tooltip: showToken
                            ? t.relayHideToken
                            : t.relayShowToken,
                        onPressed: saving || testing
                            ? null
                            : () => setState(() => showToken = !showToken),
                        icon: Icon(
                          showToken
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('test-relay-form'),
                      onPressed: saving || testing ? null : _test,
                      icon: testing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check_rounded),
                      label: Text(t.relayTest),
                    ),
                  ),
                  if (testResult != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _relayTestMessage(t, testResult!),
                        style: TextStyle(
                          color: testResult == 'connected'
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (widget.remove != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: saving || testing ? null : _remove,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(t.relayRemove),
                      ),
                    ),
                  ],
                  if (failed) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        busyFailure ? t.relayBusy : t.relayFailed,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving || testing ? null : () => Navigator.pop(context),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: saving || testing ? null : _save,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(t.save),
          ),
        ],
      ),
    );
  }
}
