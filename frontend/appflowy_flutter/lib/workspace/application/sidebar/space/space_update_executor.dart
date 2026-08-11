import 'dart:convert';

import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';

typedef SpaceViewUpdater = Future<FlowyResult<ViewPB, FlowyError>> Function({
  required String viewId,
  String? name,
  String? extra,
});

typedef SpaceVisibilityUpdater = Future<FlowyResult<void, FlowyError>> Function(
  List<ViewPB> views,
  bool isPublic,
);

class SpaceUpdateExecutor {
  SpaceUpdateExecutor({
    required SpaceViewUpdater updateView,
    required SpaceVisibilityUpdater updateVisibility,
  })  : _updateView = updateView,
        _updateVisibility = updateVisibility;

  static const _spaceIconKey = 'space_icon';
  static const _spaceIconColorKey = 'space_icon_color';
  static const _spacePermissionKey = 'space_permission';

  final SpaceViewUpdater _updateView;
  final SpaceVisibilityUpdater _updateVisibility;

  Future<FlowyResult<void, FlowyError>> execute({
    required ViewPB space,
    String? name,
    String? icon,
    String? iconColor,
    int? permissionIndex,
    bool? isPublic,
  }) async {
    String? extra;
    if (icon != null || iconColor != null || permissionIndex != null) {
      try {
        final decoded = space.extra.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(space.extra) as Map<String, dynamic>;
        if (icon != null) {
          decoded[_spaceIconKey] = icon;
        }
        if (iconColor != null) {
          decoded[_spaceIconColorKey] = iconColor;
        }
        if (permissionIndex != null) {
          decoded[_spacePermissionKey] = permissionIndex;
        }
        extra = jsonEncode(decoded);
      } catch (error) {
        return FlowyResult.failure(
          FlowyError()..msg = 'Failed to update space metadata: $error',
        );
      }
    }

    final viewResult = await _updateView(
      viewId: space.id,
      name: name,
      extra: extra,
    );
    if (viewResult.isFailure) {
      return FlowyResult.failure(viewResult.getFailure());
    }

    if (isPublic != null) {
      final visibilityResult = await _updateVisibility([space], isPublic);
      if (visibilityResult.isFailure) {
        return FlowyResult.failure(visibilityResult.getFailure());
      }
    }

    return FlowyResult.success(null);
  }
}
