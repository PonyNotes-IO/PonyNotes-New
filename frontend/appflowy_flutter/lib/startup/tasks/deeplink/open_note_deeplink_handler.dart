import 'dart:async';

import 'package:appflowy/shared/af_user_profile_extension.dart';
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
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
    final isNotePath =
        host == 'note' || host == 'open' || path == 'note' || path == 'open';
    final hasViewId = uri.queryParameters.containsKey('viewId');
    
    return isNotePath && hasViewId;
  }

  @override
  Future<FlowyResult<void, FlowyError>> handle({
    required Uri uri,
    required DeepLinkStateHandler onStateChange,
  }) async {
    Log.info('📝 [OpenNoteDeepLinkHandler] 处理打开笔记深度链接: ${uri.toString()}');
    
    onStateChange(this, DeepLinkState.loading);

    try {
      // 从URI中获取参数
      final viewId = uri.queryParameters['viewId'];
      final targetWorkspaceId = uri.queryParameters['workspaceId'];
      final linkType = uri.queryParameters['type']; // 获取链接类型：share 或 publish
      
      if (viewId == null || viewId.isEmpty) {
        Log.error('📝 [OpenNoteDeepLinkHandler] viewId参数为空');
        onStateChange(this, DeepLinkState.error);
        return FlowyResult.failure(
          FlowyError()
            ..msg = 'viewId参数不能为空'
            ..code = ErrorCode.InvalidParams,
        );
      }

      Log.info('📝 [OpenNoteDeepLinkHandler] 准备打开笔记, viewId: $viewId, workspaceId: ${targetWorkspaceId ?? "(current)"}, type: ${linkType ?? "unknown"}');

      // workspaceId 仅作为后端识别上下文的参数，前端不再主动切换工作区，
      // 由 Rust 侧的 open_document / view 服务自行处理跨工作区打开逻辑。
      final workspaceId = targetWorkspaceId;

      // 如果是分享链接（type=share），尝试将当前用户添加到协作中，
      // 具体权限与视图可见性仍由后端控制。
      if (linkType == 'share' && workspaceId != null && workspaceId.isNotEmpty) {
        Log.info('📝 [OpenNoteDeepLinkHandler] 检测到分享链接，尝试添加用户到协作');
        await _addUserToCollaboration(
          workspaceId: workspaceId,
          viewId: viewId,
        );
      }

      // 直接通过 DocumentService 打开文档，不依赖 ViewBackendService.getView
      // 因为某些情况下 getView 可能获取不到，但 openDocument 可以成功
      Log.info('📝 [OpenNoteDeepLinkHandler] 直接通过 DocumentService 打开文档: $viewId');
      
      bool documentOpened = false;
      try {
        final docResult = await DocumentService().openDocument(
          documentId: viewId,
        );
        await docResult.fold(
          (_) async {
            Log.info('📝 [OpenNoteDeepLinkHandler] open_document 成功: $viewId');
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
        Log.error('📝 [OpenNoteDeepLinkHandler] 调用 open_document 时异常: $e', stackTrace);
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

      // 创建最小化的 ViewPB 对象，用于在UI中打开视图
      // 标题会在文档打开后由文档页面自动更新
      final minimalView = ViewPB()
        ..id = viewId
        ..name = LocaleKeys.menuAppHeader_defaultNewNotebookName.tr() // 默认名称，文档打开后会自动更新
        ..layout = ViewLayoutPB.Document;
      
      Log.info('📝 [OpenNoteDeepLinkHandler] 创建最小化视图对象: ${minimalView.id}');
          
          // 等待应用初始化完成后再打开视图
          // 使用WidgetsBinding确保在UI线程中执行
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              // 获取TabsBloc实例
              final navContext = AppGlobals.rootNavKey.currentState?.context;
              if (navContext == null) {
                Log.error('📝 [OpenNoteDeepLinkHandler] 无法获取BuildContext，应用可能未完全初始化');
                // 如果应用未初始化，延迟一段时间后重试
                await Future.delayed(const Duration(seconds: 1));
                final retryContext = AppGlobals.rootNavKey.currentState?.context;
                if (retryContext == null) {
                  Log.error('📝 [OpenNoteDeepLinkHandler] 重试后仍无法获取BuildContext');
                  return;
                }
            _openView(retryContext, minimalView);
              } else {
            _openView(navContext, minimalView);
              }
            } catch (e, stackTrace) {
              Log.error('📝 [OpenNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
            }
          });
          
          onStateChange(this, DeepLinkState.finish);
          return FlowyResult.success(null);
    } catch (e, stackTrace) {
      Log.error('📝 [OpenNoteDeepLinkHandler] 处理深度链接时出错: $e', stackTrace);
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
      Log.info('📝 [OpenNoteDeepLinkHandler] 开始打开视图: ${view.name} (${view.id})');

      // 通过 ActionNavigationBloc 触发打开逻辑，避免直接依赖 TabsBloc
      final actionBloc =
          context.read<ActionNavigationBloc?>();

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
        Log.info('📝 [OpenNoteDeepLinkHandler] 已通过 ActionNavigationBloc 发送打开请求');
      } else {
        // 兜底：如果 ActionNavigationBloc 不存在，再尝试直接使用 TabsBloc
        final tabsBloc = context.read<TabsBloc>();
        tabsBloc.openPlugin(view);
        Log.info('📝 [OpenNoteDeepLinkHandler] 通过 TabsBloc 打开视图');
      }
    } catch (e, stackTrace) {
      Log.error('📝 [OpenNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
    }
  }

  /// 将当前用户添加到协作中（用于分享链接）
  Future<void> _addUserToCollaboration({
    required String workspaceId,
    required String viewId,
  }) async {
    try {
      Log.info('📝 [OpenNoteDeepLinkHandler] 开始添加用户到协作, workspaceId: $workspaceId, viewId: $viewId');

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

      // 获取用户ID
      final userId = userProfile.id.toString();
      if (userId.isEmpty) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] 用户ID为空，跳过添加协作');
        return;
      }

      // 获取 auth token
      final authToken = userProfile.authToken;
      if (authToken == null || authToken.isEmpty) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] Auth token 为空，跳过添加协作');
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

      Log.info('📝 [OpenNoteDeepLinkHandler] 请求添加协作: $uri');

      // 发送 POST 请求
      final response = await http.post(
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

      Log.info('📝 [OpenNoteDeepLinkHandler] 添加协作响应状态: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        Log.info('📝 [OpenNoteDeepLinkHandler] 成功添加用户到协作');
      } else if (response.statusCode == 409) {
        // 409 表示用户已经在协作中，这是正常情况，不需要报错
        Log.info('📝 [OpenNoteDeepLinkHandler] 用户已在协作中');
      } else {
        Log.warn('📝 [OpenNoteDeepLinkHandler] 添加协作失败: HTTP ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      // 添加协作失败不应该阻止打开笔记，只记录错误
      Log.error(
        '📝 [OpenNoteDeepLinkHandler] 添加用户到协作时出错: $e',
        e,
        stackTrace,
      );
    }
  }
}

