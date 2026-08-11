import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:protobuf/protobuf.dart';

typedef ViewIconUpdater = Future<FlowyResult<void, FlowyError>> Function({
  required ViewPB view,
  required ViewIconPB viewIcon,
});

typedef ViewIconUpdateEmitter = void Function(
  ViewPB view,
  FlowyResult<void, FlowyError> result,
);

class ViewIconUpdateExecutor {
  ViewIconUpdateExecutor({required ViewIconUpdater updateViewIcon})
      : _updateViewIcon = updateViewIcon;

  final ViewIconUpdater _updateViewIcon;

  int _version = 0;

  Future<void> execute({
    required ViewPB currentView,
    required ViewIconPB icon,
    required ViewPB Function() readCurrentView,
    required ViewIconUpdateEmitter emit,
  }) async {
    final version = ++_version;
    final previousIcon = currentView.icon.deepCopy();
    final persistenceView = currentView.deepCopy();
    final optimisticView = currentView.deepCopy()..icon = icon;

    emit(optimisticView, FlowyResult.success(null));

    final result = await _updateViewIcon(
      view: persistenceView,
      viewIcon: icon,
    );
    if (version != _version || result.isSuccess) {
      return;
    }

    final rolledBackView = readCurrentView().deepCopy()..icon = previousIcon;
    emit(rolledBackView, FlowyResult.failure(result.getFailure()));
  }
}
