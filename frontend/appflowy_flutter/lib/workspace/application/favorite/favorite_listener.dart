import 'dart:async';

import 'package:appflowy/core/notification/folder_notification.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/notification.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/foundation.dart';

typedef FavoriteUpdated = void Function(
  FlowyResult<RepeatedViewPB, FlowyError> result,
  bool isFavorite,
);

class FavoriteListener {
  StreamSubscription<SubscribeObject>? _streamSubscription;
  StreamSubscription<SubscribeObject>? _viewStreamSubscription;
  FolderNotificationParser? _parser;
  FolderNotificationParser? _viewParser;

  FavoriteUpdated? _favoriteUpdated;

  void start({
    FavoriteUpdated? favoritesUpdated,
  }) {
    _favoriteUpdated = favoritesUpdated;
    _parser = FolderNotificationParser(
      id: 'favorite',
      callback: _observableCallback,
    );
    _streamSubscription = RustStreamReceiver.listen(
      (observable) => _parser?.parse(observable),
    );

    // Also listen for DidRestoreView on the "favorite" channel to refresh favorites
    // when a previously favorited view is restored from trash.
    _viewParser = FolderNotificationParser(
      id: 'favorite',
      callback: _viewObservableCallback,
    );
    _viewStreamSubscription = RustStreamReceiver.listen(
      (observable) => _viewParser?.parse(observable),
    );
  }

  void _observableCallback(
    FolderNotification ty,
    FlowyResult<Uint8List, FlowyError> result,
  ) {
    switch (ty) {
      case FolderNotification.DidFavoriteView:
        result.onSuccess(
          (success) => _favoriteUpdated?.call(
            FlowyResult.success(RepeatedViewPB.fromBuffer(success)),
            true,
          ),
        );
      case FolderNotification.DidUnfavoriteView:
        result.map(
          (success) => _favoriteUpdated?.call(
            FlowyResult.success(RepeatedViewPB.fromBuffer(success)),
            false,
          ),
        );
        break;
      default:
        break;
    }
  }

  void _viewObservableCallback(
    FolderNotification ty,
    FlowyResult<Uint8List, FlowyError> result,
  ) {
    switch (ty) {
      case FolderNotification.DidRestoreView:
        result.fold(
          (payload) {
            final restoredView = ViewPB.fromBuffer(payload);
            Log.info('[FavoriteListener] DidRestoreView: ${restoredView.name}, isFavorite=${restoredView.isFavorite}');
            if (restoredView.isFavorite) {
              // Trigger fetchFavorites to update the list
              _favoriteUpdated?.call(
                FlowyResult.success(RepeatedViewPB(items: [restoredView])),
                true,
              );
            }
          },
          (error) => Log.error('[FavoriteListener] DidRestoreView error: $error'),
        );
        break;
      default:
        break;
    }
  }

  Future<void> stop() async {
    _parser = null;
    _viewParser = null;
    await _streamSubscription?.cancel();
    await _viewStreamSubscription?.cancel();
    _streamSubscription = null;
    _viewStreamSubscription = null;
    _favoriteUpdated = null;
  }
}
