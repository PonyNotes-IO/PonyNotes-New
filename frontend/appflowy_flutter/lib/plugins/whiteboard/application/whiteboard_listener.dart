import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';
import '../../../core/notification/whiteboard_notification.dart';

typedef OnWhiteboardRemoteUpdate = void Function(String key, dynamic value, bool isRemote);

class WhiteboardListener {
  final String id;
  OnWhiteboardRemoteUpdate? _onRemoteUpdate;
  StreamSubscription<SubscribeObject>? _subscription;
  WhiteboardNotificationParser? _parser;

  WhiteboardListener({required this.id});

  void start({
    OnWhiteboardRemoteUpdate? onRemoteUpdate,
  }) {
    _onRemoteUpdate = onRemoteUpdate;

    _parser = WhiteboardNotificationParser(
      id: id,
      callback: _callback,
    );
    _subscription = RustStreamReceiver.listen(
      (observable) {
        _parser?.parse(observable);
      },
    );
  }

  void _callback(
    WhiteboardNotification ty,
    FlowyResult<Uint8List, FlowyError> result,
  ) {
    if (ty != WhiteboardNotification.DidReceiveUpdate) return;

    result.fold(
      (payloadBytes) {
        try {
          final json = jsonDecode(utf8.decode(payloadBytes));
          if (json is! Map) {
            return;
          }

          final key = json['key'] as String?;
          final value = json['value'];
          final isRemote = json['is_remote'] == true;

          if (key == null || value == null) {
            return;
          }

          _onRemoteUpdate?.call(key, value, isRemote);
        } catch (e) {
          Log.error('[WhiteboardListener] Failed to parse notification: $e');
        }
      },
      (error) {
        Log.error('[WhiteboardListener] Notification error: ${error.msg}');
      },
    );
  }

  Future<void> stop() async {
    _onRemoteUpdate = null;
    await _subscription?.cancel();
    _subscription = null;
  }
}
