import 'dart:async';
import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/shared/af_user_profile_extension.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

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
      
      if (viewId == null || viewId.isEmpty) {
        Log.error('📝 [OpenNoteDeepLinkHandler] viewId参数为空');
        onStateChange(this, DeepLinkState.error);
        return FlowyResult.failure(
          FlowyError()
            ..msg = 'viewId参数不能为空'
            ..code = ErrorCode.InvalidParams,
        );
      }

      Log.info('📝 [OpenNoteDeepLinkHandler] 准备打开笔记, viewId: $viewId, workspaceId: ${targetWorkspaceId ?? "(current)"}');

      // 获取当前工作区ID（如果未提供）
      String? workspaceId = targetWorkspaceId;
      if (workspaceId == null || workspaceId.isEmpty) {
        final workspaceResult = await FolderEventReadCurrentWorkspace().send();
        workspaceId = workspaceResult.fold(
          (workspace) => workspace.id,
          (error) {
            Log.warn('📝 [OpenNoteDeepLinkHandler] 无法获取当前工作区: $error');
            return null;
          },
        );
      }

      if (workspaceId == null || workspaceId.isEmpty) {
        Log.error('📝 [OpenNoteDeepLinkHandler] 工作区ID为空，无法继续');
        onStateChange(this, DeepLinkState.error);
        return FlowyResult.failure(
          FlowyError()
            ..msg = '工作区ID不能为空'
            ..code = ErrorCode.InvalidParams,
        );
      }

      // 如果带了 workspaceId，先切换到指定工作区
      if (targetWorkspaceId != null && targetWorkspaceId.isNotEmpty) {
        final rootContext = AppGlobals.rootNavKey.currentState?.context;
        UserWorkspaceBloc? userWorkspaceBloc;
        if (rootContext != null) {
          try {
            userWorkspaceBloc = rootContext.read<UserWorkspaceBloc>();
          } catch (e, stackTrace) {
            Log.warn(
              '📝 [OpenNoteDeepLinkHandler] 获取 UserWorkspaceBloc 失败，跳过工作区切换',
              e,
              stackTrace,
            );
          }
        }

        if (userWorkspaceBloc != null) {
          final current = userWorkspaceBloc.state.currentWorkspace?.workspaceId;
          if (current != targetWorkspaceId) {
            Log.info('📝 [OpenNoteDeepLinkHandler] 切换工作区到: $targetWorkspaceId');
            final workspaceType =
                userWorkspaceBloc.state.currentWorkspace?.workspaceType ??
                    WorkspaceTypePB.LocalW;
            userWorkspaceBloc.add(
              UserWorkspaceEvent.openWorkspace(
                workspaceId: targetWorkspaceId,
                workspaceType: workspaceType,
              ),
            );
            var retries = 10;
            while (retries-- > 0 &&
                userWorkspaceBloc.state.currentWorkspace?.workspaceId !=
                    targetWorkspaceId) {
              await Future.delayed(const Duration(milliseconds: 200));
            }
            Log.info('📝 [OpenNoteDeepLinkHandler] 工作区切换结果: ${userWorkspaceBloc.state.currentWorkspace?.workspaceId}');
          }
        } else {
          Log.warn(
            '📝 [OpenNoteDeepLinkHandler] 找不到 UserWorkspaceBloc，跳过工作区切换',
          );
        }
      }

      // 首先尝试通过 API 获取发布笔记内容
      final publishedContentResult = await _fetchPublishedNoteContent(
        workspaceId: workspaceId,
        viewId: viewId,
      );

      // 如果成功获取到发布内容，创建新笔记并打开
      if (publishedContentResult != null) {
        return await _createNoteFromPublishedContent(
          workspaceId: workspaceId,
          viewId: viewId,
          content: publishedContentResult,
          onStateChange: onStateChange,
        );
      }

      // 如果获取失败，尝试直接获取本地视图信息
      Log.info('📝 [OpenNoteDeepLinkHandler] 无法获取发布内容，尝试打开本地视图');
      final viewResult = await ViewBackendService.getView(viewId);
      
      return await viewResult.fold(
        (view) async {
          Log.info('📝 [OpenNoteDeepLinkHandler] 成功获取视图: ${view.name}');
          
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
                _openView(retryContext, view);
              } else {
                _openView(navContext, view);
              }
            } catch (e, stackTrace) {
              Log.error('📝 [OpenNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
            }
          });
          
          onStateChange(this, DeepLinkState.finish);
          return FlowyResult.success(null);
        },
        (error) async {
          Log.error('📝 [OpenNoteDeepLinkHandler] 获取视图失败: ${error.msg}');
          onStateChange(this, DeepLinkState.error);
          return FlowyResult.failure(error);
        },
      );
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

  /// 通过 API 获取发布笔记的内容
  Future<Map<String, dynamic>?> _fetchPublishedNoteContent({
    required String workspaceId,
    required String viewId,
  }) async {
    try {
      // 获取 base URL 和 auth token
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      
      if (baseUrl.isEmpty) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] Base URL 为空，跳过 API 请求');
        return null;
      }

      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) {
          Log.warn('📝 [OpenNoteDeepLinkHandler] 获取用户信息失败: $error');
          return null;
        },
      );

      if (userProfile == null) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] 用户信息为空，跳过 API 请求');
        return null;
      }

      final authToken = userProfile.authToken;
      if (authToken == null || authToken.isEmpty) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] Auth token 为空，跳过 API 请求');
        return null;
      }

      // 构建 API URL
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/sharing/workspace/$workspaceId/view/$viewId/access-details',
      );

      Log.info('📝 [OpenNoteDeepLinkHandler] 请求发布笔记内容: $uri');

      // 发送 HTTP GET 请求
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

      Log.info(
        '📝 [OpenNoteDeepLinkHandler] API 响应状态: ${response.statusCode}, 内容长度: ${response.body.length}',
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        
        // 检查响应 code
        final code = jsonData['code'] as int?;
        if (code != null && code != 0) {
          final message = jsonData['message'] as String? ?? '获取失败';
          Log.warn('📝 [OpenNoteDeepLinkHandler] API 返回错误: $message');
          return null;
        }

        // 返回数据部分
        final data = jsonData['data'] as Map<String, dynamic>?;
        if (data != null) {
          Log.info('📝 [OpenNoteDeepLinkHandler] 成功获取发布笔记内容');
          return data;
        } else {
          Log.warn('📝 [OpenNoteDeepLinkHandler] API 响应数据为空');
          return null;
        }
      } else if (response.statusCode == 404) {
        Log.info('📝 [OpenNoteDeepLinkHandler] 发布笔记不存在 (404)');
        return null;
      } else {
        Log.warn(
          '📝 [OpenNoteDeepLinkHandler] API 请求失败: HTTP ${response.statusCode}',
        );
        return null;
      }
    } catch (e, stackTrace) {
      Log.error(
        '📝 [OpenNoteDeepLinkHandler] 获取发布笔记内容时出错: $e',
        e,
        stackTrace,
      );
      return null;
    }
  }

  /// 从发布内容创建新笔记并打开
  Future<FlowyResult<void, FlowyError>> _createNoteFromPublishedContent({
    required String workspaceId,
    required String viewId,
    required Map<String, dynamic> content,
    required DeepLinkStateHandler onStateChange,
  }) async {
    try {
      Log.info('📝 [OpenNoteDeepLinkHandler] 开始从发布内容创建新笔记');

      // 获取笔记名称
      final noteName = content['name'] as String? ?? 
                      content['title'] as String? ?? 
                      '分享的笔记';

      // 获取笔记内容（可能是 markdown、JSON 或其他格式）
      final noteContent = content['content'] as String? ?? 
                         content['data'] as String? ?? 
                         '';

      // 获取当前工作区
      final workspaceResult = await FolderEventReadCurrentWorkspace().send();
      final currentWorkspaceId = workspaceResult.fold(
        (workspace) => workspace.id,
        (error) => workspaceId, // 使用传入的 workspaceId 作为 fallback
      );

      // 创建新笔记
      // 注意：这里假设内容可能是 Markdown 格式，如果是其他格式需要相应调整
      List<int>? initialDataBytes;
      if (noteContent.isNotEmpty) {
        try {
          // 尝试将内容作为 JSON 解析（如果是文档数据）
          final contentJson = jsonDecode(noteContent) as Map<String, dynamic>?;
          if (contentJson != null) {
            // 如果是 JSON 格式的文档数据，尝试转换为 bytes
            // 这里需要根据实际 API 返回的数据格式来调整
            // 暂时先记录日志，后续根据实际数据格式完善
            Log.info('📝 [OpenNoteDeepLinkHandler] 检测到 JSON 格式内容');
          }
        } catch (e) {
          // 如果不是 JSON，可能是 Markdown 或其他文本格式
          Log.info('📝 [OpenNoteDeepLinkHandler] 内容不是 JSON 格式，将作为文本处理');
        }
      }

      // 创建视图
      final createResult = await ViewBackendService.createView(
        layoutType: ViewLayoutPB.Document,
        parentViewId: currentWorkspaceId,
        name: noteName,
        openAfterCreate: true,
        initialDataBytes: initialDataBytes,
        section: ViewSectionPB.Public, // 创建在公共区域
      );

      return await createResult.fold(
        (view) async {
          Log.info('📝 [OpenNoteDeepLinkHandler] 成功创建笔记: ${view.name} (${view.id})');
          
          // 等待应用初始化完成后再打开视图
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              final navContext = AppGlobals.rootNavKey.currentState?.context;
              if (navContext == null) {
                Log.error('📝 [OpenNoteDeepLinkHandler] 无法获取BuildContext，应用可能未完全初始化');
                await Future.delayed(const Duration(seconds: 1));
                final retryContext = AppGlobals.rootNavKey.currentState?.context;
                if (retryContext == null) {
                  Log.error('📝 [OpenNoteDeepLinkHandler] 重试后仍无法获取BuildContext');
                  return;
                }
                _openView(retryContext, view);
              } else {
                _openView(navContext, view);
              }
            } catch (e, stackTrace) {
              Log.error('📝 [OpenNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
            }
          });

          onStateChange(this, DeepLinkState.finish);
          return FlowyResult.success(null);
        },
        (error) async {
          Log.error('📝 [OpenNoteDeepLinkHandler] 创建笔记失败: ${error.msg}');
          onStateChange(this, DeepLinkState.error);
          return FlowyResult.failure(error);
        },
      );
    } catch (e, stackTrace) {
      Log.error('📝 [OpenNoteDeepLinkHandler] 从发布内容创建笔记时出错: $e', stackTrace);
      onStateChange(this, DeepLinkState.error);
      return FlowyResult.failure(
        FlowyError()
          ..msg = '从发布内容创建笔记时出错: $e'
          ..code = ErrorCode.Internal,
      );
    }
  }
}

