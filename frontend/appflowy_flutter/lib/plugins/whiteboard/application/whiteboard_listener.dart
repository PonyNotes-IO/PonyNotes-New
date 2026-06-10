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
          // 尝试解析为 UTF-8 编码的 JSON
          String jsonString;
          try {
            jsonString = utf8.decode(payloadBytes);
          } catch (e) {
            // 如果 UTF-8 解码失败，可能是二进制数据（如图片等），直接忽略
            Log.debug('[WhiteboardListener] Payload is not UTF-8 encoded, skipping');
            return;
          }

          final json = jsonDecode(jsonString);
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
          Log.error('[WBCollab][WhiteboardListener] Failed to parse notification: $e');
        }
      },
      (error) {
        Log.error('[WBCollab][WhiteboardListener] Notification error: ${error.msg}');
      },
    );
  }

  Future<void> stop() async {
    _onRemoteUpdate = null;
    await _subscription?.cancel();
    _subscription = null;
  }
}
