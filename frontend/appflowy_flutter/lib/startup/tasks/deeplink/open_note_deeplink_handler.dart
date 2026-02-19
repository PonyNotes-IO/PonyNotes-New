import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:appflowy/core/notification/folder_notification.dart';
import 'package:appflowy/shared/af_user_profile_extension.dart';
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/notification.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/protobuf.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/panels/publish_notifier.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../../../env/cloud_env.dart';
import '../../../generated/locale_keys.g.dart';
import '../../../user/application/user_service.dart';
import '../../startup.dart';
import '../app_widget.dart';

/// 处理打开笔记的深度链接
/// 支持的URI格式: ponynotes://note?viewId=xxx
/// 或者: ponynotes://open?viewId=xxx
class OpenNoteDeepLinkHandler extends DeepLinkHandler<void> {
  @override
  bool canHandle(Uri uri) {
    // 检查是否是打开笔记的深度链接（兼容 host 或 path 形式）
    final host = uri.host;
    final path = uri.path;

    // 原有格式: ponynotes://note?viewId=xxx 或 ponynotes://open?viewId=xxx
    final isNotePath =
        host == 'note' || host == 'open' || path == 'note' || path == 'open';

    // 新格式: https://www.xiaomabiji.com/share?viewId=xxx&type=publish
    // 支持任意域名下的 /share 路径，带 viewId 和 type=publish 参数
    final isSharePath = path == '/share' || path == 'share';
    final hasViewId = uri.queryParameters.containsKey('viewId');
    final linkType = uri.queryParameters['type'];
    final isPublishType = linkType == 'publish';

    // 支持两种格式：
    // 1. ponynotes://note?viewId=xxx 或 ponynotes://open?viewId=xxx
    // 2. https://domain/share?viewId=xxx&type=publish
    return (isNotePath && hasViewId) ||
        (isSharePath && hasViewId && isPublishType);
  }

