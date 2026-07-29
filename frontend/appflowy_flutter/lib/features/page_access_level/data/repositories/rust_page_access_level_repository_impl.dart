import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/page_access_level/data/repositories/page_access_level_repository.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/util/extensions.dart';
import 'package:appflowy/shared/af_user_profile_extension.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:http/http.dart' as http;

/// Cloud permissions are resolved from the document-sharing aggregate. This
/// repository deliberately has no current-workspace or FFI permission fallback:
/// those sources are stale or unrelated when a shared document is open in a
/// different workspace.
class RustPageAccessLevelRepositoryImpl implements PageAccessLevelRepository {
  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String pageId) async {
    final result = await ViewBackendService.getView(pageId);
    return result.fold(
      FlowyResult.success,
      FlowyResult.failure,
    );
  }

  @override
  Future<FlowyResult<void, FlowyError>> lockView(String pageId) async {
    final result = await ViewBackendService.lockView(pageId);
    return result.fold(FlowyResult.success, FlowyResult.failure);
  }

  @override
  Future<FlowyResult<void, FlowyError>> unlockView(String pageId) async {
    final result = await ViewBackendService.unlockView(pageId);
    return result.fold(FlowyResult.success, FlowyResult.failure);
  }

  @override
  Future<FlowyResult<ShareAccessLevel, FlowyError>> getAccessLevel(
    String pageId,
  ) async {
    final userResult = await UserBackendService.getCurrentUserProfile();
    final user = userResult.fold((value) => value, (_) => null);
    if (user == null) {
      return _unverified('无法验证当前账号的文档权限');
    }

    // Local-only users never call the cloud and therefore remain fully local.
    if (user.userAuthType == AuthTypePB.Local ||
        user.workspaceType == WorkspaceTypePB.LocalW) {
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

    final token = _extractAuthToken(user);
    if (token == null || token.isEmpty) {
      return _unverified('权限待验证：登录令牌不可用');
    }

    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        return _unverified('权限待验证：服务地址不可用');
      }

      final response = await http.get(
        Uri.parse(baseUrl).replace(path: '/api/document-shares/$pageId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        Log.warn(
          '[PageAccessLevel] document snapshot failed: '
          'page=$pageId status=${response.statusCode}',
        );
        return _unverified('权限待验证：服务端未确认文档访问权');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['code'] is int && body['code'] != 0) {
        return _unverified('权限待验证：服务端返回了权限错误');
      }
      final snapshot = body['data'] as Map<String, dynamic>?;
      final permissionId = _asInt(snapshot?['permission_id']);
      if (permissionId == null || permissionId < 1 || permissionId > 4) {
        return _unverified('权限待验证：文档权限数据无效');
      }
      return FlowyResult.success(_accessLevel(permissionId));
    } catch (error) {
      Log.warn('[PageAccessLevel] document permission check failed: $error');
      return _unverified('权限待验证：网络或文档定位异常');
    }
  }

  @override
  Future<FlowyResult<SharedSectionType, FlowyError>> getSectionType(
    String pageId,
  ) async {
    final result =
        await FolderEventGetSharedViewSection(ViewIdPB(value: pageId)).send();
    return result.fold(
      (value) => FlowyResult.success(value.section.sharedSectionType),
      FlowyResult.failure,
    );
  }

  @override
  Future<FlowyResult<UserWorkspacePB, FlowyError>> getCurrentWorkspace() async {
    final currentWorkspace = await UserBackendService.getCurrentWorkspace();
    final workspaceId = currentWorkspace.fold((value) => value.id, (_) => null);
    if (workspaceId == null || workspaceId.isEmpty) {
      return FlowyResult.failure(
        FlowyError(
          code: ErrorCode.Internal,
          msg: 'Current workspace not found',
        ),
      );
    }
    return UserBackendService.getWorkspaceById(workspaceId);
  }

  FlowyResult<ShareAccessLevel, FlowyError> _unverified(String message) {
    return FlowyResult.failure(
      FlowyError(
        code: ErrorCode.Internal,
        msg: message,
      ),
    );
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  ShareAccessLevel _accessLevel(int permissionId) {
    switch (permissionId) {
      case 2:
        return ShareAccessLevel.readAndComment;
      case 3:
        return ShareAccessLevel.readAndWrite;
      case 4:
        return ShareAccessLevel.fullAccess;
      default:
        return ShareAccessLevel.readOnly;
    }
  }

  String? _extractAuthToken(UserProfilePB user) {
    final rawToken = user.authToken;
    if (rawToken == null || rawToken.isEmpty) return null;
    try {
      final value = jsonDecode(rawToken);
      if (value is Map<String, dynamic>) {
        final token = value['access_token'] as String?;
        if (token != null && token.isNotEmpty) return token;
      }
    } catch (_) {
      // Raw JWT tokens are valid too.
    }
    return rawToken;
  }
}
