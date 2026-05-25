import 'dart:async';
import 'dart:typed_data';

import 'package:appflowy/core/notification/folder_notification.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';

typedef FolderSyncStateCallback = void Function(
  FolderSyncStatePB syncState,
);

class FolderSyncStateListener {
  FolderSyncStateListener({
    required this.workspaceId,
  });

  final String workspaceId;
  StreamSubscription<SubscribeObject>? _subscription;
  FolderNotificationParser? _parser;
  FolderSyncStateCallback? didReceiveSyncState;

  void start({
    FolderSyncStateCallback? didReceiveSyncState,
  }) {
    this.didReceiveSyncState = didReceiveSyncState;

    _parser = FolderNotificationParser(
      id: workspaceId,
      callback: _callback,
    );
    _subscription = RustStreamReceiver.listen(
      (observable) => _parser?.parse(observable),
    );
  }

  void _callback(
    FolderNotification ty,
    FlowyResult<Uint8List, FlowyError> result,
  ) {
    switch (ty) {
      case FolderNotification.DidUpdateFolderSyncUpdate:
        result.map(
          (r) {
            final value = FolderSyncStatePB.fromBuffer(r);
            Log.info('[FolderSyncStateListener] 收到同步状态更新: isSyncing=${value.isSyncing}, isFinish=${value.isFinish}');
            didReceiveSyncState?.call(value);
          },
        );
        break;
      default:
        break;
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
