import 'dart:async';
import 'dart:typed_data';

import 'package:appflowy/core/notification/whiteboard_notification.dart';
import 'package:appflowy_backend/protobuf/flowy-whiteboard/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';

typedef OnWhiteboardUpdate = void Function(WhiteboardDataPB data);

class WhiteboardListener {
  WhiteboardListener({
    required this.id,
  });

  final String id;

  StreamSubscription<SubscribeObject>? _subscription;
  WhiteboardNotificationParser? _parser;

  OnWhiteboardUpdate? _onUpdate;

  void start({
    OnWhiteboardUpdate? onUpdate,
  }) {
    _onUpdate = onUpdate;

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
    switch (ty) {
      case WhiteboardNotification.DidReceiveUpdate:
        result.map(
          (s) => _onUpdate?.call(WhiteboardDataPB.fromBuffer(s)),
        );
        break;
      default:
        break;
    }
  }

  Future<void> stop() async {
    _onUpdate = null;
    await _subscription?.cancel();
    _subscription = null;
  }
}
