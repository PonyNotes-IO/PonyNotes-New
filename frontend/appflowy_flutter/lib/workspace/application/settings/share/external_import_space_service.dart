import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/home/space/space_change_notifier.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';

/// 统一定位电脑端和移动端外部文件导入使用的私有空间。
class ExternalImportSpaceService {
  ExternalImportSpaceService._();

  static const _legacySpaceNames = {'外部导入', 'External Import'};
  static const _spaceIcon = '📥';
  static const _spaceIconColor = '#FF6B6B';

  static final Map<String, Future<ViewPB>> _pendingRequests = {};

  /// 返回当前工作区已有的外部导入空间；不存在时只创建一个。
  ///
  /// 同一工作区内的并发请求会复用同一个 Future，避免用户连续点击时创建
  /// 多个同名空间。
  static Future<ViewPB> getOrCreate(String workspaceId) {
    final existingRequest = _pendingRequests[workspaceId];
    if (existingRequest != null) {
      return existingRequest;
    }

    final request = _getOrCreate(workspaceId);
    _pendingRequests[workspaceId] = request;
    return request.whenComplete(() {
      if (identical(_pendingRequests[workspaceId], request)) {
        _pendingRequests.remove(workspaceId);
      }
    });
  }

  static Future<ViewPB> _getOrCreate(String workspaceId) async {
    final userResult = await UserBackendService.getCurrentUserProfile();
    final user = userResult.fold(
      (user) => user,
      (error) => throw Exception('获取当前用户失败: $error'),
    );
    final workspaceService = WorkspaceService(
      workspaceId: workspaceId,
      userId: user.id,
    );

    final privateViewsResult = await workspaceService.getPrivateViews();
    final privateViews = privateViewsResult.fold(
      (views) => views,
      (error) => throw Exception('获取私有空间失败: $error'),
    );
    final localizedName = LocaleKeys.importPanel_externalImport.tr();
    final acceptedNames = {..._legacySpaceNames, localizedName};

    for (final view in privateViews) {
      if (view.isSpace && acceptedNames.contains(view.name)) {
        Log.info('复用已有外部导入空间: ${view.id}');
        return view;
      }
    }

    final spaceExtra = {
      ViewExtKeys.isSpaceKey: true,
      ViewExtKeys.spaceIconKey: _spaceIcon,
      ViewExtKeys.spaceIconColorKey: _spaceIconColor,
      ViewExtKeys.spacePermissionKey: SpacePermission.private.index,
      ViewExtKeys.spaceCreatedAtKey: DateTime.now().millisecondsSinceEpoch,
    };
    final createResult = await workspaceService.createView(
      name: localizedName,
      viewSection: ViewSectionPB.Private,
      layout: ViewLayoutPB.Document,
      extra: jsonEncode(spaceExtra),
      setAsCurrent: false,
    );

    return createResult.fold(
      (view) {
        Log.info('创建外部导入空间成功: ${view.id}');
        SpaceChangeNotifier.instance.notifySpaceCreated(view);
        return view;
      },
      (error) => throw Exception('创建外部导入空间失败: $error'),
    );
  }
}
