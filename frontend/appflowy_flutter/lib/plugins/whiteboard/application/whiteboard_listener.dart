import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';
import '../../../core/notification/whiteboard_notification.dart';

/// Callback signature: receives the full parsed JSON payload from Rust notifications.
/// The payload contains: {key, value, is_remote, and optionally large_data}.
typedef OnWhiteboardRemoteUpdate = void Function(Map<String, dynamic> payload);

class WhiteboardListener {
  final String id;
  OnWhiteboardRemoteUpdate? _onRemoteUpdate;
  StreamSubscription<SubscribeObject>? _subscription;
  WhiteboardNotificationParser? _parser;
  bool _stopped = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _initialReconnectDelay = Duration(milliseconds: 500);

  WhiteboardListener({required this.id});

  void start({
    OnWhiteboardRemoteUpdate? onRemoteUpdate,
  }) {
    _onRemoteUpdate = onRemoteUpdate;
    _stopped = false;
    _reconnectAttempts = 0;
    _subscribe();
  }

  void _subscribe() {
    if (_stopped) return;

    _parser = WhiteboardNotificationParser(
      id: id,
      callback: _callback,
    );
    _subscription = RustStreamReceiver.shared.observable.stream.listen(
      (observable) {
        _parser?.parse(observable);
      },
      onError: (Object error) {
        Log.error('[WBCollab][WhiteboardListener] Stream error: $error, will reconnect');
        _scheduleReconnect();
      },
      onDone: () {
        if (!_stopped) {
          Log.warn('[WBCollab][WhiteboardListener] Stream closed unexpectedly, will reconnect');
          _scheduleReconnect();
        }
      },
    );
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    _subscription?.cancel();
    _subscription = null;

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      Log.error(
        '[WBCollab][WhiteboardListener] Max reconnect attempts ($_maxReconnectAttempts) reached, giving up',
      );
      return;
    }

    final delay = _initialReconnectDelay * (1 << _reconnectAttempts);
    _reconnectAttempts++;
    Log.info(
      '[WBCollab][WhiteboardListener] Scheduling reconnect attempt $_reconnectAttempts in ${delay.inMilliseconds}ms',
    );

    Timer(delay, () {
      if (!_stopped) {
        _subscribe();
      }
    });
  }

  void _callback(
    WhiteboardNotification ty,
    FlowyResult<Uint8List, FlowyError> result,
  ) {
    if (ty != WhiteboardNotification.DidReceiveUpdate) return;

    // Reset reconnect counter on successful message delivery
    _reconnectAttempts = 0;

    result.fold(
      (payloadBytes) {
        try {
          String jsonString;
          try {
            jsonString = utf8.decode(payloadBytes);
          } catch (e) {
            Log.debug('[WhiteboardListener] Payload is not UTF-8 encoded, skipping');
            return;
          }

          final json = jsonDecode(jsonString);
          if (json is! Map) {
            return;
          }

          final key = json['key'] as String?;
          if (key == null) return;

          // Note: value may be null for large_data notifications — that is valid.
          // Pass the full payload so the adapter can access all fields.
          _onRemoteUpdate?.call(Map<String, dynamic>.from(json as Map));
        } catch (e) {
          Log.error('[WBCollab][WhiteboardListener] Failed to parse notification: $e');
        }
      },
      (error) {
        Log.error('[WBCollab][WhiteboardListener] Notification error: ${error.msg}');
      },
    );
  }

  Future<void> stop() async {
    _stopped = true;
    _onRemoteUpdate = null;
    await _subscription?.cancel();
    _subscription = null;
  }
}