  @override
  Future<FlowyResult<void, FlowyError>> handle({
    required Uri uri,
    required DeepLinkStateHandler onStateChange,
  }) async {
    onStateChange(this, DeepLinkState.loading);

    try {
      // 从URI中获取参数
      final viewId = uri.queryParameters['viewId'];
      final targetWorkspaceId = uri.queryParameters['workspaceId'];
      final linkType = uri.queryParameters['type']; // 获取链接类型：share 或 publish
      final permissionParam = uri.queryParameters['permission']; // 获取分享链接权限参数
      // 解析权限ID，默认只读权限(1)
      final permissionId = permissionParam != null 
          ? int.tryParse(permissionParam) ?? 1 
          : 1;

      if (viewId == null || viewId.isEmpty) {
        Log.error('[OpenNoteDeepLinkHandler] viewId参数为空');
        onStateChange(this, DeepLinkState.error);
        return FlowyResult.failure(
          FlowyError()
            ..msg = 'viewId参数不能为空'
            ..code = ErrorCode.InvalidParams,
        );
      }

      // workspaceId 仅作为后端识别上下文的参数，前端不再主动切换工作区，
      // 由 Rust 侧的 open_document / view 服务自行处理跨工作区打开逻辑。
      final workspaceId = targetWorkspaceId;

      // 如果是分享链接（type=share），尝试将当前用户添加到协作中，
      // 具体权限与视图可见性仍由后端控制。
      if (linkType == 'share' &&
          workspaceId != null &&
          workspaceId.isNotEmpty) {
        await _addUserToCollaboration(
          workspaceId: workspaceId,
          viewId: viewId,
          permissionId: permissionId,
        );
      }

      // 如果是发布链接（type=publish），调用 receive API 接收文档
      String effectiveViewId = viewId;
      bool isReadonly = false;

      if (linkType == 'publish' &&
          workspaceId != null &&
          workspaceId.isNotEmpty) {
        Log.info(
            '[OpenNoteDeepLinkHandler] 处理发布链接: viewId=$viewId, workspaceId=$workspaceId');

        // 获取当前用户的工作区ID（而不是使用链接中的发布者工作区ID）
        final currentWorkspaceId = await _getCurrentWorkspaceId();
        if (currentWorkspaceId == null || currentWorkspaceId.isEmpty) {
          Log.warn('[OpenNoteDeepLinkHandler] 无法获取当前用户工作区，使用链接中的workspaceId');
          // 如果获取失败，尝试使用链接中的workspaceId（这可能会导致问题）
        }

        // 调用 receive API 接收发布的文档，使用当前用户的工作区ID
        final receiveResult = await _receivePublishedCollab(
          publishedViewId: viewId,
          workspaceId: currentWorkspaceId ?? workspaceId,
        );

        if (receiveResult.$1) {
          effectiveViewId = receiveResult.$3;
          isReadonly = receiveResult.$4;
          Log.info(
              '[OpenNoteDeepLinkHandler] 接收发布文档成功: receivedViewId=$effectiveViewId, isReadonly=$isReadonly');
          // 刷新侧边栏
          PublishRefresh.ping();
        } else {
          Log.warn(
              '[OpenNoteDeepLinkHandler] 接收发布文档失败: ${receiveResult.$2}，尝试使用原viewId打开');
          // 即使接收失败也继续打开，使用原始viewId
          effectiveViewId = viewId;
          isReadonly = true;
        }
      }

      // 直接通过 DocumentService 打开文档，不依赖 ViewBackendService.getView
      // 因为某些情况下 getView 可能获取不到，但 openDocument 可以成功
      bool documentOpened = false;
      try {
        final docResult = await DocumentService().openDocument(
          documentId: effectiveViewId,
        );
        await docResult.fold(
          (_) async {
            documentOpened = true;
            // 等待一小段时间，确保文档数据已经加载完成
            await Future.delayed(const Duration(milliseconds: 300));
          },
          (error) async {
            Log.warn(
              '📝 [OpenNoteDeepLinkHandler] open_document 失败: ${error.msg}',
            );
            documentOpened = false;
          },
        );
      } catch (e, stackTrace) {
        Log.error(
            '[OpenNoteDeepLinkHandler] 调用 open_document 时异常: $e', stackTrace);
        documentOpened = false;
      }

      // 只有在文档成功打开后，才在UI中显示视图
      if (!documentOpened) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] 文档打开失败，无法显示视图');
        onStateChange(this, DeepLinkState.error);
        return FlowyResult.failure(
          FlowyError()
            ..msg = '文档打开失败，无法显示笔记'
            ..code = ErrorCode.Internal,
        );
      }

      // 获取发布笔记的真实标题（用于发布链接或协作分享链接）
      // 传入 viewId 和 workspaceId，以便获取协作文档的真实名称
      final viewName = await _getViewName(viewId, workspaceId);

      // 创建最小化的 ViewPB 对象，用于在UI中打开视图
      // 如果是发布的文档（只读），设置 is_locked = true
      final minimalView = ViewPB()
        ..id = effectiveViewId // 使用接收后的 viewId
        ..name = viewName // 使用真实标题，如果没有则使用默认名称
        ..layout = ViewLayoutPB.Document
        ..isLocked = isReadonly; // 设置只读锁定状态

