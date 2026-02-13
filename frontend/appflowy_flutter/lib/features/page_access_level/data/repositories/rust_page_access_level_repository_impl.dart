import 'package:appflowy/features/page_access_level/data/repositories/page_access_level_repository.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/util/extensions.dart';
import 'package:appflowy/env/cloud_env.dart';
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
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:appflowy/startup/startup.dart';
import 'dart:convert';

class RustPageAccessLevelRepositoryImpl implements PageAccessLevelRepository {
  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String pageId) async {
    final result = await ViewBackendService.getView(pageId);
    return result.fold(
      (view) {
        Log.debug('get view(${view.id}) success');
        return FlowyResult.success(view);
      },
      (error) {
        Log.error('failed to get view, error: $error');
        return FlowyResult.failure(error);
      },
    );
  }

  @override
  Future<FlowyResult<void, FlowyError>> lockView(String pageId) async {
    final result = await ViewBackendService.lockView(pageId);
    return result.fold(
      (_) {
        Log.debug('lock view($pageId) success');
        return FlowyResult.success(null);
      },
      (error) {
        Log.error('failed to lock view, error: $error');
        return FlowyResult.failure(error);
      },
    );
  }

  @override
  Future<FlowyResult<void, FlowyError>> unlockView(String pageId) async {
    final result = await ViewBackendService.unlockView(pageId);
    return result.fold(
      (_) {
        Log.debug('unlock view($pageId) success');
        return FlowyResult.success(null);
      },
      (error) {
        Log.error('failed to unlock view, error: $error');
        return FlowyResult.failure(error);
      },
    );
  }

  /// 1. local users have full access
  /// 2. local workspace users have full access
  /// 3. page creator has full access
  /// 4. owner and members in public page have full access
  /// 5. check the shared users list
  /// 6. check if the page is a received published collab (should be readonly)
  @override
  Future<FlowyResult<ShareAccessLevel, FlowyError>> getAccessLevel(
    String pageId,
  ) async {
    final userResult = await UserBackendService.getCurrentUserProfile();
    final user = userResult.fold(
      (s) => s,
      (_) => null,
    );

    if (user == null) {
      return FlowyResult.failure(
        FlowyError(
          code: ErrorCode.Internal,
          msg: 'User not found',
        ),
      );
    }

    if (user.userAuthType == AuthTypePB.Local) {
      // Local user can always have full access.
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

    if (user.workspaceType == WorkspaceTypePB.LocalW) {
      // Local workspace can always have full access.
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

    // If the user is the creator of the page, they can always have full access.
    final viewResult = await getView(pageId);
    final view = viewResult.fold(
      (s) => s,
      (_) => null,
    );
    if (view?.createdBy == user.id) {
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

    // Check if the page is a received published collab
    // If it is, it should be readonly regardless of other permissions
    final receivedReadonlyResult = await _getReceivedPublishedCollabReadonly(pageId);
    if (receivedReadonlyResult.isReceived && receivedReadonlyResult.isReadonly) {
      Log.debug('page $pageId is a received published collab, setting to readonly');
      return FlowyResult.success(ShareAccessLevel.readOnly);
    }

    // If the page is public, the user can always have full access.
    final workspaceResult = await getCurrentWorkspace();
    final workspace = workspaceResult.fold(
      (s) => s,
      (_) => null,
    );
    if (workspace == null) {
      return FlowyResult.failure(
        FlowyError(
          code: ErrorCode.Internal,
          msg: 'Current workspace not found',
        ),
      );
    }

    final sectionTypeResult = await getSectionType(pageId);
    final sectionType = sectionTypeResult.fold(
      (s) => s,
      (_) => null,
    );
    if (sectionType == SharedSectionType.public &&
        workspace.role != AFRolePB.Guest) {
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

    final email = user.email;

    final request = GetSharedUsersPayloadPB(
      viewId: pageId,
    );
    final result = await FolderEventGetSharedUsers(request).send();
    return result.fold(
      (success) {
        final accessLevel = success.items
                .firstWhereOrNull(
                  (item) => item.email == email,
                )
                ?.accessLevel
                .shareAccessLevel ??
            ShareAccessLevel.readOnly;

        Log.debug('current user access level: $accessLevel, in page: $pageId');

        return FlowyResult.success(accessLevel);
      },
      (failure) {
        Log.error(
          'failed to get user access level: $failure, in page: $pageId',
        );

        // return the read access level if the user is not found
        return FlowyResult.success(ShareAccessLevel.readOnly);
      },
    );
  }

  /// 查询接收的发布文档只读状态
  Future<({bool isReceived, bool isReadonly})> _getReceivedPublishedCollabReadonly(
    String pageId,
  ) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[PageAccessLevel] Base URL 为空，无法检查接收文档只读状态');
        return (isReceived: false, isReadonly: false);
      }

      final uri = Uri.parse(baseUrl).replace(
        // 注意：后端 API 是在 /api/workspace scope 下定义的
        path: '/api/workspace/published/received/$pageId/readonly',
      );

      final authToken = await _getAuthToken();
      if (authToken == null || authToken.isEmpty) {
        Log.warn('[PageAccessLevel] Auth token 为空，无法检查接收文档只读状态');
        return (isReceived: false, isReadonly: false);
      }

      final response = await http
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('请求超时');
            },
          );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final data = body['data'];
          if (data is Map<String, dynamic>) {
            final isReceived = data['is_received'] as bool? ?? false;
            final isReadonly = data['is_readonly'] as bool? ?? false;
            return (isReceived: isReceived, isReadonly: isReadonly);
          }
        }
      }
    } catch (e, stackTrace) {
      Log.error(
        '[PageAccessLevel] 检查接收文档只读状态失败: $e',
        stackTrace,
      );
    }
    return (isReceived: false, isReadonly: false);
  }

  /// 获取 auth token
  Future<String?> _getAuthToken() async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        return null;
      }

      // 构建 API URL: /api/user/me
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/user/me',
      );

      final response = await http
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
            },
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('请求超时');
            },
          );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final data = body['data'];
          if (data is Map<String, dynamic>) {
            final token = data['token'] as String?;
            return token;
          }
        }
      }
    } catch (e) {
      Log.error('[PageAccessLevel] 获取 token 时出错: $e');
    }
    return null;
  }

  @override
  Future<FlowyResult<SharedSectionType, FlowyError>> getSectionType(
    String pageId,
  ) async {
    final request = ViewIdPB(value: pageId);
    final result = await FolderEventGetSharedViewSection(request).send();
    return result.fold(
      (success) {
        final sectionType = success.section.sharedSectionType;
        Log.debug('shared section type: $sectionType, in page: $pageId');
        return FlowyResult.success(sectionType);
      },
      (failure) {
        Log.error(
          'failed to get shared section type: $failure, in page: $pageId',
        );

        return FlowyResult.failure(failure);
      },
    );
  }

  @override
  Future<FlowyResult<UserWorkspacePB, FlowyError>> getCurrentWorkspace() async {
    final result = await UserBackendService.getCurrentWorkspace();
    final currentWorkspaceId = result.fold(
      (s) => s.id,
      (_) => null,
    );

    if (currentWorkspaceId == null) {
      return FlowyResult.failure(
        FlowyError(
          code: ErrorCode.Internal,
          msg: 'Current workspace not found',
        ),
      );
    }

    final workspaceResult = await UserBackendService.getWorkspaceById(
      currentWorkspaceId,
    );
    return workspaceResult;
  }
}
