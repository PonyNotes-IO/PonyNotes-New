import 'dart:async';
import 'dart:typed_data';

import 'package:appflowy/core/notification/handwriting_saber_notification.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-handwriting-saber/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-handwriting-saber/notification.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';

typedef OnHandwritingSaberRemoteUpdate = void Function(
  HandwritingSaberUpdatePB update,
);

/// 监听手写笔记的远端更新。
///
/// Rust 侧在 Collab 收到其他设备/服务端的更新后会发通知。画布必须据此重新
/// 读取数据，否则会停留在旧内容上，并在下一次保存时把远端内容整篇覆盖。
class HandwritingSaberListener {
  HandwritingSaberListener({required this.id});

  final String id;

  StreamSubscription<SubscribeObject>? _subscription;
  HandwritingSaberNotificationParser? _parser;
  OnHandwritingSaberRemoteUpdate? _onRemoteUpdate;

  void start({required OnHandwritingSaberRemoteUpdate onRemoteUpdate}) {
    _onRemoteUpdate = onRemoteUpdate;
    _parser = HandwritingSaberNotificationParser(id: id, callback: _callback);
    _subscription = RustStreamReceiver.listen(
      (observable) => _parser?.parse(observable),
    );
  }

  void _callback(
    HandwritingSaberNotification ty,
    FlowyResult<Uint8List, FlowyError> result,
  ) {
    switch (ty) {
      case HandwritingSaberNotification.DidReceiveUpdate:
        result.map(
          (bytes) => _onRemoteUpdate?.call(
            HandwritingSaberUpdatePB.fromBuffer(bytes),
          ),
        );
        break;
      default:
        break;
    }
  }

  Future<void> stop() async {
    _onRemoteUpdate = null;
    await _subscription?.cancel();
    _subscription = null;
    _parser = null;
  }
}
