import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/core/notification/whiteboard_notification.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';

typedef OnWhiteboardRemoteUpdate = void Function(String key, dynamic value);

class WhiteboardListener {
  WhiteboardListener({
    required this.id,
  });

  final String id;

  StreamSubscription<SubscribeObject>? _subscription;
  WhiteboardNotificationParser? _parser;

  OnWhiteboardRemoteUpdate? _onRemoteUpdate;

  void start({
    OnWhiteboardRemoteUpdate? onRemoteUpdate,
  }) {
    _onRemoteUpdate = onRemoteUpdate;

    _parser = WhiteboardNotificationParser(
      id: id,
      callback: _callback,
    );
    _subscription = RustStreamReceiver.listen(
      (observable) => _parser?.parse(observable),
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
          // Rust 发送的是 JSON 字符串，不是 Protobuf 二进制。
          // 直接解析 JSON，提取 key/value 推送给适配器。
          final json = jsonDecode(String.fromCharCodes(payloadBytes));
          if (json is! Map) return;

          final key = json['key'] as String?;
          final value = json['value'];
          if (key == null || value == null) return;

          _onRemoteUpdate?.call(key, value);
        } catch (e) {
          // 解析失败时静默忽略，避免污染日志
        }
      },
      (_) {},
    );
  }

  Future<void> stop() async {
    _onRemoteUpdate = null;
    await _subscription?.cancel();
    _subscription = null;
  }
}
