import 'package:appflowy/features/page_access_level/data/repositories/page_access_level_repository.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/util/extensions.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/shared/af_user_profile_extension.dart';
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

  /// 权限检查优先级（从高到低）：
  /// 1. local users → fullAccess
  /// 2. local workspace → fullAccess
  /// 3. **接收的发布文档 → readOnly**（必须在 creator 检查之前，因为复制后 createdBy 是接收者自己）
  /// 4. page creator → fullAccess
  /// 5. public page owner/member → fullAccess
  /// 6. shared users list
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
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

    if (user.workspaceType == WorkspaceTypePB.LocalW) {
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

    // 关键修复：接收的发布文档检查必须在 creator 检查之前
    // 因为 receive_published_collab 复制文档时 created_by 设为了接收者的 uid，
    // 如果先检查 creator，接收者会被误判为"创建者"而获得 fullAccess
    final receivedReadonlyResult = await _getReceivedPublishedCollabReadonly(pageId);
    if (receivedReadonlyResult.isReceived && receivedReadonlyResult.isReadonly) {
      Log.debug('page $pageId is a received published collab, setting to readonly');
      return FlowyResult.success(ShareAccessLevel.readOnly);
    }

    final viewResult = await getView(pageId);
    final view = viewResult.fold(
      (s) => s,
      (_) => null,
    );
    if (view?.createdBy == user.id) {
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

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

    // Non-Guest workspace members get fullAccess for public section documents.
    // When sectionType is null (getSectionType failed because the folder collab
    // hadn't finished initializing yet), we also grant fullAccess. This handles
    // the timing issue where B opens A's old documents before the folder is ready:
    //   - Private docs explicitly return PrivateSection when the folder IS loaded
    //   - SharedSection docs (cross-workspace explicit shares) should go through
    //     the explicit shared-users permission check below
    //   - The backend Casbin enforces actual write access regardless of this flag
    if (workspace.role != AFRolePB.Guest &&
        (sectionType == SharedSectionType.public || sectionType == null)) {
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

  Future<String?> _getAuthToken() async {
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      return userResult.fold(
        (user) {
          final rawToken = user.authToken;
          if (rawToken == null || rawToken.isEmpty) return null;
          try {
            final decoded = jsonDecode(rawToken);
            if (decoded is Map<String, dynamic>) {
              final accessToken = decoded['access_token'] as String?;
              if (accessToken != null && accessToken.isNotEmpty) {
                return accessToken;
              }
            }
          } catch (_) {}
          return rawToken;
        },
        (error) {
          Log.warn('[PageAccessLevel] 获取用户信息失败: $error');
          return null;
        },
      );
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