      // 等待应用初始化完成后再打开视图
      // 使用WidgetsBinding确保在UI线程中执行
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          // 获取TabsBloc实例
          final navContext = AppGlobals.rootNavKey.currentState?.context;
          if (navContext == null) {
            Log.error('[OpenNoteDeepLinkHandler] 无法获取BuildContext，应用可能未完全初始化');
            // 如果应用未初始化，延迟一段时间后重试
            await Future.delayed(const Duration(seconds: 1));
            final retryContext = AppGlobals.rootNavKey.currentState?.context;
            if (retryContext == null) {
              Log.error('[OpenNoteDeepLinkHandler] 重试后仍无法获取BuildContext');
              return;
            }
            _openView(retryContext, minimalView);
          } else {
            _openView(navContext, minimalView);
          }
        } catch (e, stackTrace) {
          Log.error('[OpenNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
        }
      });

      onStateChange(this, DeepLinkState.finish);
      return FlowyResult.success(null);
    } catch (e, stackTrace) {
      Log.error('[OpenNoteDeepLinkHandler] 处理深度链接时出错: $e', stackTrace);
      onStateChange(this, DeepLinkState.error);
      return FlowyResult.failure(
        FlowyError()
          ..msg = '处理深度链接时出错: $e'
          ..code = ErrorCode.Internal,
      );
    }
  }

  /// 打开视图
  void _openView(BuildContext context, ViewPB view) {
    try {
      // 通过 ActionNavigationBloc 触发打开逻辑，避免直接依赖 TabsBloc
      final actionBloc = context.read<ActionNavigationBloc?>();

      if (actionBloc != null) {
        actionBloc.add(
          ActionNavigationEvent.performAction(
            action: NavigationAction(
              objectId: view.id,
              arguments: {
                ActionArgumentKeys.view: view,
              },
            ),
            showErrorToast: true,
          ),
        );
      } else {
        // 兜底：如果 ActionNavigationBloc 不存在，再尝试直接使用 TabsBloc
        final tabsBloc = context.read<TabsBloc>();
        tabsBloc.openPlugin(view);
      }
    } catch (e, stackTrace) {
      Log.error('📝 [OpenNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
    }
  }

  /// 将当前用户添加到协作中（用于分享链接）
  /// permissionId: 权限ID，1=查看，2=评论，3=编辑，4=全部权限
  Future<void> _addUserToCollaboration({
    required String workspaceId,
    required String viewId,
    int permissionId = 1, // 默认只读权限
  }) async {
    try {
      // 获取当前用户信息
      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) {
          Log.warn('📝 [OpenNoteDeepLinkHandler] 获取用户信息失败: $error');
          return null;
        },
      );

      if (userProfile == null) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] 用户信息为空，跳过添加协作');
        return;
      }

      // 获取 auth token
      final authToken = userProfile.authToken;
      if (authToken == null || authToken.isEmpty) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] Auth token 为空，跳过添加协作');
        return;
      }

      // 获取用户ID
      final userId = _getUserId(authToken);
      if (userId == null || userId.isEmpty) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] 用户ID为空，跳过添加协作');
        return;
      }
      // 获取 base URL
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] Base URL 为空，跳过添加协作');
        return;
      }

      // 构建 API URL: /api/workspace/{workspace_id}/collab/{object_id}/members/{member_user_id}
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/$workspaceId/collab/$viewId/members/$userId',
      );

      // 发送 POST 请求，传递 permission_id 参数（默认只读权限 = 1）
      // 这样后端会正确创建 af_collab_member 和 af_collab_member_invite 记录
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_extractAccessToken(authToken)}',
        },
        body: jsonEncode({
          'permission_id': permissionId, // 使用分享链接中的权限参数
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Success 刷新共享列表处理
        Log.info('[OpenNoteDeepLinkHandler] 添加协作成功');
      } else if (response.statusCode == 409) {
        // 409 表示用户已经在协作中，这是正常情况，不需要报错
      } else {
        Log.warn(
            '[OpenNoteDeepLinkHandler] 添加协作失败: HTTP ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      // 添加协作失败不应该阻止打开笔记，只记录错误
      Log.error(
        '[OpenNoteDeepLinkHandler] 添加用户到协作时出错: $e',
        stackTrace,
      );
    }
  }

  String? _extractAccessToken(String? rawToken) {
    if (rawToken == null || rawToken.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawToken);
      if (decoded is Map<String, dynamic>) {
        final accessToken = decoded['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          return accessToken;
        }
      }
    } catch (_) {
      // 非 JSON，直接使用原始 token
      return rawToken;
    }
    return null;
  }

  String? _getUserId(String? rawToken) {
    if (rawToken == null || rawToken.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawToken);
      if (decoded is Map<String, dynamic>) {
        final user = decoded['user'];
        if (user is Map<String, dynamic>) {
          return user['id'];
        } else {
          return null;
        }
      }
    } catch (_) {
      // 非 JSON，直接使用原始 token
      return rawToken;
    }
    return null;
  }

  /// 获取视图名称
  /// 优先从发布元数据获取，如果是协作分享链接则通过 ViewBackendService 获取
  Future<String> _getViewName(String viewId, String? workspaceId) async {
    // 首先尝试从发布元数据获取名称
    final publishName = await _getViewNameFromPublishInfo(viewId);
    
    // 如果获取到的是空字符串（说明是协作分享链接），或者获取到的是默认名称，尝试通过 ViewBackendService 获取
    final defaultName = LocaleKeys.menuAppHeader_defaultNewNotebookName.tr();
    if (publishName.isEmpty || publishName == defaultName) {
      if (workspaceId != null && workspaceId.isNotEmpty) {
        return _getCollabViewName(viewId, workspaceId);
      }
    }
    
    // 如果获取到了有效的名称，直接返回
    if (publishName.isNotEmpty) {
      return publishName;
    }
    
    // 否则返回默认名称
    return defaultName;
  }

  /// 从发布元数据获取视图名称
  /// 如果获取失败，则使用默认名称
  Future<String> _getViewNameFromPublishInfo(String viewId) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[OpenNoteDeepLinkHandler] Base URL 为空，使用默认名称');
        return LocaleKeys.menuAppHeader_defaultNewNotebookName.tr();
      }

      // 构建 API URL: /api/workspace/v1/published-info/{view_id}
      // 这个 API 不需要登录认证，可以公开访问
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/v1/published-info/$viewId',
      );

      final response = await http.get(uri).timeout(
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
            final metadata = data['metadata'];
            if (metadata is Map<String, dynamic>) {
              // metadata 结构: { "view": { "name": "笔记名称", ... } }
              final view = metadata['view'];
              if (view is Map<String, dynamic>) {
                final name = view['name'] as String?;
                if (name != null && name.isNotEmpty) {
                  Log.info('[OpenNoteDeepLinkHandler] 从发布元数据获取到标题: $name');
                  return name;
                }
              }
            }
          }
        }
      } else if (response.statusCode == 404) {
        // 404 表示笔记未发布（可能是纯协作分享链接），返回空字符串表示需要使用其他方式获取
        Log.info('[OpenNoteDeepLinkHandler] 笔记未发布，将尝试其他方式获取名称');
        return '';
      } else {
        Log.warn(
            '[OpenNoteDeepLinkHandler] 获取发布信息失败: HTTP ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      Log.error(
        '[OpenNoteDeepLinkHandler] 获取发布信息时出错: $e',
        stackTrace,
      );
    }

    // 获取失败时使用空字符串，由调用方决定是否使用默认名称
    return '';
  }

  /// 通过 ViewBackendService 获取协作文档的名称
  /// 用于协作分享链接（非发布文档）的场景
  Future<String> _getCollabViewName(String viewId, String workspaceId) async {
    try {
      Log.info('[OpenNoteDeepLinkHandler] 尝试通过 ViewBackendService 获取协作文档名称: viewId=$viewId, workspaceId=$workspaceId');
      
      // 使用 ViewBackendService.getView 获取视图信息
      final result = await ViewBackendService.getView(viewId);
      
      return result.fold(
        (view) {
          if (view.name.isNotEmpty) {
            Log.info('[OpenNoteDeepLinkHandler] 从 ViewBackendService 获取到标题: ${view.name}');
            return view.name;
          }
          Log.warn('[OpenNoteDeepLinkHandler] ViewBackendService 返回的视图名称为空');
          return LocaleKeys.menuAppHeader_defaultNewNotebookName.tr();
        },
        (error) {
          Log.error('[OpenNoteDeepLinkHandler] ViewBackendService 获取视图失败: ${error.msg}');
          return LocaleKeys.menuAppHeader_defaultNewNotebookName.tr();
        },
      );
    } catch (e, stackTrace) {
      Log.error('[OpenNoteDeepLinkHandler] 通过 ViewBackendService 获取视图名称时出错: $e', stackTrace);
      return LocaleKeys.menuAppHeader_defaultNewNotebookName.tr();
    }
  }

  /// 调用 receive_published_collab API 接收发布的文档
  /// 返回 (是否成功, 错误信息, 接收后的viewId, 是否只读)
  Future<(bool, String, String, bool)> _receivePublishedCollab({
    required String publishedViewId,
    required String workspaceId,
  }) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[OpenNoteDeepLinkHandler] Base URL 为空');
        return (false, 'Base URL 为空', publishedViewId, true);
      }

      // 构建 API URL: /api/workspace/published/receive
      // 注意：后端 API 是在 /api/workspace scope 下定义的
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/published/receive',
      );

      // 获取 auth token
      final authToken = await _getAuthTokenFromUserService();
      if (authToken == null || authToken.isEmpty) {
        Log.warn('[OpenNoteDeepLinkHandler] Auth token 为空');
        return (false, 'Auth token 为空', publishedViewId, true);
      }

      // 生成目标 view_id
      final destViewId = _generateUuid();

      final requestBody = jsonEncode({
        'published_view_id': publishedViewId,
        'dest_workspace_id': workspaceId,
        'dest_view_id': destViewId,
      });

      Log.info('[OpenNoteDeepLinkHandler] 调用 receive API: $uri');
      Log.info('[OpenNoteDeepLinkHandler] 请求参数: $requestBody');

      final response = await http
          .post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: requestBody,
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      Log.info(
          '[OpenNoteDeepLinkHandler] receive API 响应: HTTP ${response.statusCode}');

      // 解析响应体（所有分支都需要）
      final responseBody = jsonDecode(response.body);
      Log.info('[OpenNoteDeepLinkHandler] receive API 响应体: $responseBody');

      if (response.statusCode == 200) {
        if (responseBody is Map<String, dynamic>) {
          final data = responseBody['data'];
          if (data is Map<String, dynamic>) {
            final viewId = data['view_id'] as String?;
            final isReadonly = data['is_readonly'] as bool? ?? true;
            Log.info(
                '[OpenNoteDeepLinkHandler] 接收成功: viewId=$viewId, isReadonly=$isReadonly');
            return (true, '', viewId ?? destViewId, isReadonly);
          }
        }
        return (true, '', destViewId, true);
      } else if (response.statusCode == 400) {
        // 可能已接收过，解析响应获取已接收的 view_id
        if (responseBody is Map<String, dynamic>) {
          final data = responseBody['data'];
          if (data is Map<String, dynamic>) {
            final viewId = data['view_id'] as String?;
            final isReadonly = data['is_readonly'] as bool? ?? true;
            return (true, '已接收过', viewId ?? publishedViewId, isReadonly);
          }
        }
        return (false, '已接收过', publishedViewId, true);
      } else {
        final error = responseBody is Map<String, dynamic>
            ? (responseBody['error'] as String? ?? '未知错误')
            : '未知错误';
        Log.warn('[OpenNoteDeepLinkHandler] 接收失败: $error');
        return (false, error, publishedViewId, true);
      }
    } catch (e, stackTrace) {
      Log.error('[OpenNoteDeepLinkHandler] 调用 receive API 时出错: $e', stackTrace);
      return (false, e.toString(), publishedViewId, true);
    }
  }

  /// 获取当前用户的工作区ID
  Future<String?> _getCurrentWorkspaceId() async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        return null;
      }

      // 构建 API URL: /api/user/workspaces
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/user/workspaces',
      );

      // 获取 auth token
      final authToken = await _getAuthTokenFromUserService();
      if (authToken == null || authToken.isEmpty) {
        Log.warn('[OpenNoteDeepLinkHandler] Auth token 为空');
        return null;
      }

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final data = body['data'];
          if (data is List && data.isNotEmpty) {
            final firstWorkspace = data[0];
            if (firstWorkspace is Map<String, dynamic>) {
              return firstWorkspace['workspace_id'] as String?;
            }
          }
        }
      }
    } catch (e, stackTrace) {
      Log.error('[OpenNoteDeepLinkHandler] 获取工作区信息时出错: $e', stackTrace);
    }
    return null;
  }

  /// 从用户服务获取 auth token
  Future<String?> _getAuthTokenFromUserService() async {
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      return userResult.fold(
        (user) => user.authToken,
        (error) {
          Log.warn('[OpenNoteDeepLinkHandler] 获取用户信息失败: $error');
          return null;
        },
      );
    } catch (e) {
      Log.error('[OpenNoteDeepLinkHandler] 获取 token 时出错: $e');
      return null;
    }
  }

  /// 生成 UUID v4
  String _generateUuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // 版本4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // 变体
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('-');
  }
}
