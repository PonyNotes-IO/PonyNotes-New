import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';

/// 工作区权限服务
/// 提供集中式的权限检查，确保 Guest（受限成员）无法执行创建、删除等操作
class WorkspacePermissionService {
  /// 检查当前用户是否有创建权限
  /// Guest（受限成员）无法创建文档和空间
  static Future<bool> canCreate({
    required String workspaceId,
    required int userId,
  }) async {
    return _checkPermission(
      workspaceId: workspaceId,
      userId: userId,
      allowedRoles: [AFRolePB.Owner, AFRolePB.Member],
    );
  }

  /// 检查当前用户是否有删除权限
  /// Guest（受限成员）无法删除空间
  static Future<bool> canDelete({
    required String workspaceId,
    required int userId,
  }) async {
    return _checkPermission(
      workspaceId: workspaceId,
      userId: userId,
      allowedRoles: [AFRolePB.Owner, AFRolePB.Member],
    );
  }

  /// 检查当前用户是否有修改权限
  /// Guest（受限成员）无法修改空间
  static Future<bool> canModify({
    required String workspaceId,
    required int userId,
  }) async {
    return _checkPermission(
      workspaceId: workspaceId,
      userId: userId,
      allowedRoles: [AFRolePB.Owner, AFRolePB.Member],
    );
  }

  /// 检查当前用户是否有重命名权限
  /// Guest（受限成员）无法重命名空间
  static Future<bool> canRename({
    required String workspaceId,
    required int userId,
  }) async {
    return _checkPermission(
      workspaceId: workspaceId,
      userId: userId,
      allowedRoles: [AFRolePB.Owner, AFRolePB.Member],
    );
  }

  /// 获取当前用户在工作区中的角色
  static Future<AFRolePB?> getCurrentUserRole({
    required String workspaceId,
    required int userId,
  }) async {
    try {
      final service = UserBackendService(userId: Int64(userId));
      final result = await service.getWorkspaceMembers(workspaceId);
      return result.fold(
        (members) {
          final myMember = members.items.firstWhereOrNull(
            (m) => m.uid.toInt() == userId,
          );
          return myMember?.role;
        },
        (e) {
          Log.error('Failed to get user role: ${e.msg}');
          return null;
        },
      );
    } catch (e, st) {
      Log.error('Exception when getting user role: $e\n$st');
      return null;
    }
  }

  /// 通用权限检查方法
  static Future<bool> _checkPermission({
    required String workspaceId,
    required int userId,
    required List<AFRolePB> allowedRoles,
  }) async {
    try {
      final role = await getCurrentUserRole(
        workspaceId: workspaceId,
        userId: userId,
      );
      if (role == null) {
        // 无法获取角色时，默认允许（后端会执行最终检查）
        return true;
      }
      return allowedRoles.contains(role);
    } catch (e, st) {
      Log.error('Exception when checking permission: $e\n$st');
      return true;
    }
  }
}
