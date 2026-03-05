import 'dart:typed_data';
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';

enum WhiteboardNotification {
  Unknown,
  DidReceiveUpdate,
}

class WhiteboardNotificationParser {
  WhiteboardNotificationParser({
    required this.id,
    required this.callback,
  });

  final String id;
  final void Function(
    WhiteboardNotification ty,
    FlowyResult<Uint8List, FlowyError> result,
  ) callback;

  void parse(SubscribeObject observable) {
    if (observable.id != id || observable.source != 'Whiteboard') {
      return;
    }

    final ty = WhiteboardNotification.values[observable.ty];
    callback(ty, FlowyResult.success(Uint8List.fromList(observable.payload)));
  }
}
