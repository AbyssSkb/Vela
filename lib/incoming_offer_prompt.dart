import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/generated/app_localizations.dart';
import 'notice.dart';
import 'peer_confirmation.dart';
import 'src/rust/api/node.dart';

enum BackgroundOfferAction { accept, decline, showDialog, connectionClosed }

/// Owns the notification, button ID and foreground dialog for one offer.
class IncomingOfferPrompt {
  IncomingOfferPrompt(this._channel, {this.notificationId});

  final MethodChannel _channel;
  final String? notificationId;
  final _backgroundAction = Completer<BackgroundOfferAction>();
  Future<BackgroundOfferAction>? get decidedAction =>
      _backgroundAction.isCompleted ? _backgroundAction.future : null;
  bool openedDialog = false;
  bool _notificationShown = false;

  void becameVisible() {
    if (!_backgroundAction.isCompleted) {
      _backgroundAction.complete(BackgroundOfferAction.showDialog);
    }
  }

  void notificationDecision(Object? id, Object? accepted) {
    if (notificationId == null ||
        id != notificationId ||
        accepted is! bool ||
        _backgroundAction.isCompleted)
      return;
    _backgroundAction.complete(
      accepted ? BackgroundOfferAction.accept : BackgroundOfferAction.decline,
    );
  }

  Future<PeerDecision> confirm(
    BuildContext context, {
    required IncomingRequest offer,
    required String Function() senderName,
    required String contentName,
    required List<String> batchFiles,
    required String size,
    required bool inBackground,
    required bool autoAccept,
    bool updatesClipboard = false,
  }) async {
    final t = AppLocalizations.of(context)!;
    if (inBackground && (!autoAccept || Platform.isAndroid)) {
      _notificationShown = true;
      try {
        await _channel.invokeMethod<void>('offer', {
          'title': Platform.isAndroid
              ? t.shareFrom(senderName())
              : senderName(),
          'message': Platform.isAndroid
              ? [
                  '$contentName · $size',
                  if (updatesClipboard) t.incomingClipboardHint,
                ].join('\n')
              : t.backgroundOffer,
          'shortText': t.incomingShort,
          'id': notificationId,
          'accept': t.receive,
          'reject': t.reject,
        });
      } catch (e) {
        debugPrint('Could not show incoming notification: $e');
      }
      if (!autoAccept) {
        final action = await Future.any([
          _backgroundAction.future,
          offer.waitForConnectionClose().then(
            (_) => BackgroundOfferAction.connectionClosed,
          ),
        ]);
        await clearNotification();
        switch (action) {
          case BackgroundOfferAction.accept:
            return PeerDecision.accepted;
          case BackgroundOfferAction.decline:
            return PeerDecision.declined;
          case BackgroundOfferAction.connectionClosed:
            return PeerDecision.connectionClosed;
          case BackgroundOfferAction.showDialog:
            break;
        }
      }
    }
    if (autoAccept) return PeerDecision.accepted;
    if (!context.mounted) return PeerDecision.connectionClosed;
    openedDialog = true;
    var showingAllFiles = false;
    return showPeerConfirmation(
      context,
      peerClosed: offer.waitForConnectionClose(),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => NoticePrompt(
          title: t.shareFrom(senderName()),
          inlineActions: batchFiles.isEmpty && !updatesClipboard,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$contentName · $size',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (updatesClipboard) ...[
                const SizedBox(height: 8),
                Text(t.incomingClipboardHint),
              ],
              if (batchFiles.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(batchFiles.take(3).join('\n')),
                if (batchFiles.length > 3)
                  TextButton(
                    onPressed: () => setDialogState(
                      () => showingAllFiles = !showingAllFiles,
                    ),
                    child: Text(
                      showingAllFiles
                          ? t.showFewerOfferedFiles
                          : t.showMoreOfferedFiles(batchFiles.length - 3),
                    ),
                  ),
                if (showingAllFiles) Text(batchFiles.skip(3).join('\n')),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.reject),
            ),
            FilledButton(
              key: const ValueKey('accept-offer'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.receive),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> clearNotification() async {
    if (!_notificationShown) return;
    try {
      await _channel.invokeMethod<void>('clearOffer');
      _notificationShown = false;
    } catch (_) {}
  }
}
