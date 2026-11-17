part of 'main.dart';

void _registerDebugDriver() {
  _driverMode = true;
  enableFlutterDriverExtension(
    handler: (message) async {
      final state = _testHome.currentState;
      if (state == null || message == null) return 'not ready';
      final data = jsonDecode(message) as Map<String, dynamic>;
      if (data['action'] == 'state') {
        return jsonEncode({
          'busy': state.contentOperationActive,
          'pairing': state.outgoingPairingUiActive,
          'activity': state.activity,
          'message': state.lastMessage,
          'receivedPath': state.receivedPath,
          'peers': state.peers,
          'presence': state.presence.map(
            (id, value) => MapEntry(id, value.name),
          ),
          'refreshingPresence': state.refreshingPresence,
          'manualRefreshing': state.checkingPeers,
          'visiblePresenceChecks': state.visiblePresenceChecks.toList(),
        });
      }
      if (data['action'] == 'refresh-auto-test') {
        unawaited(state.presenceController.readSnapshot());
        return 'started';
      }
      if (data['action'] == 'notification-preview-test' && Platform.isAndroid) {
        await _HomePageState.backgroundChannel.invokeMethod<void>('transfer', {
          'title': notificationTitle(data['title'] as String),
          'text': data['text'],
          'channel': 'Transfers',
          'progress': data['progress'],
          'shortText': data['shortText'],
          'id': 'preview',
          'cancel': '取消',
          'sourceType': 'desktop',
          'destinationType': 'mobile',
        });
        return 'shown';
      }
      if (data['action'] == 'notification-offer-test' && Platform.isAndroid) {
        state.notificationOfferId = 'preview-offer';
        state.notificationDecision = Completer<bool>();
        await _HomePageState.backgroundChannel.invokeMethod<void>('offer', {
          'id': state.notificationOfferId,
          'title': 'MacBook 发来内容',
          'message': 'photo.jpg · 4 MB',
          'shortText': '待接收',
          'accept': '接收',
          'reject': '拒绝',
        });
        return 'shown';
      }
      if (data['action'] == 'notification-offer-result' && Platform.isAndroid) {
        final decision = state.notificationDecision;
        return decision?.isCompleted == true
            ? (await decision!.future ? 'accepted' : 'declined')
            : 'pending';
      }
      if (data['action'] == 'notification-clear-test' && Platform.isAndroid) {
        await _HomePageState.backgroundChannel.invokeMethod<void>(
          'clearTransfer',
        );
        return 'cleared';
      }
      if (data['action'] == 'notification-finish-test' && Platform.isAndroid) {
        final base = await getApplicationSupportDirectory();
        final file = File('${base.path}/vela-notification-test.txt');
        await file.writeAsString('Vela notification test');
        await _HomePageState.backgroundChannel.invokeMethod<void>(
          'finishTransfer',
          {
            'text': '已接收 vela-notification-test.txt',
            'channel': 'Transfers',
            'path': file.path,
            'name': 'vela-notification-test.txt',
            'open': '打开',
            'received': true,
            'title': '接收完成',
            'shortText': '已接收',
            'test': true,
          },
        );
        return 'shown';
      }
      if (data['action'] == 'mac-focus-test' && Platform.isMacOS) {
        await state.prefs!.setBool(
          'mac_focus_on_offer_${state.widget.profile}',
          data['value'] as bool,
        );
        return 'set';
      }
      if (data['action'] == 'mac-close-test' && Platform.isMacOS) {
        await _HomePageState.backgroundChannel.invokeMethod<void>('testClose');
        return 'closed';
      }
      if (data['action'] == 'mac-show-test' && Platform.isMacOS) {
        await _HomePageState.backgroundChannel.invokeMethod<void>('testShow');
        return 'shown';
      }
      if (data['action'] == 'mac-status-test' && Platform.isMacOS) {
        return jsonEncode(
          await _HomePageState.backgroundChannel.invokeMapMethod<String, bool>(
            'testStatus',
          ),
        );
      }
      if (data['action'] == 'mac-menu-test' && Platform.isMacOS) {
        return jsonEncode(
          await _HomePageState.backgroundChannel
              .invokeMapMethod<String, dynamic>('testMenu'),
        );
      }
      if (data['action'] == 'mac-menu-incoming-test' && Platform.isMacOS) {
        await _HomePageState.backgroundChannel.invokeMethod<void>(
          'testMenuIncoming',
          data['value'] as bool,
        );
        return 'set';
      }
      if (data['action'] == 'device') {
        return jsonEncode({'name': state.deviceName, 'type': state.deviceType});
      }
      if (data['action'] == 'set-clipboard') {
        final kind = data['kind'] as String;
        if (kind == 'text') {
          await Clipboard.setData(
            ClipboardData(text: data['content'] as String),
          );
        } else if (kind == 'image') {
          await Pasteboard.writeImage(base64Decode(data['content'] as String));
        } else if (kind == 'file') {
          final base = await getApplicationSupportDirectory();
          final file = File(
            '${base.path}/clip-test-${DateTime.now().microsecondsSinceEpoch}.txt',
          );
          await file.writeAsString(data['content'] as String, flush: true);
          if (Platform.isAndroid) {
            await _HomePageState.clipboardChannel.invokeMethod<void>(
              'writeFile',
              {'path': file.path},
            );
          } else if (!await Pasteboard.writeFiles([file.path])) {
            throw StateError('clipboard write failed');
          }
        }
        return 'set';
      }
      if (data['action'] == 'get-clipboard') {
        final kind = data['kind'] as String;
        if (kind == 'text') {
          return (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
        }
        if (kind == 'image') {
          return (await Pasteboard.image)?.isNotEmpty == true ? 'image' : '';
        }
        final files = Platform.isAndroid
            ? await _HomePageState.clipboardChannel.invokeListMethod<String>(
                    'files',
                  ) ??
                  <String>[]
            : await Pasteboard.files();
        if (files.isEmpty) return '';
        final path = Platform.isAndroid
            ? await _HomePageState.clipboardChannel.invokeMethod<String>(
                'materialize',
                {'uri': files.single},
              )
            : files.single;
        return path == null ? '' : await File(path).readAsString();
      }
      if (data['action'] == 'clean-speed-test') {
        final path = state.receivedPath;
        if (path == null ||
            !File(path).uri.pathSegments.last.startsWith('vela-speed-test-')) {
          return 'not a speed test file';
        }
        await File(path).delete();
        return 'deleted';
      }
      if (data['action'] != 'send' && data['action'] != 'send-speed-test') {
        return 'unknown action';
      }
      final peerId = data['peer'] as String;
      final base = await getApplicationSupportDirectory();
      final speedTest = data['action'] == 'send-speed-test';
      final name = data['filename'] as String?;
      if (name != null &&
          (name.isEmpty ||
              name.contains('/') ||
              name.contains('\\') ||
              name == '.' ||
              name == '..')) {
        return 'invalid filename';
      }
      final testDirectory = name == null
          ? null
          : await Directory.systemTemp.createTemp('vela-dialog-test-');
      final file = File(
        name == null
            ? '${base.path}/${speedTest ? 'vela-speed-test' : 'test'}-${DateTime.now().microsecondsSinceEpoch}.${speedTest ? 'bin' : 'txt'}'
            : '${testDirectory!.path}/$name',
      );
      if (speedTest) {
        final bytes = data['bytes'] as int? ?? 512 * 1024 * 1024;
        if (bytes <= 0 || bytes > 512 * 1024 * 1024) return 'invalid size';
        final handle = await file.open(mode: FileMode.write);
        await handle.truncate(bytes);
        await handle.close();
      } else {
        await file.writeAsString(data['content'] as String, flush: true);
      }
      final textTest = data['kind'] == 'text';
      unawaited(() async {
        try {
          await state._send(
            peerId,
            state.peers[peerId]!,
            state._createSendSession(
              PreparedTransfer(
                paths: [file.path],
                kind: textTest ? TransferKind.text : TransferKind.file,
              ),
            ),
          );
        } finally {
          if ((textTest || speedTest || testDirectory != null) &&
              await file.exists()) {
            await file.delete();
          }
          if (testDirectory != null && await testDirectory.exists()) {
            await testDirectory.delete();
          }
        }
      }());
      return 'started';
    },
  );
}
