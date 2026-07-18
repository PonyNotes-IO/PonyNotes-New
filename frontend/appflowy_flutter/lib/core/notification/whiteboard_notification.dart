import 'dart:async';
import 'dart:typed_data';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';

const int kWhiteboardNotificationTy = 41;

/// 白板通知的来源标识，必须与 Rust 侧 `WHITEBOARD_OBSERVABLE_SOURCE` 保持一致
/// （flowy-whiteboard/src/notification.rs）。
///
/// 【必须按 source 过滤】通知的 `ty` 是**按子系统各自编号**的，不同子系统的相同
/// 数值代表完全不同的通知：白板的 41 是 `DidReceiveUpdate`（负载为 JSON 字节），
/// 而 Folder 的 41 是 `DidUpdateSharedUsers`（source="Workspace"，负载为 protobuf）。
/// 二者的通知 id 都可能是同一个 viewId，若只比对 id 与 ty 就会把 Folder 的 protobuf
/// 负载误当成白板 JSON 去解析，产生大量 FormatException（日志实测 192 次）。
const String kWhiteboardObservableSource = 'Whiteboard';

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
    // 先按来源过滤：只处理白板子系统发出的通知，避免与其它子系统的同号通知串台。
    if (observable.source != kWhiteboardObservableSource) {
      return;
    }

    if (observable.id != id) {
      return;
    }

    final ty = observable.ty == kWhiteboardNotificationTy
        ? WhiteboardNotification.DidReceiveUpdate
        : WhiteboardNotification.Unknown;

    callback(ty, FlowyResult.success(Uint8List.fromList(observable.payload)));
  }
}
