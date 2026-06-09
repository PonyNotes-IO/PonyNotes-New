import 'dart:async';
import 'dart:typed_data';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';

const int kWhiteboardNotificationTy = 41;

enum WhiteboardNotification {
  Unknown,
  DidReceiveUpdate,
}

class WhiteboardNotificationParser {
  final String id;
  final void Function(
    WhiteboardNotification ty,
    FlowyResult<Uint8List, FlowyError> result,
  ) callback;

  WhiteboardNotificationParser({
    required this.id,
    required this.callback,
  });

  void parse(SubscribeObject observable) {
    if (observable.id != id) {
      return;
    }

    final ty = observable.ty == kWhiteboardNotificationTy
        ? WhiteboardNotification.DidReceiveUpdate
        : WhiteboardNotification.Unknown;

    callback(ty, FlowyResult.success(Uint8List.fromList(observable.payload)));
  }
}
