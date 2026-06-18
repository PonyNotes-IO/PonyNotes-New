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
    final authToken = _extractAuthToken(user);
    final receivedReadonlyResult = await _getReceivedPublishedCollabReadonly(pageId, authToken: authToken);
    if (receivedReadonlyResult.isReceived && receivedReadonlyResult.isReadonly) {
      Log.debug('page $pageId is a received published collab, setting to readonly');
      return FlowyResult.success(ShareAccessLevel.readOnly);
    }

    final email = user.email;
    final userId = user.id.toInt();

    // 通过 Rust FFI 查询本地 SQLite 缓存中的共享用户列表
    // 后台会自动同步云端数据并发送通知触发刷新
    final request = GetSharedUsersPayloadPB(viewId: pageId);
    final result = await FolderEventGetSharedUsers(request).send();
    final sharedUsersAccessLevel = result.fold(
      (success) {
        return success.items
            .firstWhereOrNull((item) =>
                item.userId != null &&
                item.userId == userId.toString())
            ?.accessLevel
            .shareAccessLevel;
      },
      (failure) {
        Log.error('failed to get user access level: $failure, in page: $pageId');
        return null;
      },
    );

    if (sharedUsersAccessLevel != null) {
      Log.debug('[PageAccessLevel] shared list returned: $sharedUsersAccessLevel for page: $pageId');
      return FlowyResult.success(sharedUsersAccessLevel);
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

    // Fall back to default permissions for workspace members in public section
    // Non-Guest workspace members get fullAccess for public section documents.
    if (workspace.role != AFRolePB.Guest &&
        sectionType == SharedSectionType.public) {
      return FlowyResult.success(ShareAccessLevel.fullAccess);
    }

    // Default to readOnly if no permission is found
    return FlowyResult.success(ShareAccessLevel.readOnly);
  }

  /// 查询接收的发布文档只读状态
  /// [authToken] 已解析好的 Bearer token，避免重复调用 GET_PROFILE
  Future<({bool isReceived, bool isReadonly})> _getReceivedPublishedCollabReadonly(
    String pageId, {
    String? authToken,
  }) async {
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

      final token = authToken ?? await _getAuthToken();
      if (token == null || token.isEmpty) {
        Log.warn('[PageAccessLevel] Auth token 为空，无法检查接收文档只读状态');
        return (isReceived: false, isReadonly: false);
      }

      final response = await http
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(
            const Duration(seconds: 3),
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
    } catch (e) {
      // 使用 Log.warn 而非 Log.error，避免在网络不稳定时产生大量错误日志
      // 超时等网络错误属于正常降级情况，不影响应用核心功能
      Log.warn(
        '[PageAccessLevel] 检查接收文档只读状态失败: $e',
      );
    }
    return (isReceived: false, isReadonly: false);
  }

  /// 从 UserProfilePB 中提取 Bearer token（不触发网络请求）
  String? _extractAuthToken(UserProfilePB user) {
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
  }

  Future<String?> _getAuthToken() async {
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      return userResult.fold(
        (user) => _extractAuthToken(user),
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

  /// 直接通过 HTTP 查询后端 collab members API 获取当前用户的权限。
  /// 绕过本地 SQLite 缓存，确保权限变更立即生效。
  /// API: GET /api/workspace/{workspace_id}/collab/{object_id}/members
  Future<ShareAccessLevel?> _getAccessLevelFromCollabMembers(
    String pageId, {
    required String email,
    required int userId,
    String? authToken,
  }) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[PageAccessLevel] Base URL 为空，无法查询 collab members');
        return null;
      }

      // 获取当前 workspace ID
      final workspaceResult = await UserBackendService.getCurrentWorkspace();
      final workspaceId = workspaceResult.fold(
        (s) => s.id,
        (_) => null,
      );

      if (workspaceId == null) {
        Log.warn('[PageAccessLevel] 无法获取当前 workspace ID');
        return null;
      }

      final token = authToken ?? await _getAuthToken();
      if (token == null || token.isEmpty) {
        Log.warn('[PageAccessLevel] Auth token 为空，无法查询 collab members');
        return null;
      }

      // GET /api/workspace/{workspace_id}/collab/{object_id}/members
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/$workspaceId/collab/$pageId/members',
      );

      Log.debug('[PageAccessLevel] fetching collab members: $uri, email: $email');

      final response = await http
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw Exception('请求超时');
            },
          );

      Log.debug('[PageAccessLevel] collab members response: HTTP ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final code = body['code'] as int?;
        if (code != null && code != 0) {
          Log.warn('[PageAccessLevel] collab members API returned error code: $code, body: ${response.body}');
          return null;
        }

        final data = body['data'] as List<dynamic>?;
        if (data == null) {
          Log.warn('[PageAccessLevel] collab members API returned data=null, body: ${response.body}');
          return null;
        }

        Log.debug('[PageAccessLevel] collab members count: ${data.length}, searching for uid=$userId, email=$email');

        // 在成员列表中查找当前用户
        // 优先通过 uid 匹配（最可靠），回退到 email 匹配
        for (final member in data) {
          final memberMap = member as Map<String, dynamic>;
          final memberUid = memberMap['uid'] as int?;
          final memberEmail = (memberMap['email'] as String? ?? '').trim().toLowerCase();
          final permissionId = memberMap['permission_id'] as int? ?? 1;

          Log.debug('[PageAccessLevel] member: uid=$memberUid, email=$memberEmail, permission_id=$permissionId');

          // 优先 uid 匹配
          final uidMatch = memberUid != null && memberUid == userId;
          // 回退 email 匹配（仅当 email 非空时）
          final emailMatch = email.isNotEmpty &&
              memberEmail.isNotEmpty &&
              memberEmail == email.trim().toLowerCase();

          if (uidMatch || emailMatch) {
            final accessLevel = _mapPermissionIdToAccessLevel(permissionId);
            Log.debug('[PageAccessLevel] MATCH FOUND: uid=$memberUid, email=$memberEmail, '
                'permission_id=$permissionId -> $accessLevel (by ${uidMatch ? "uid" : "email"})');
            return accessLevel;
          }
        }

        Log.warn('[PageAccessLevel] user NOT found in collab members list. '
            'Looking for uid=$userId, email=$email, '
            'members=${data.map((m) => 'uid=${(m as Map)['uid']}, email=${m['email']}, perm=${m['permission_id']}').toList()}');
        return null;
      } else {
        Log.warn('[PageAccessLevel] collab members API failed: HTTP ${response.statusCode}, body: ${response.body}');
        return null;
      }
    } catch (e) {
      Log.warn('[PageAccessLevel] 查询 collab members 失败: $e');
      return null;
    }
  }

  /// 将后端 permission_id 映射为 ShareAccessLevel
  /// 后端定义：1=ReadOnly, 2=ReadAndComment, 3=ReadAndWrite, 4=FullAccess
  ShareAccessLevel _mapPermissionIdToAccessLevel(int permissionId) {
    switch (permissionId) {
      case 1:
        return ShareAccessLevel.readOnly;
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
}
