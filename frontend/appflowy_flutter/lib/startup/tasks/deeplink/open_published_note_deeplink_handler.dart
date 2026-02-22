import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart' as uuid_lib;
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;

import '../../../env/cloud_env.dart';
import '../../../generated/locale_keys.g.dart';
import '../../../startup/startup.dart';
import '../app_widget.dart';

/// 处理发布笔记的深度链接
/// 支持的URI格式: https://ponynotes.io/p/{namespace}/{publish_name}
/// 或者: ponynotes://p/{namespace}/{publish_name}
class OpenPublishedNoteDeepLinkHandler extends DeepLinkHandler<void> {
  @override
  bool canHandle(Uri uri) {
    // 检查是否是发布笔记的深度链接
    final host = uri.host;
    final path = uri.path;

    // 支持的格式:
    // 1. https://ponynotes.io/p/{namespace}/{publish_name}
    // 2. ponynotes://p/{namespace}/{publish_name}
    final isPublishedPath = path.startsWith('/p/') ||
        host == 'p' ||
        path.startsWith('p/');

    return isPublishedPath;
  }

  @override
  Future<FlowyResult<void, FlowyError>> handle({
    required Uri uri,
    required DeepLinkStateHandler onStateChange,
  }) async {
    onStateChange(this, DeepLinkState.loading);

    try {
      // 解析路径获取 namespace 和 publish_name
      String namespace;
      String publishName;

      if (uri.scheme == 'https' || uri.scheme == 'http') {
        // https://ponynotes.io/p/{namespace}/{publish_name}
        final pathParts = uri.pathSegments;
        if (pathParts.length >= 3 && pathParts[0] == 'p') {
          namespace = pathParts[1];
          publishName = pathParts[2];
        } else {
          Log.error('[OpenPublishedNoteDeepLinkHandler] 无效的发布链接路径: ${uri.path}');
          onStateChange(this, DeepLinkState.error);
          return FlowyResult.failure(
            FlowyError()
              ..msg = '无效的发布链接格式'
              ..code = ErrorCode.InvalidParams,
          );
        }
      } else {
        // ponynotes://p/{namespace}/{publish_name}
        final pathParts = uri.pathSegments;
        if (pathParts.length >= 2 && pathParts[0] == 'p') {
          namespace = pathParts[1];
          publishName = pathParts.length > 2 ? pathParts[2] : '';
        } else {
          Log.error('[OpenPublishedNoteDeepLinkHandler] 无效的发布链接路径: ${uri.path}');
          onStateChange(this, DeepLinkState.error);
          return FlowyResult.failure(
            FlowyError()
              ..msg = '无效的发布链接格式'
              ..code = ErrorCode.InvalidParams,
          );
        }
      }

      if (publishName.isEmpty) {
        Log.error('[OpenPublishedNoteDeepLinkHandler] publish_name 为空');
        onStateChange(this, DeepLinkState.error);
        return FlowyResult.failure(
          FlowyError()
            ..msg = 'publish_name 不能为空'
            ..code = ErrorCode.InvalidParams,
        );
      }

      Log.info('[OpenPublishedNoteDeepLinkHandler] 处理发布链接: namespace=$namespace, publishName=$publishName');

      // 首先获取发布文档的 view_id
      final viewIdResult = await _getPublishedViewId(namespace, publishName);
      if (viewIdResult == null) {
        Log.error('[OpenPublishedNoteDeepLinkHandler] 无法获取发布文档信息');
        onStateChange(this, DeepLinkState.error);
        return FlowyResult.failure(
          FlowyError()
            ..msg = '发布文档不存在或已被取消发布'
            ..code = ErrorCode.RecordNotFound,
        );
      }

      final viewId = viewIdResult['viewId'] as String;
      final viewName = viewIdResult['name'] as String? ?? publishName;
      final destWorkspaceId = viewIdResult['workspaceId'] as String?;

      Log.info('[OpenPublishedNoteDeepLinkHandler] 获取到发布文档: viewId=$viewId, name=$viewName');

      // 获取当前工作区 ID
      final workspaceId = destWorkspaceId ?? await _getCurrentWorkspaceId();
      if (workspaceId == null || workspaceId.isEmpty) {
        Log.error('[OpenPublishedNoteDeepLinkHandler] 无法获取当前工作区');
        onStateChange(this, DeepLinkState.error);
        return FlowyResult.failure(
          FlowyError()
            ..msg = '无法获取当前工作区'
            ..code = ErrorCode.Internal,
        );
      }

      // 调用 receive_published_collab API
      // 这会：1. 将文档复制到用户工作区 2. 设置 is_locked = true（只读）3. 在 af_received_published_collab 表中创建记录
      final receiveResult = await _receivePublishedCollab(
        publishedViewId: viewId,
        workspaceId: workspaceId,
      );

      if (!receiveResult.$1) {
        Log.warn('[OpenPublishedNoteDeepLinkHandler] 接收发布文档失败: ${receiveResult.$2}');
        // 即使接收失败，也尝试打开文档（可能是已接收过的）
      }

      // 打开复制的文档
      final receivedViewId = receiveResult.$3;
      final isReadonly = receiveResult.$4;

      Log.info('[OpenPublishedNoteDeepLinkHandler] 打开发布文档: viewId=$receivedViewId, isReadonly=$isReadonly');

      // 创建最小化的 ViewPB 对象
      final minimalView = ViewPB()
        ..id = receivedViewId
        ..name = viewName
        ..layout = ViewLayoutPB.Document;

      // 等待应用初始化完成后再打开视图
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final navContext = AppGlobals.rootNavKey.currentState?.context;
          if (navContext == null) {
            Log.error('[OpenPublishedNoteDeepLinkHandler] 无法获取BuildContext');
            await Future.delayed(const Duration(seconds: 1));
            final retryContext = AppGlobals.rootNavKey.currentState?.context;
            if (retryContext == null) {
              Log.error('[OpenPublishedNoteDeepLinkHandler] 重试后仍无法获取BuildContext');
              return;
            }
            _openView(retryContext, minimalView);
          } else {
            _openView(navContext, minimalView);
          }
        } catch (e, stackTrace) {
          Log.error('[OpenPublishedNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
        }
      });

