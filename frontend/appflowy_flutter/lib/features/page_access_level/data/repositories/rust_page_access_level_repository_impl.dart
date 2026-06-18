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
  /// 3. 接收的发布文档 → readOnly（必须在 creator 检查之前，因为复制后 createdBy 是接收者自己）
  /// 4. **显式共享权限**（HTTP API + FFI 缓存双层查询）→ 使用 API 返回值
  /// 5. page creator → fullAccess（仅当 API 无记录时）
  /// 6. 默认 → readOnly（不再对公共区域成员兜底 fullAccess）
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

    // 提取用户的 UUID（从 JWT token 中），用于 collab members 匹配
    final userUuid = _extractUserUuid(user);

    // 关键修复：显式权限检查必须在 creator 检查之前。
    // 即使当前用户是文档创建者，如果后端已将其权限修改为 readOnly，
    // 必须以显式权限为准，不能直接返回 fullAccess。
    //
    // 两层查询确保权限即时生效：
    //   1. 先查 HTTP API（直接查后端，绕过本地缓存延迟）
    //   2. 回退查 Rust FFI 本地缓存
    ShareAccessLevel? sharedUsersAccessLevel;

    // 第一层：直接查 HTTP API（确保权限变更后立即生效）
    sharedUsersAccessLevel = await _getAccessLevelFromCollabMembers(
      pageId,
      email: email,
      userId: userId,
      userUuid: userUuid,
      authToken: authToken,
    );

    // 第二层：如果 HTTP 查询失败，回退到 Rust FFI 本地缓存
    if (sharedUsersAccessLevel == null) {
      Log.debug('[PageAccessLevel] HTTP API returned null, falling back to Rust FFI cache');
      final request = GetSharedUsersPayloadPB(viewId: pageId);
      final result = await FolderEventGetSharedUsers(request).send();
      sharedUsersAccessLevel = result.fold(
        (success) {
          final matched = success.items
              .firstWhereOrNull((item) => item.email == email);
          if (matched != null) {
            Log.debug('[PageAccessLevel] FFI cache match: email=$email, '
                'permission_id=${matched.accessLevel}, '
                'shareAccessLevel=${matched.accessLevel.shareAccessLevel}');
          }
          return matched?.accessLevel.shareAccessLevel;
        },
        (failure) {
          Log.error('failed to get user access level from FFI: $failure, in page: $pageId');
          return null;
        },
      );
    }

    if (sharedUsersAccessLevel != null) {
      Log.debug('[PageAccessLevel] access level resolved: $sharedUsersAccessLevel for page: $pageId');
      return FlowyResult.success(sharedUsersAccessLevel);
    }

    // 用户不在共享列表中，回退到 creator 检查
    Log.debug('[PageAccessLevel] user not in shared list for page: $pageId, email: $email — falling back to creator check');
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

    // 修复：不再对公共区域工作区成员默认返回 fullAccess。
    // 之前的逻辑会导致被修改权限的用户（不在 collab members 列表中）
    // 仍然获得 fullAccess，权限修改无法生效。
    // 现在统一回退到 readOnly，确保只有显式授权的用户才能编辑。
    Log.debug('[PageAccessLevel] no explicit permission found for user uid=${user.id.toInt()} '
        'on page $pageId, sectionType=$sectionType, workspaceRole=${workspace.role} — '
        'defaulting to readOnly');
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

  /// 从 JWT token 中提取用户 UUID（sub 字段）
  /// 用于 collab members API 的 uid 匹配（后端 uid 是 UUID 字符串）
  String? _extractUserUuid(UserProfilePB user) {
    final rawToken = user.authToken;
    if (rawToken == null || rawToken.isEmpty) return null;

    String? accessToken = rawToken;
    if (rawToken.trimLeft().startsWith('{')) {
      try {
        final tokenMap = jsonDecode(rawToken) as Map<String, dynamic>;
        accessToken = tokenMap['access_token'] as String?;
      } catch (_) {
        return null;
      }
    }
    if (accessToken == null || accessToken.isEmpty) return null;

    final parts = accessToken.split('.');
    if (parts.length < 2) return null;
    try {
      final payload = parts[1];
      final normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
      final padding = (4 - normalized.length % 4) % 4;
      final padded = normalized + ('=' * padding);
      final decoded = utf8.decode(base64Decode(padded));
      final payloadMap = jsonDecode(decoded) as Map<String, dynamic>;
      final sub = payloadMap['sub']?.toString();
      if (sub != null && sub.isNotEmpty) return sub;
    } catch (_) {}
    return null;
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
    String? userUuid,
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

      Log.debug('[PageAccessLevel] fetching collab members: $uri, email: $email, uuid: $userUuid');

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

        Log.debug('[PageAccessLevel] collab members count: ${data.length}, '
            'searching for uid=$userId, uuid=$userUuid, email=$email');

        // 在成员列表中查找当前用户
        // 匹配优先级：UUID字符串 > 数值uid > email
        for (final member in data) {
          final memberMap = member as Map<String, dynamic>;
          final memberEmail = (memberMap['email'] as String? ?? '').trim().toLowerCase();

          // 安全解析 permission_id（后端可能返回 int 或 String）
          final rawPermId = memberMap['permission_id'];
          final int permissionId;
          if (rawPermId is int) {
            permissionId = rawPermId;
          } else if (rawPermId is String) {
            permissionId = int.tryParse(rawPermId) ?? 1;
          } else {
            permissionId = 1;
          }

          // 安全解析 uid（后端可能返回 int 或 String(UUID)）
          // 修复核心 bug：之前用 `as int?` 直接强转，后端返回 String 时
          // 抛 TypeError 被外层 catch 吞掉，导致整个函数返回 null，
          // 最终走到 creator fallback 永远返回 fullAccess。
          final rawUid = memberMap['uid'];
          final int? memberUidInt;
          final String? memberUidStr;
          if (rawUid is int) {
            memberUidInt = rawUid;
            memberUidStr = null;
          } else if (rawUid is num) {
            memberUidInt = rawUid.toInt();
            memberUidStr = null;
          } else if (rawUid is String) {
            memberUidInt = int.tryParse(rawUid);
            memberUidStr = rawUid;
          } else {
            memberUidInt = null;
            memberUidStr = null;
          }

          // 也检查 user_id / uuid 字段（不同后端版本可能用不同字段名）
          final rawUserId = memberMap['user_id'] ?? memberMap['uuid'];
          final String? memberUuid;
          if (rawUserId is String && rawUserId.isNotEmpty) {
            memberUuid = rawUserId;
          } else if (memberUidStr != null && memberUidStr.isNotEmpty &&
              memberUidStr.contains('-')) {
            memberUuid = memberUidStr;
          } else {
            memberUuid = null;
          }

          Log.debug('[PageAccessLevel] member: uid=$rawUid, uuid=$memberUuid, '
              'email=$memberEmail, permission_id=$permissionId');

          // 匹配逻辑：UUID 字符串 > 数值 uid > email
          bool uuidMatch = false;
          if (userUuid != null && userUuid.isNotEmpty && memberUuid != null) {
            uuidMatch = memberUuid == userUuid;
          }
          if (!uuidMatch && userUuid != null && userUuid.isNotEmpty &&
              memberUidStr != null) {
            uuidMatch = memberUidStr == userUuid;
          }

          final uidMatch = !uuidMatch &&
              memberUidInt != null && memberUidInt == userId;

          final emailMatch = !uuidMatch && !uidMatch &&
              email.isNotEmpty &&
              memberEmail.isNotEmpty &&
              memberEmail == email.trim().toLowerCase();

          if (uuidMatch || uidMatch || emailMatch) {
            final accessLevel = _mapPermissionIdToAccessLevel(permissionId);
            final matchBy = uuidMatch ? 'uuid' : (uidMatch ? 'uid' : 'email');
            Log.debug('[PageAccessLevel] MATCH FOUND: uid=$rawUid, uuid=$memberUuid, '
                'email=$memberEmail, permission_id=$permissionId '
                '-> $accessLevel (by $matchBy)');
            return accessLevel;
          }
        }

        Log.warn('[PageAccessLevel] user NOT found in collab members list. '
            'Looking for uid=$userId, uuid=$userUuid, email=$email, '
            'members=${data.map((m) {
              final mm = m as Map<String, dynamic>;
              return 'uid=${mm['uid']}, uuid=${mm['uuid'] ?? mm['user_id']}, '
                  'email=${mm['email']}, perm=${mm['permission_id']}';
            }).toList()}');
        return null;
      } else {
        Log.warn('[PageAccessLevel] collab members API failed: HTTP ${response.statusCode}, body: ${response.body}');
        return null;
      }
    } catch (e, stackTrace) {
      Log.warn('[PageAccessLevel] 查询 collab members 失败: $e\n$stackTrace');
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
