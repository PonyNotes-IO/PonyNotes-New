import 'dart:convert';

import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:fixnum/fixnum.dart' as fixnum;

/// 桌面端和移动端共用的“最近访问”私有空间解析服务。
///
/// “最近访问”是已经写入用户数据的固定系统空间名称，因此这里使用稳定的
/// 持久化名称进行识别，而不是跟随客户端显示语言变化，避免跨设备重复创建。
class RecentAccessSpaceService {
  RecentAccessSpaceService({
    required this.workspaceId,
    required fixnum.Int64 userId,
    WorkspaceService? workspaceService,
    void Function(String message)? logInfo,
  })  : _workspaceService = workspaceService ??
            WorkspaceService(
              workspaceId: workspaceId,
              userId: userId,
            ),
        _logInfo = logInfo ?? Log.info;

  static const spaceName = '最近访问';

  final String workspaceId;
  final WorkspaceService _workspaceService;
  final void Function(String message) _logInfo;

  static final Map<String, Future<RecentAccessSpaceResult>> _pendingOperations =
      {};

  /// 查找“最近访问”私有空间；不存在时自动创建。
  ///
  /// 同一工作区中的并发调用共享一次进行中的查询/创建任务，避免用户连续点击
  /// 新建按钮时创建出多个同名空间。
  Future<RecentAccessSpaceResult> getOrCreate() async {
    final pending = _pendingOperations[workspaceId];
    if (pending != null) {
      final result = await pending;
      return result;
    }

    final operation = _getOrCreate();
    _pendingOperations[workspaceId] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_pendingOperations[workspaceId], operation)) {
        final _ = _pendingOperations.remove(workspaceId);
      }
    }
  }

  Future<RecentAccessSpaceResult> _getOrCreate() async {
    final privateViewsResult = await _workspaceService.getPrivateViews();
    final privateViews = privateViewsResult.fold(
      (views) => views,
      (error) => throw RecentAccessSpaceException(
        '获取私有空间失败: ${error.msg}',
      ),
    );

    for (final view in privateViews) {
      if (view.isSpace && view.name == spaceName) {
        _logInfo('找到已存在的“$spaceName”私有空间，ID: ${view.id}');
        return RecentAccessSpaceResult(space: view, wasCreated: false);
      }
    }

    _logInfo('私有空间中不存在“$spaceName”，开始自动创建');
    final result = await _workspaceService.createView(
      name: spaceName,
      viewSection: ViewSectionPB.Private,
      layout: ViewLayoutPB.Document,
      setAsCurrent: false,
      extra: jsonEncode({
        ViewExtKeys.isSpaceKey: true,
        ViewExtKeys.spaceIconKey: '📋',
        ViewExtKeys.spaceIconColorKey: '#4A90E2',
        ViewExtKeys.spacePermissionKey: SpacePermission.private.index,
        ViewExtKeys.spaceCreatedAtKey: DateTime.now().millisecondsSinceEpoch,
      }),
    );

    return result.fold(
      (view) {
        _logInfo('成功创建“$spaceName”私有空间，ID: ${view.id}');
        return RecentAccessSpaceResult(space: view, wasCreated: true);
      },
      (error) => throw RecentAccessSpaceException(
        '创建“$spaceName”私有空间失败: ${error.msg}',
      ),
    );
  }
}

class RecentAccessSpaceResult {
  const RecentAccessSpaceResult({
    required this.space,
    required this.wasCreated,
  });

  final ViewPB space;
  final bool wasCreated;
}

class RecentAccessSpaceException implements Exception {
  const RecentAccessSpaceException(this.message);

  final String message;

  @override
  String toString() => message;
}