      onStateChange(this, DeepLinkState.finish);
      return FlowyResult.success(null);
    } catch (e, stackTrace) {
      Log.error('[OpenPublishedNoteDeepLinkHandler] 处理深度链接时出错: $e', stackTrace);
      onStateChange(this, DeepLinkState.error);
      return FlowyResult.failure(
        FlowyError()
          ..msg = '处理深度链接时出错: $e'
          ..code = ErrorCode.Internal,
      );
    }
  }

  /// 获取发布的文档信息
  Future<Map<String, dynamic>?> _getPublishedViewId(
    String namespace,
    String publishName,
  ) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[OpenPublishedNoteDeepLinkHandler] Base URL 为空');
        return null;
      }

      // 构建 API URL: /api/workspace/v1/published/{namespace}/{publish_name}
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/v1/published/$namespace/$publishName',
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
              final view = metadata['view'];
              if (view is Map<String, dynamic>) {
                final viewId = view['view_id'] as String?;
                final name = view['name'] as String?;
                final workspaceId = metadata['workspace_id'] as String?;
                if (viewId != null) {
                  return {
                    'viewId': viewId,
                    'name': name ?? publishName,
                    'workspaceId': workspaceId,
                  };
                }
              }
            }
          }
        }
      } else if (response.statusCode == 404) {
        Log.info('[OpenPublishedNoteDeepLinkHandler] 发布文档不存在');
      } else {
        Log.warn('[OpenPublishedNoteDeepLinkHandler] 获取发布信息失败: HTTP ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      Log.error('[OpenPublishedNoteDeepLinkHandler] 获取发布信息时出错: $e', stackTrace);
    }
    return null;
  }

  /// 获取当前工作区 ID
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
      final authToken = await _getAuthToken();
      if (authToken == null || authToken.isEmpty) {
        Log.warn('[OpenPublishedNoteDeepLinkHandler] Auth token 为空');
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
      Log.error('[OpenPublishedNoteDeepLinkHandler] 获取工作区信息时出错: $e', stackTrace);
    }
    return null;
  }

  /// 调用 receive_published_collab API 接收发布的文档
  Future<(bool, String, String, bool)> _receivePublishedCollab({
    required String publishedViewId,
    required String workspaceId,
  }) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[OpenPublishedNoteDeepLinkHandler] Base URL 为空');
        return (false, 'Base URL 为空', publishedViewId, true);
      }

      // 构建 API URL: /api/workspace/published/receive
      // 注意：后端 API 是在 /api/workspace scope 下定义的
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/published/receive',
      );

      // 获取 auth token
      final authToken = await _getAuthToken();
      if (authToken == null || authToken.isEmpty) {
        Log.warn('[OpenPublishedNoteDeepLinkHandler] Auth token 为空');
        return (false, 'Auth token 为空', publishedViewId, true);
      }

      // 生成目标 view_id
      final destViewId = const uuid_lib.Uuid().v4();

      final requestBody = jsonEncode({
        'published_view_id': publishedViewId,
        'dest_workspace_id': workspaceId,
        'dest_view_id': destViewId,
      });

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: requestBody,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      if (response.body.isEmpty) {
        Log.error('[OpenPublishedNoteDeepLinkHandler] 服务器返回空响应体');
        return (false, '服务器返回空响应 (HTTP ${response.statusCode})', publishedViewId, true);
      }

      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (responseBody is Map<String, dynamic>) {
          final data = responseBody['data'];
          if (data is Map<String, dynamic>) {
            final viewId = data['view_id'] as String?;
            final isReadonly = data['is_readonly'] as bool? ?? true;
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
        Log.warn('[OpenPublishedNoteDeepLinkHandler] 接收失败: $error');
        return (false, error, publishedViewId, true);
      }
    } catch (e, stackTrace) {
      Log.error('[OpenPublishedNoteDeepLinkHandler] 调用 receive API 时出错: $e', stackTrace);
      return (false, e.toString(), publishedViewId, true);
    }
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

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
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
          if (data is Map<String, dynamic>) {
            final token = data['token'] as String?;
            return token;
          }
        }
      }
    } catch (e) {
      Log.error('[OpenPublishedNoteDeepLinkHandler] 获取 token 时出错: $e');
    }
    return null;
  }

  /// 打开视图
  void _openView(BuildContext context, ViewPB view) {
    try {
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
        final tabsBloc = context.read<TabsBloc>();
        tabsBloc.openPlugin(view);
      }
    } catch (e, stackTrace) {
      Log.error('[OpenPublishedNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
    }
  }
}

